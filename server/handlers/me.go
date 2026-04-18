package handlers

import (
	"log/slog"
	"net/http"

	"fridgecheck/db"
	"fridgecheck/middleware"
)

type MeHandler struct {
	db                *db.DB
	scanLimit         int
	recipesLimit      int
}

func NewMeHandler(database *db.DB, scanLimit, recipesLimit int) *MeHandler {
	return &MeHandler{db: database, scanLimit: scanLimit, recipesLimit: recipesLimit}
}

func (h *MeHandler) Get(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	user, err := h.db.UserByID(userID)
	if err != nil {
		slog.Error("UserByID failed", "err", err, "uid", userID)
		writeError(w, http.StatusNotFound, "user_not_found", nil)
		return
	}
	usage, err := h.db.UsageToday(userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db_error", nil)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"userId":     user.ID,
		"tier":       user.Tier,
		"createdAt":  user.CreatedAt,
		"usageToday": map[string]int{"scan": usage[db.EndpointScan], "recipes": usage[db.EndpointRecipes]},
		"limits":     map[string]int{"scan": h.scanLimit, "recipes": h.recipesLimit},
	})
}
