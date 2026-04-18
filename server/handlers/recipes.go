package handlers

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"fridgecheck/anthropic"
	"fridgecheck/db"
	"fridgecheck/middleware"
)

type RecipesHandler struct {
	db        *db.DB
	anthropic *anthropic.Client
	limit     int
}

func NewRecipesHandler(database *db.DB, client *anthropic.Client, limit int) *RecipesHandler {
	return &RecipesHandler{db: database, anthropic: client, limit: limit}
}

type recipesResponse struct {
	Recipes []anthropic.Recipe `json:"recipes"`
}

func (h *RecipesHandler) Post(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	used, err := h.db.CountUsageLast24h(userID, db.EndpointRecipes)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db_error", nil)
		return
	}
	if used >= h.limit {
		writeError(w, http.StatusTooManyRequests, "quota_exceeded", map[string]any{
			"limit": h.limit, "used": used,
		})
		return
	}

	var input anthropic.RecipeInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
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

	recipes, usage, err := h.anthropic.GenerateRecipes(input)
	if err != nil {
		slog.Error("anthropic recipes failed", "err", err, "uid", userID)
		writeError(w, http.StatusBadGateway, "upstream_failed", nil)
		return
	}
	if err := h.db.RecordUsage(userID, db.EndpointRecipes, usage.InputTokens, usage.OutputTokens); err != nil {
		slog.Error("record usage failed", "err", err)
	}
	writeJSON(w, http.StatusOK, recipesResponse{Recipes: recipes})
}
