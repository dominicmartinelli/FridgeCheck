package anthropic

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"
)

const endpoint = "https://api.anthropic.com/v1/messages"

// ErrTruncated is returned when the model stopped because it hit max_tokens.
// The partial response is unusable (incomplete JSON), so callers should
// surface this as a distinct error rather than a generic upstream failure.
var ErrTruncated = errors.New("anthropic response truncated at max_tokens")

type Client struct {
	apiKey string
	http   *http.Client
}

func NewClient(apiKey string) *Client {
	return &Client{
		apiKey: apiKey,
		http:   &http.Client{Timeout: 5 * time.Minute},
	}
}

type Ingredient struct {
	Name              string `json:"name"`
	Category          string `json:"category"`
	EstimatedQuantity string `json:"estimatedQuantity"`
}

type Recipe struct {
	Title           string   `json:"title"`
	Summary         string   `json:"summary"`
	Ingredients     []string `json:"ingredients"`
	Steps           []string `json:"steps"`
	PrepTime        int      `json:"prepTime"`
	CookTime        int      `json:"cookTime"`
	NutritionalInfo string   `json:"nutritionalInfo"`
	CuisineType     string   `json:"cuisineType"`
	Difficulty      string   `json:"difficulty"`
}

type RecipeInput struct {
	Ingredients          []string `json:"ingredients"`
	DietaryRestrictions  []string `json:"dietaryRestrictions"`
	Allergies            []string `json:"allergies"`
	CuisinePreferences   []string `json:"cuisinePreferences"`
	ServingSize          int      `json:"servingSize"`
	PantryItems          []string `json:"pantryItems"`
}

type Usage struct {
	InputTokens  int
	OutputTokens int
}

type contentBlock struct {
	Type   string      `json:"type"`
	Text   string      `json:"text,omitempty"`
	Source *imgSource  `json:"source,omitempty"`
}

type imgSource struct {
	Type      string `json:"type"`
	MediaType string `json:"media_type"`
	Data      string `json:"data"`
}

type message struct {
	Role    string      `json:"role"`
	Content interface{} `json:"content"` // []contentBlock for scan, string for recipes
}

type requestBody struct {
	Model        string        `json:"model"`
	MaxTokens    int           `json:"max_tokens"`
	Messages     []message     `json:"messages"`
	OutputConfig *outputConfig `json:"output_config,omitempty"`
}

// outputConfig enforces structured outputs: the API guarantees the response
// is valid JSON matching the schema, so no "only return JSON" prompt
// boilerplate or markdown-fence stripping is needed. Requires a model with
// structured-outputs support (Haiku 4.5, Sonnet 4.6, or newer — NOT Sonnet 4.5).
type outputConfig struct {
	Format outputFormat `json:"format"`
}

type outputFormat struct {
	Type   string          `json:"type"`
	Schema json.RawMessage `json:"schema"`
}

const ingredientsSchema = `{
  "type": "object",
  "properties": {
    "ingredients": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "category": {"type": "string", "enum": ["Produce", "Dairy", "Meat", "Seafood", "Grains", "Condiments", "Beverages", "Snacks", "Frozen", "Other"]},
          "estimatedQuantity": {"type": "string", "description": "Estimated amount, e.g. '2 pieces', '1 bag', '500ml'"}
        },
        "required": ["name", "category", "estimatedQuantity"],
        "additionalProperties": false
      }
    }
  },
  "required": ["ingredients"],
  "additionalProperties": false
}`

const recipesSchema = `{
  "type": "object",
  "properties": {
    "recipes": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "title": {"type": "string"},
          "summary": {"type": "string", "description": "Brief 1-2 sentence description"},
          "ingredients": {"type": "array", "items": {"type": "string", "description": "Ingredient with amount"}},
          "steps": {"type": "array", "items": {"type": "string"}},
          "prepTime": {"type": "integer", "description": "Minutes"},
          "cookTime": {"type": "integer", "description": "Minutes"},
          "nutritionalInfo": {"type": "string", "description": "e.g. 'Approx. 450 cal, 25g protein, 35g carbs, 18g fat per serving'"},
          "cuisineType": {"type": "string"},
          "difficulty": {"type": "string", "enum": ["Easy", "Medium", "Hard"]}
        },
        "required": ["title", "summary", "ingredients", "steps", "prepTime", "cookTime", "nutritionalInfo", "cuisineType", "difficulty"],
        "additionalProperties": false
      }
    }
  },
  "required": ["recipes"],
  "additionalProperties": false
}`

type responseUsage struct {
	InputTokens  int `json:"input_tokens"`
	OutputTokens int `json:"output_tokens"`
}

type responseBody struct {
	Content []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	StopReason string        `json:"stop_reason"`
	Usage      responseUsage `json:"usage"`
}

func (c *Client) AnalyzeImages(ctx context.Context, imagesB64 []string, model string) ([]Ingredient, Usage, error) {
	blocks := make([]contentBlock, 0, len(imagesB64)+1)
	for _, data := range imagesB64 {
		blocks = append(blocks, contentBlock{
			Type:   "image",
			Source: &imgSource{Type: "base64", MediaType: "image/jpeg", Data: data},
		})
	}
	countWord := "this image"
	if len(imagesB64) != 1 {
		countWord = fmt.Sprintf("these %d images", len(imagesB64))
	}
	blocks = append(blocks, contentBlock{
		Type: "text",
		Text: fmt.Sprintf("Analyze %s of a fridge/food items. Identify all visible food items and ingredients across all images. Deduplicate items that appear in multiple images. Estimate the quantity of each item. Only list items you can actually see — if no food items are clearly visible, return an empty list.", countWord),
	})

	text, usage, err := c.call(ctx, requestBody{
		Model: model,
		// Headroom for the long ingredient lists a 15-photo scan can produce;
		// this is a cap, not spend — only generated tokens are billed.
		MaxTokens:    4096,
		Messages:     []message{{Role: "user", Content: blocks}},
		OutputConfig: &outputConfig{Format: outputFormat{Type: "json_schema", Schema: json.RawMessage(ingredientsSchema)}},
	})
	if err != nil {
		return nil, usage, err
	}
	var parsed struct {
		Ingredients []Ingredient `json:"ingredients"`
	}
	if err := json.Unmarshal([]byte(extractJSON(text)), &parsed); err != nil {
		return nil, usage, fmt.Errorf("decode ingredients: %w (raw: %s)", err, text)
	}
	return parsed.Ingredients, usage, nil
}

func (c *Client) GenerateRecipes(ctx context.Context, input RecipeInput, model string) ([]Recipe, Usage, error) {
	parts := []string{fmt.Sprintf("I have these ingredients available: %s.", strings.Join(input.Ingredients, ", "))}
	if len(input.PantryItems) > 0 {
		parts = append(parts, fmt.Sprintf("I also have these pantry staples: %s.", strings.Join(input.PantryItems, ", ")))
	}
	if len(input.DietaryRestrictions) > 0 {
		parts = append(parts, fmt.Sprintf("Dietary restrictions: %s.", strings.Join(input.DietaryRestrictions, ", ")))
	}
	if len(input.Allergies) > 0 {
		parts = append(parts, fmt.Sprintf("Allergies (must avoid): %s.", strings.Join(input.Allergies, ", ")))
	}
	if len(input.CuisinePreferences) > 0 {
		parts = append(parts, fmt.Sprintf("Preferred cuisines: %s.", strings.Join(input.CuisinePreferences, ", ")))
	}
	parts = append(parts, fmt.Sprintf("Serving size: %d people.", input.ServingSize))
	parts = append(parts, `
Suggest 3 recipes I can make using ONLY the ingredients listed above. Do not suggest recipes that require significant ingredients not in the list. You may assume basic pantry staples (salt, pepper, oil, water, common spices) are available. Provide complete step-by-step instructions, keeping each step to one short sentence.`)

	text, usage, err := c.call(ctx, requestBody{
		Model:        model,
		MaxTokens:    4096,
		Messages:     []message{{Role: "user", Content: strings.Join(parts, "\n")}},
		OutputConfig: &outputConfig{Format: outputFormat{Type: "json_schema", Schema: json.RawMessage(recipesSchema)}},
	})
	if err != nil {
		return nil, usage, err
	}
	var parsed struct {
		Recipes []Recipe `json:"recipes"`
	}
	if err := json.Unmarshal([]byte(extractJSON(text)), &parsed); err != nil {
		return nil, usage, fmt.Errorf("decode recipes: %w (raw: %s)", err, text)
	}
	return parsed.Recipes, usage, nil
}

// call posts to the Messages API. The request is tied to ctx so an abandoned
// client request cancels the upstream call instead of running (and billing)
// to completion.
func (c *Client) call(ctx context.Context, body requestBody) (string, Usage, error) {
	buf, err := json.Marshal(body)
	if err != nil {
		return "", Usage{}, err
	}
	req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewReader(buf))
	if err != nil {
		return "", Usage{}, err
	}
	req.Header.Set("content-type", "application/json")
	req.Header.Set("x-api-key", c.apiKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	resp, err := c.http.Do(req)
	if err != nil {
		return "", Usage{}, err
	}
	defer resp.Body.Close()
	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", Usage{}, err
	}
	if resp.StatusCode != http.StatusOK {
		return "", Usage{}, fmt.Errorf("anthropic http %d: %s", resp.StatusCode, string(respBytes))
	}
	var r responseBody
	if err := json.Unmarshal(respBytes, &r); err != nil {
		return "", Usage{}, fmt.Errorf("decode anthropic response: %w", err)
	}
	// Join all text blocks rather than assuming the first block is text —
	// some model configs emit other block types (e.g. thinking) first.
	var sb strings.Builder
	for _, blk := range r.Content {
		if blk.Type == "text" {
			sb.WriteString(blk.Text)
		}
	}
	text := sb.String()
	usage := Usage{InputTokens: r.Usage.InputTokens, OutputTokens: r.Usage.OutputTokens}
	if text == "" {
		return "", usage, fmt.Errorf("anthropic returned no text block")
	}
	if r.StopReason == "max_tokens" {
		return text, usage, fmt.Errorf("%w (max_tokens=%d, out_tokens=%d)", ErrTruncated, body.MaxTokens, r.Usage.OutputTokens)
	}
	return text, usage, nil
}

var fenceJSON = regexp.MustCompile("(?s)```json\\s*(.*?)```")
var fenceAny = regexp.MustCompile("(?s)```\\s*(.*?)```")

func extractJSON(text string) string {
	trimmed := strings.TrimSpace(text)
	if m := fenceJSON.FindStringSubmatch(trimmed); len(m) == 2 {
		return strings.TrimSpace(m[1])
	}
	if m := fenceAny.FindStringSubmatch(trimmed); len(m) == 2 {
		return strings.TrimSpace(m[1])
	}
	first := strings.Index(trimmed, "{")
	last := strings.LastIndex(trimmed, "}")
	if first != -1 && last > first {
		return trimmed[first : last+1]
	}
	return trimmed
}
