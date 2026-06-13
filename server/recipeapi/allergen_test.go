package recipeapi

import (
	"testing"

	"fridgecheck/anthropic"
)

func TestPlanForAllergens(t *testing.T) {
	// Shellfish/Fish/Sesame have no -Free flag — they must NOT skip the
	// curated path; they become exclusion keywords instead.
	p, ok := planFor(anthropic.RecipeInput{Allergies: []string{"Shellfish"}})
	if !ok {
		t.Fatal("shellfish allergy should no longer skip the curated path")
	}
	if len(p.excludeKeywords) == 0 {
		t.Error("shellfish should populate excludeKeywords")
	}
	if len(p.requiredFlags) != 0 {
		t.Errorf("shellfish has no -Free flag, got requiredFlags=%v", p.requiredFlags)
	}

	// Nuts has a reliable flag — require it (no keyword exclusion needed).
	p, ok = planFor(anthropic.RecipeInput{Allergies: []string{"Nuts"}})
	if !ok {
		t.Fatal("nut allergy should be expressible")
	}
	if len(p.requiredFlags) != 1 || p.requiredFlags[0] != "Nut-Free" {
		t.Errorf("nuts should require Nut-Free, got %v", p.requiredFlags)
	}

	// Paleo dietary restriction is still unmappable → skip.
	if _, ok := planFor(anthropic.RecipeInput{DietaryRestrictions: []string{"Paleo"}}); ok {
		t.Error("Paleo should still skip the curated path")
	}
}

func TestContainsAllergen(t *testing.T) {
	_, _ = planFor(anthropic.RecipeInput{Allergies: []string{"Shellfish", "Fish"}})
	kws := append(allergenKeywords["Shellfish"], allergenKeywords["Fish"]...)

	cases := []struct {
		name   string
		recipe anthropic.Recipe
		want   bool
	}{
		{"shrimp in ingredients", anthropic.Recipe{
			Title:       "Garlic Scampi",
			Ingredients: []string{"450 g shrimp, peeled", "3 cloves garlic"},
		}, true},
		{"salmon in title", anthropic.Recipe{
			Title:       "Grilled Salmon",
			Ingredients: []string{"olive oil", "lemon"},
		}, true},
		{"clean chicken dish", anthropic.Recipe{
			Title:       "Chicken Rice Bowl",
			Ingredients: []string{"chicken breast", "rice", "broccoli"},
		}, false},
	}
	for _, tc := range cases {
		if got := containsAllergen(tc.recipe, kws); got != tc.want {
			t.Errorf("%s: containsAllergen=%v want %v", tc.name, got, tc.want)
		}
	}

	// No keywords (e.g. only flag-backed allergies) → never excludes.
	if containsAllergen(anthropic.Recipe{Title: "Shrimp Boil"}, nil) {
		t.Error("nil keywords should never exclude")
	}
}
