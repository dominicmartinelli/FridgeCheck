// Temporary smoke test: exercises both Anthropic calls once against the real
// API to validate the structured-output schemas and configured models.
// Run from server/: go run ./smoketest -config=config.toml
package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"flag"
	"fmt"
	"image"
	"image/jpeg"
	"os"

	"fridgecheck/anthropic"
	"fridgecheck/config"
	"fridgecheck/recipeapi"
)

func main() {
	// Opt-in: each unique recipe detail costs 1 recipe-api credit.
	testRecipeAPI := flag.Bool("recipeapi", false, "also exercise recipe-api.com (spends up to 2 credits)")
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

	if *testRecipeAPI {
		if cfg.RecipeAPIKey == "" {
			fmt.Println("recipe-api SKIP: recipe_api_key not set in config")
			os.Exit(1)
		}
		rc := recipeapi.NewClient(cfg.RecipeAPIKey)
		curated, err := rc.FindByIngredients(context.Background(), anthropic.RecipeInput{
			Ingredients: []string{"chicken", "rice", "spinach"},
			ServingSize: 2,
		}, 2)
		if err != nil {
			fmt.Println("recipe-api FAIL:", err)
			os.Exit(1)
		}
		fmt.Printf("recipe-api OK: %d curated recipes\n", len(curated))
		for _, r := range curated {
			fmt.Printf("  - %q (%s, %s, prep=%dm cook=%dm, %d steps) %s\n",
				r.Title, r.CuisineType, r.Difficulty, r.PrepTime, r.CookTime, len(r.Steps), r.NutritionalInfo)
		}
	}
}
