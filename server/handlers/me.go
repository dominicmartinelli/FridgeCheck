package handlers

import (
	"log/slog"
	"net/http"

	"fridgecheck/db"
	"fridgecheck/middleware"
)

type MeHandler struct {
	db              *db.DB
	scanLimitFor    func(tier string) int
	recipesLimitFor func(tier string) int
}

func NewMeHandler(database *db.DB, scanLimitFor, recipesLimitFor func(string) int) *MeHandler {
	return &MeHandler{db: database, scanLimitFor: scanLimitFor, recipesLimitFor: recipesLimitFor}
}

func (h *MeHandler) Get(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	user, err := h.db.UserByID(userID)
	if err != nil {
		slog.Error("UserByID failed", "err", err, "uid", userID)
		writeError(w, http.StatusNotFound, "user_not_found", nil)
		return
	}
	usage, err := h.db.UsageLast24h(userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db_error", nil)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"userId":     user.ID,
		"tier":       user.Tier,
		"createdAt":  user.CreatedAt,
		"usageToday": map[string]int{"scan": usage[db.EndpointScan], "recipes": usage[db.EndpointRecipes]},
		"limits":     map[string]int{"scan": h.scanLimitFor(user.Tier), "recipes": h.recipesLimitFor(user.Tier)},
	})
}

func (h *MeHandler) Delete(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	if err := h.db.DeleteUser(userID); err != nil {
		slog.Error("DeleteUser failed", "err", err, "uid", userID)
		writeError(w, http.StatusInternalServerError, "db_error", nil)
		return
	}
	slog.Info("account deleted", "uid", userID)
	w.WriteHeader(http.StatusNoContent)
}
