// Temporary smoke test: exercises both Anthropic calls once against the real
// API to validate the structured-output schemas and configured models.
// Run from server/: go run ./smoketest -config=config.toml
package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"image"
	"image/jpeg"
	"os"

	"fridgecheck/anthropic"
	"fridgecheck/config"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		fmt.Println("config:", err)
		os.Exit(1)
	}
	c := anthropic.NewClient(cfg.AnthropicAPIKey)

	recipes, usage, err := c.GenerateRecipes(context.Background(), anthropic.RecipeInput{
		Ingredients: []string{"eggs", "spinach", "cheddar"},
		ServingSize: 2,
	}, cfg.RecipesModel())
	if err != nil {
		fmt.Println("recipes FAIL:", err)
		os.Exit(1)
	}
	fmt.Printf("recipes OK (%s): %d recipes, in=%d out=%d, first=%q (%d steps, difficulty=%s)\n",
		cfg.RecipesModel(), len(recipes), usage.InputTokens, usage.OutputTokens,
		recipes[0].Title, len(recipes[0].Steps), recipes[0].Difficulty)

	// Tiny black JPEG: validates the scan request shape + schema; the model
	// should return zero (or near-zero) ingredients.
	img := image.NewRGBA(image.Rect(0, 0, 64, 64))
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, nil); err != nil {
		fmt.Println("jpeg encode:", err)
		os.Exit(1)
	}
	b64 := base64.StdEncoding.EncodeToString(buf.Bytes())
	ings, usage2, err := c.AnalyzeImages(context.Background(), []string{b64}, cfg.ScanModel())
	if err != nil {
		fmt.Println("scan FAIL:", err)
		os.Exit(1)
	}
	fmt.Printf("scan OK (%s): %d ingredients, in=%d out=%d\n",
		cfg.ScanModel(), len(ings), usage2.InputTokens, usage2.OutputTokens)
}
