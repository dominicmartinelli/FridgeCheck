package recipeapi

// Live mapping check against the public, unauthenticated /dinner endpoint —
// validates that detailRecipe's field names match the real API and that
// mapRecipe produces a sane app-shaped recipe. Costs no credits. Gated so
// normal `go test ./...` stays offline: RECIPEAPI_LIVE=1 go test ./recipeapi -v

import (
	"encoding/json"
	"net/http"
	"os"
	"testing"
)

func TestDinnerMapping(t *testing.T) {
	if os.Getenv("RECIPEAPI_LIVE") == "" {
		t.Skip("set RECIPEAPI_LIVE=1 to run against the live API")
	}
	resp, err := http.Get(defaultBaseURL + "/dinner")
	if err != nil {
		t.Fatalf("fetch /dinner: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("/dinner http %d", resp.StatusCode)
	}
	// /dinner returns the recipe object bare (the detail endpoint wraps it in
	// {data, usage}); decoding it directly exercises the same field names.
	var d detailRecipe
	if err := json.NewDecoder(resp.Body).Decode(&d); err != nil {
		t.Fatalf("decode: %v", err)
	}

	r := mapRecipe(d)
	if r.Title == "" {
		t.Error("mapped recipe has empty title")
	}
	if len(r.Ingredients) == 0 {
		t.Error("mapped recipe has no ingredients")
	}
	if len(r.Steps) == 0 {
		t.Error("mapped recipe has no steps")
	}
	if r.PrepTime == 0 && r.CookTime == 0 {
		t.Error("mapped recipe has no times — ISO duration parsing likely broken")
	}
	switch r.Difficulty {
	case "Easy", "Medium", "Hard":
	default:
		t.Errorf("unexpected difficulty %q", r.Difficulty)
	}
	t.Logf("mapped %q: %d ingredients, %d steps, prep=%dm cook=%dm, difficulty=%s, nutrition=%q",
		r.Title, len(r.Ingredients), len(r.Steps), r.PrepTime, r.CookTime, r.Difficulty, r.NutritionalInfo)
	t.Logf("first ingredient: %q", r.Ingredients[0])
}
