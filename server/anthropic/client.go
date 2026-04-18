package anthropic

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"
)

const endpoint = "https://api.anthropic.com/v1/messages"

type Client struct {
	apiKey string
	model  string
	http   *http.Client
}

func NewClient(apiKey, model string) *Client {
	return &Client{
		apiKey: apiKey,
		model:  model,
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
	Model     string    `json:"model"`
	MaxTokens int       `json:"max_tokens"`
	Messages  []message `json:"messages"`
}

type responseUsage struct {
	InputTokens  int `json:"input_tokens"`
	OutputTokens int `json:"output_tokens"`
}

type responseBody struct {
	Content []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	Usage responseUsage `json:"usage"`
}

func (c *Client) AnalyzeImages(imagesB64 []string) ([]Ingredient, Usage, error) {
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
		Text: fmt.Sprintf(`Analyze %s of a fridge/food items. Identify all visible food items and ingredients across all images. Deduplicate items that appear in multiple images.

Return your response as valid JSON with this exact structure:
{
  "ingredients": [
    {
      "name": "item name",
      "category": "one of: Produce, Dairy, Meat, Seafood, Grains, Condiments, Beverages, Snacks, Frozen, Other",
      "estimatedQuantity": "estimated amount e.g. '2 pieces', '1 bag', '500ml'"
    }
  ]
}

Only return the JSON, no other text.`, countWord),
	})

	text, usage, err := c.call(requestBody{
		Model:     c.model,
		MaxTokens: 2048,
		Messages:  []message{{Role: "user", Content: blocks}},
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

func (c *Client) GenerateRecipes(input RecipeInput) ([]Recipe, Usage, error) {
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
Suggest 5 recipes I can make using ONLY the ingredients listed above. Do not suggest recipes that require significant ingredients not in the list. You may assume basic pantry staples (salt, pepper, oil, water, common spices) are available. For each recipe, provide detailed step-by-step instructions.

Return your response as valid JSON with this exact structure:
{
  "recipes": [
    {
      "title": "Recipe Name",
      "summary": "Brief 1-2 sentence description",
      "ingredients": ["ingredient 1 with amount", "ingredient 2 with amount"],
      "steps": ["Step 1 instruction", "Step 2 instruction"],
      "prepTime": 15,
      "cookTime": 30,
      "nutritionalInfo": "Approx. 450 cal, 25g protein, 35g carbs, 18g fat per serving",
      "cuisineType": "Italian",
      "difficulty": "Easy"
    }
  ]
}

Only return the JSON, no other text.`)

	text, usage, err := c.call(requestBody{
		Model:     c.model,
		MaxTokens: 8192,
		Messages:  []message{{Role: "user", Content: strings.Join(parts, "\n")}},
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

func (c *Client) call(body requestBody) (string, Usage, error) {
	buf, err := json.Marshal(body)
	if err != nil {
		return "", Usage{}, err
	}
	req, err := http.NewRequest("POST", endpoint, bytes.NewReader(buf))
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
	if len(r.Content) == 0 || r.Content[0].Text == "" {
		return "", Usage{}, fmt.Errorf("anthropic returned no text block")
	}
	return r.Content[0].Text, Usage{InputTokens: r.Usage.InputTokens, OutputTokens: r.Usage.OutputTokens}, nil
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
