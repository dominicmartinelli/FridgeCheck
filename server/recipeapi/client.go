// Package recipeapi integrates recipe-api.com as a curated-recipe source for
// the hybrid /v1/recipes flow: curated matches when the catalog has them,
// Claude generation otherwise. Search/browse calls are free; each unique
// recipe detail costs 1 credit, so detail fetches are capped per request and
// any 429 puts the whole curated path into a cool-down.
//
// Matching uses the free-text q= search (recipe name/description). The
// /ingredients endpoint is a USDA *nutrition* database whose UUIDs are a
// different ID space from the recipe ingredient graph, so it can't be used to
// resolve names for the ingredients= filter — q= is the workable path.
package recipeapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"fridgecheck/anthropic"
)

const defaultBaseURL = "https://recipe-api.com/api/v1"

// Per-request bounds. q-searches are free but rate-limited per minute, so cap
// how many ingredients we probe; detail fetches cost 1 credit each.
const (
	maxIngredientSearches = 6
	searchPageSize        = 20
)

// ErrUnavailable means the curated path can't serve this request (unmappable
// dietary/allergy constraints, credit cool-down, no matches). Callers fall
// back to Claude; it is never a user-facing error.
var ErrUnavailable = errors.New("recipe-api unavailable for this request")

type Client struct {
	apiKey string
	base   string
	http   *http.Client

	mu           sync.Mutex
	blockedUntil time.Time
}

func NewClient(apiKey string) *Client {
	return &Client{
		apiKey: apiKey,
		base:   defaultBaseURL,
		http:   &http.Client{Timeout: 20 * time.Second},
	}
}

// Generic pantry staples produce noisy q-search matches (q=butter →
// buttercream desserts) and rarely define a dish, so they're skipped as
// search anchors.
var genericStaples = map[string]bool{
	"salt": true, "pepper": true, "water": true, "sugar": true,
	"oil": true, "olive oil": true, "vegetable oil": true, "butter": true,
	"flour": true, "milk": true, "ice": true,
}

// Dietary restrictions the API can express directly as flags.
var dietaryFlagMap = map[string]string{
	"Vegetarian":  "Vegetarian",
	"Vegan":       "Vegan",
	"Gluten-Free": "Gluten-Free",
}

// Allergies enforced by requiring the matching "-Free" flag on the recipe.
// Allergies absent from this map can't be guaranteed against the catalog, so
// the curated path is skipped entirely (Claude handles them in the prompt).
var allergyFlagMap = map[string]string{
	"Nuts":    "Nut-Free",
	"Peanuts": "Peanut-Free",
	"Gluten":  "Gluten-Free",
	"Dairy":   "Dairy-Free",
	"Eggs":    "Egg-Free",
	"Soy":     "Soy-Free",
	"Wheat":   "Gluten-Free",
}

type searchPlan struct {
	dietaryFlags  []string // dietary= query param
	requiredFlags []string // recipe must carry all of these
	maxCarbs      int      // 0 = no filter
	maxFat        int
	cuisine       string
	allergyWords  []string // lowercase keywords matched against not_suitable_for
}

// planFor maps app preferences onto API filters. ok=false means a constraint
// can't be expressed safely and the curated path must be skipped.
func planFor(input anthropic.RecipeInput) (searchPlan, bool) {
	var p searchPlan
	for _, a := range input.Allergies {
		flag, known := allergyFlagMap[a]
		if !known {
			return p, false // e.g. Shellfish, Fish, Sesame
		}
		p.requiredFlags = append(p.requiredFlags, flag)
		p.allergyWords = append(p.allergyWords, strings.TrimSuffix(strings.ToLower(a), "s"))
	}
	for _, d := range input.DietaryRestrictions {
		switch d {
		case "Keto":
			p.maxCarbs = 15
		case "Low-Carb":
			p.maxCarbs = 30
		case "Low-Fat":
			p.maxFat = 15
		case "Mediterranean":
			p.cuisine = "Mediterranean"
		default:
			flag, known := dietaryFlagMap[d]
			if !known {
				return p, false // e.g. Paleo
			}
			p.dietaryFlags = append(p.dietaryFlags, flag)
		}
	}
	p.dietaryFlags = append(p.dietaryFlags, p.requiredFlags...)
	return p, true
}

// anchorNames picks the ingredients worth searching on: drop generic staples,
// dedupe, and cap the count to bound rate-limit exposure.
func anchorNames(ingredients []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, raw := range ingredients {
		name := strings.TrimSpace(raw)
		key := strings.ToLower(name)
		if name == "" || genericStaples[key] || seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, name)
		if len(out) >= maxIngredientSearches {
			break
		}
	}
	return out
}

// FindByIngredients returns up to maxRecipes curated recipes matching the
// detected ingredients and preferences, mapped to the app's recipe shape.
func (c *Client) FindByIngredients(ctx context.Context, input anthropic.RecipeInput, maxRecipes int) ([]anthropic.Recipe, error) {
	c.mu.Lock()
	blocked := time.Now().Before(c.blockedUntil)
	c.mu.Unlock()
	if blocked {
		return nil, fmt.Errorf("%w: credit/rate cool-down active", ErrUnavailable)
	}

	plan, ok := planFor(input)
	if !ok {
		return nil, fmt.Errorf("%w: preferences not expressible as catalog filters", ErrUnavailable)
	}

	anchors := anchorNames(input.Ingredients)
	if len(anchors) == 0 {
		return nil, fmt.Errorf("%w: no searchable ingredients", ErrUnavailable)
	}

	// Free-text search each anchor and rank recipes by overlap — how many of
	// the user's ingredients each recipe matches. A recipe surfacing for
	// chicken AND rice AND spinach is a far better fridge match than one that
	// only matched a single ingredient.
	overlap := map[string]int{}
	byID := map[string]searchResult{}
	var searchHits int
	for _, name := range anchors {
		results, err := c.qSearch(ctx, name, plan)
		if err != nil {
			if errors.Is(err, ErrUnavailable) {
				break // 429 cool-down: proceed with whatever we gathered
			}
			continue // one failed search shouldn't sink the rest
		}
		searchHits += len(results)
		for _, r := range results {
			overlap[r.ID]++
			byID[r.ID] = r
		}
	}

	candidates := make([]searchResult, 0, len(byID))
	for id := range byID {
		candidates = append(candidates, byID[id])
	}
	sort.SliceStable(candidates, func(a, b int) bool {
		return overlap[candidates[a].ID] > overlap[candidates[b].ID]
	})

	var recipes []anthropic.Recipe
	var passed, detailErrors, topOverlap int
	creditBlocked := false
	for _, cand := range candidates {
		if len(recipes) >= maxRecipes {
			break
		}
		if !cand.passes(plan) {
			continue
		}
		passed++
		detail, err := c.detail(ctx, cand.ID)
		if err != nil {
			if errors.Is(err, ErrUnavailable) {
				creditBlocked = true
				break // credits gone mid-request: keep what we have
			}
			detailErrors++
			continue
		}
		if overlap[cand.ID] > topOverlap {
			topOverlap = overlap[cand.ID]
		}
		recipes = append(recipes, detail)
	}

	slog.Info("recipe-api diag",
		"anchors", len(anchors), "search_hits", searchHits,
		"unique_candidates", len(candidates), "passed_filters", passed,
		"top_overlap", topOverlap, "detail_errors", detailErrors,
		"credit_blocked", creditBlocked, "returned", len(recipes))
	return recipes, nil
}

type searchResult struct {
	ID      string `json:"id"`
	Dietary struct {
		Flags          []string `json:"flags"`
		NotSuitableFor []string `json:"not_suitable_for"`
	} `json:"dietary"`
}

// passes re-checks constraints on the recipe itself; the dietary= search
// filter is treated as advisory, not trusted for allergy safety.
func (r searchResult) passes(plan searchPlan) bool {
	flags := make(map[string]bool, len(r.Dietary.Flags))
	for _, f := range r.Dietary.Flags {
		flags[f] = true
	}
	for _, required := range plan.requiredFlags {
		if !flags[required] {
			return false
		}
	}
	for _, nsf := range r.Dietary.NotSuitableFor {
		lower := strings.ToLower(nsf)
		for _, w := range plan.allergyWords {
			if strings.Contains(lower, w) {
				return false
			}
		}
	}
	return true
}

func (c *Client) qSearch(ctx context.Context, name string, plan searchPlan) ([]searchResult, error) {
	params := url.Values{
		"q":        {name},
		"per_page": {strconv.Itoa(searchPageSize)},
	}
	if len(plan.dietaryFlags) > 0 {
		params.Set("dietary", strings.Join(plan.dietaryFlags, ","))
	}
	if plan.maxCarbs > 0 {
		params.Set("max_carbs", strconv.Itoa(plan.maxCarbs))
	}
	if plan.maxFat > 0 {
		params.Set("max_fat", strconv.Itoa(plan.maxFat))
	}
	if plan.cuisine != "" {
		params.Set("cuisine", plan.cuisine)
	}
	var resp struct {
		Data []searchResult `json:"data"`
	}
	if err := c.get(ctx, "/recipes", params, &resp); err != nil {
		return nil, err
	}
	return resp.Data, nil
}

type detailRecipe struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Cuisine     string `json:"cuisine"`
	Difficulty  string `json:"difficulty"`
	Meta        struct {
		ActiveTime  string `json:"active_time"`
		PassiveTime string `json:"passive_time"`
	} `json:"meta"`
	Ingredients []struct {
		Items []struct {
			Name        string   `json:"name"`
			Quantity    *float64 `json:"quantity"`
			Unit        *string  `json:"unit"`
			Preparation *string  `json:"preparation"`
		} `json:"items"`
	} `json:"ingredients"`
	Instructions []struct {
		StepNumber int    `json:"step_number"`
		Text       string `json:"text"`
	} `json:"instructions"`
	Nutrition struct {
		PerServing struct {
			Calories      *float64 `json:"calories"`
			ProteinG      *float64 `json:"protein_g"`
			CarbohydrateG *float64 `json:"carbohydrates_g"`
			FatG          *float64 `json:"fat_g"`
		} `json:"per_serving"`
	} `json:"nutrition"`
}

func (c *Client) detail(ctx context.Context, id string) (anthropic.Recipe, error) {
	var resp struct {
		Data detailRecipe `json:"data"`
	}
	if err := c.get(ctx, "/recipes/"+id, nil, &resp); err != nil {
		return anthropic.Recipe{}, err
	}
	return mapRecipe(resp.Data), nil
}

func mapRecipe(d detailRecipe) anthropic.Recipe {
	r := anthropic.Recipe{
		Title:       d.Name,
		Summary:     d.Description,
		CuisineType: d.Cuisine,
		PrepTime:    isoMinutes(d.Meta.ActiveTime),
		CookTime:    isoMinutes(d.Meta.PassiveTime),
		Source:      "curated",
	}
	switch d.Difficulty {
	case "Easy":
		r.Difficulty = "Easy"
	case "Intermediate":
		r.Difficulty = "Medium"
	default: // Advanced, Professional
		r.Difficulty = "Hard"
	}
	for _, group := range d.Ingredients {
		for _, item := range group.Items {
			r.Ingredients = append(r.Ingredients, formatIngredient(
				item.Name, item.Quantity, item.Unit, item.Preparation))
		}
	}
	sort.SliceStable(d.Instructions, func(a, b int) bool {
		return d.Instructions[a].StepNumber < d.Instructions[b].StepNumber
	})
	for _, step := range d.Instructions {
		r.Steps = append(r.Steps, step.Text)
	}
	ps := d.Nutrition.PerServing
	if ps.Calories != nil {
		r.NutritionalInfo = fmt.Sprintf("Approx. %.0f cal", *ps.Calories)
		if ps.ProteinG != nil {
			r.NutritionalInfo += fmt.Sprintf(", %.0fg protein", *ps.ProteinG)
		}
		if ps.CarbohydrateG != nil {
			r.NutritionalInfo += fmt.Sprintf(", %.0fg carbs", *ps.CarbohydrateG)
		}
		if ps.FatG != nil {
			r.NutritionalInfo += fmt.Sprintf(", %.0fg fat", *ps.FatG)
		}
		r.NutritionalInfo += " per serving (USDA-verified)"
	}
	return r
}

func formatIngredient(name string, quantity *float64, unit, preparation *string) string {
	var b strings.Builder
	if quantity != nil && *quantity > 0 {
		b.WriteString(strconv.FormatFloat(*quantity, 'f', -1, 64))
		if unit != nil && *unit != "" {
			b.WriteString(" " + *unit)
		}
		b.WriteString(" ")
	}
	b.WriteString(name)
	if preparation != nil && *preparation != "" {
		b.WriteString(", " + *preparation)
	}
	return b.String()
}

var isoDuration = regexp.MustCompile(`^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$`)

func isoMinutes(s string) int {
	m := isoDuration.FindStringSubmatch(s)
	if m == nil {
		return 0
	}
	days, _ := strconv.Atoi(zeroIfEmpty(m[1]))
	hours, _ := strconv.Atoi(zeroIfEmpty(m[2]))
	mins, _ := strconv.Atoi(zeroIfEmpty(m[3]))
	return days*24*60 + hours*60 + mins
}

func zeroIfEmpty(s string) string {
	if s == "" {
		return "0"
	}
	return s
}

func (c *Client) get(ctx context.Context, path string, params url.Values, out any) error {
	u := c.base + path
	if len(params) > 0 {
		u += "?" + params.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("X-API-Key", c.apiKey)

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode == http.StatusTooManyRequests {
		c.blockFor(parseErrorCode(body))
		return fmt.Errorf("%w: http 429 %s", ErrUnavailable, parseErrorCode(body))
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("recipe-api http %d: %s", resp.StatusCode, truncate(string(body), 200))
	}
	return json.Unmarshal(body, out)
}

// blockFor pauses the curated path after a 429: briefly for per-minute rate
// limits, much longer when the plan's credit pool is exhausted.
func (c *Client) blockFor(code string) {
	cooldown := 30 * time.Second
	if strings.Contains(code, "LIMIT_EXCEEDED") {
		cooldown = 6 * time.Hour
	}
	c.mu.Lock()
	if until := time.Now().Add(cooldown); until.After(c.blockedUntil) {
		c.blockedUntil = until
	}
	c.mu.Unlock()
}

func parseErrorCode(body []byte) string {
	var e struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	_ = json.Unmarshal(body, &e)
	return e.Error.Code
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
