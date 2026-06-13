package handlers

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"fridgecheck/anthropic"
	"fridgecheck/db"
	"fridgecheck/middleware"
	"fridgecheck/recipeapi"
)

type RecipesHandler struct {
	db        *db.DB
	anthropic *anthropic.Client
	recipeAPI *recipeapi.Client // nil when recipe_api_key is not configured
	model     string
	limitFor  func(tier string) int
}

func NewRecipesHandler(database *db.DB, client *anthropic.Client, recipeAPI *recipeapi.Client, model string, limitFor func(string) int) *RecipesHandler {
	return &RecipesHandler{db: database, anthropic: client, recipeAPI: recipeAPI, model: model, limitFor: limitFor}
}

type recipesResponse struct {
	Recipes []anthropic.Recipe `json:"recipes"`
}

func (h *RecipesHandler) Post(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	user, err := h.db.UserByID(userID)
	if err != nil {
		slog.Error("UserByID failed", "err", err, "uid", userID)
		writeError(w, http.StatusNotFound, "user_not_found", nil)
		return
	}
	limit := h.limitFor(user.Tier)

	used, err := h.db.CountUsageLast24h(userID, db.EndpointRecipes)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db_error", nil)
		return
	}
	if limit > 0 && used >= limit {
		writeError(w, http.StatusTooManyRequests, "quota_exceeded", map[string]any{
			"limit": limit, "used": used,
		})
		return
	}

	var input anthropic.RecipeInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		slog.Warn("recipes decode failed", "err", err, "uid", userID, "content_length", r.ContentLength)
		writeError(w, http.StatusBadRequest, "invalid_body", nil)
		return
	}
	if len(input.Ingredients) == 0 {
		writeError(w, http.StatusBadRequest, "no_ingredients", nil)
		return
	}
	if input.ServingSize <= 0 {
		input.ServingSize = 2
	}
	slog.Info("recipes received", "uid", userID, "ingredients", len(input.Ingredients), "model", h.model)

	usageID, err := h.db.ReserveUsage(userID, db.EndpointRecipes)
	if err != nil {
		slog.Error("reserve usage failed", "err", err, "uid", userID)
		writeError(w, http.StatusInternalServerError, "db_error", nil)
		return
	}

	// Hybrid: serve curated catalog recipes when we can match at least two;
	// otherwise (thin matches, unmappable preferences, credit cool-down, or
	// any error) generate with Claude. The reserved usage event stays either
	// way — curated responses draw quota too, just with zero token counts.
	if h.recipeAPI != nil {
		curated, err := h.recipeAPI.FindByIngredients(r.Context(), input, 8)
		if err == nil && len(curated) >= 2 {
			writeJSON(w, http.StatusOK, recipesResponse{Recipes: curated})
			return
		}
	}

	recipes, usage, err := h.anthropic.GenerateRecipes(r.Context(), input, h.model)
	if err != nil {
		settleUsage(h.db, usageID, usage)
		slog.Error("anthropic recipes failed", "err", err, "uid", userID, "model", h.model)
		if errors.Is(err, anthropic.ErrTruncated) {
			writeError(w, http.StatusBadGateway, "response_truncated", nil)
			return
		}
		writeError(w, http.StatusBadGateway, "upstream_failed", nil)
		return
	}
	if err := h.db.SetUsageTokens(usageID, usage.InputTokens, usage.OutputTokens); err != nil {
		slog.Error("record usage failed", "err", err)
	}
	slog.Info("recipes ok", "uid", userID, "model", h.model, "recipes", len(recipes), "in_tokens", usage.InputTokens, "out_tokens", usage.OutputTokens)
	writeJSON(w, http.StatusOK, recipesResponse{Recipes: recipes})
}
