// Package recipeapi integrates recipe-api.com as a curated-recipe source for
// the hybrid /v1/recipes flow: curated matches when the catalog has them,
// Claude generation otherwise. Search/browse calls are free; each unique
// recipe detail costs 1 credit, so detail fetches are capped per request and
// any 429 puts the whole curated path into a cool-down.
package recipeapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
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

// ErrUnavailable means the curated path can't serve this request (unmappable
// dietary/allergy constraints, credit cool-down, no matches). Callers fall
// back to Claude; it is never a user-facing error.
var ErrUnavailable = errors.New("recipe-api unavailable for this request")

type Client struct {
	apiKey string
	base   string
	http   *http.Client

	mu           sync.Mutex
	ingredients  map[string]resolvedIngredient // lowercased query -> resolution ("" id = known miss)
	blockedUntil time.Time
}

type resolvedIngredient struct {
	ID       string
	Category string
}

func NewClient(apiKey string) *Client {
	return &Client{
		apiKey:      apiKey,
		base:        defaultBaseURL,
		http:        &http.Client{Timeout: 20 * time.Second},
		ingredients: map[string]resolvedIngredient{},
	}
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

	anchors := c.resolveAnchors(ctx, input.Ingredients)
	if len(anchors) == 0 {
		return nil, fmt.Errorf("%w: no detected ingredients resolved", ErrUnavailable)
	}

	// ingredients= is ALL-match, so start specific and relax: 3 anchors, 2, 1.
	var candidates []searchResult
	for n := min(3, len(anchors)); n >= 1; n-- {
		results, err := c.search(ctx, anchors[:n], plan)
		if err != nil {
			return nil, err
		}
		if len(results) > 0 {
			candidates = results
			break
		}
	}

	var recipes []anthropic.Recipe
	for _, cand := range candidates {
		if len(recipes) >= maxRecipes {
			break
		}
		if !cand.passes(plan) {
			continue
		}
		detail, err := c.detail(ctx, cand.ID)
		if err != nil {
			if errors.Is(err, ErrUnavailable) {
				break // credits gone mid-request: keep what we have
			}
			continue // one bad recipe shouldn't sink the rest
		}
		recipes = append(recipes, detail)
	}
	return recipes, nil
}

// resolveAnchors maps free-text detected names to ingredient UUIDs and orders
// them so proteins, then produce/staples, lead the ALL-match search.
func (c *Client) resolveAnchors(ctx context.Context, names []string) []string {
	if len(names) > 8 {
		names = names[:8] // bound lookup fan-out per request
	}
	resolved := make([]resolvedIngredient, len(names))
	var wg sync.WaitGroup
	sem := make(chan struct{}, 4)
	for i, name := range names {
		wg.Add(1)
		go func(i int, name string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			resolved[i] = c.resolveIngredient(ctx, name)
		}(i, name)
	}
	wg.Wait()

	var hits []resolvedIngredient
	for _, r := range resolved {
		if r.ID != "" {
			hits = append(hits, r)
		}
	}
	sort.SliceStable(hits, func(a, b int) bool {
		return categoryRank(hits[a].Category) < categoryRank(hits[b].Category)
	})
	ids := make([]string, len(hits))
	for i, h := range hits {
		ids[i] = h.ID
	}
	return ids
}

func categoryRank(category string) int {
	c := strings.ToLower(category)
	switch {
	case strings.Contains(c, "meat"), strings.Contains(c, "poultry"),
		strings.Contains(c, "seafood"), strings.Contains(c, "fish"):
		return 0
	case strings.Contains(c, "vegetable"), strings.Contains(c, "legume"),
		strings.Contains(c, "grain"), strings.Contains(c, "pasta"):
		return 1
	default:
		return 2
	}
}

func (c *Client) resolveIngredient(ctx context.Context, name string) resolvedIngredient {
	key := strings.ToLower(strings.TrimSpace(name))
	c.mu.Lock()
	if r, ok := c.ingredients[key]; ok {
		c.mu.Unlock()
		return r
	}
	c.mu.Unlock()

	r := c.lookupIngredient(ctx, key)
	// Vision names are often compound ("cheddar cheese"); retry on the head
	// noun before giving up.
	if r.ID == "" {
		if words := strings.Fields(key); len(words) > 1 {
			r = c.lookupIngredient(ctx, words[len(words)-1])
		}
	}
	c.mu.Lock()
	c.ingredients[key] = r // cache misses too — the catalog is stable
	c.mu.Unlock()
	return r
}

func (c *Client) lookupIngredient(ctx context.Context, q string) resolvedIngredient {
	var resp struct {
		Data []struct {
			ID       string `json:"id"`
			Name     string `json:"name"`
			Category string `json:"category"`
		} `json:"data"`
	}
	params := url.Values{"q": {q}, "per_page": {"1"}}
	if err := c.get(ctx, "/ingredients", params, &resp); err != nil || len(resp.Data) == 0 {
		return resolvedIngredient{}
	}
	return resolvedIngredient{ID: resp.Data[0].ID, Category: resp.Data[0].Category}
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

func (c *Client) search(ctx context.Context, ingredientIDs []string, plan searchPlan) ([]searchResult, error) {
	params := url.Values{
		"ingredients": {strings.Join(ingredientIDs, ",")},
		"per_page":    {"20"},
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

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
