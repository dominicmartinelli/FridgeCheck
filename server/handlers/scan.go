package handlers

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"fridgecheck/anthropic"
	"fridgecheck/db"
	"fridgecheck/middleware"
)

type ScanHandler struct {
	db        *db.DB
	anthropic *anthropic.Client
	limit     int
}

func NewScanHandler(database *db.DB, client *anthropic.Client, limit int) *ScanHandler {
	return &ScanHandler{db: database, anthropic: client, limit: limit}
}

type scanRequest struct {
	Images []string `json:"images"`
}

type scanResponse struct {
	Ingredients []anthropic.Ingredient `json:"ingredients"`
}

func (h *ScanHandler) Post(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	used, err := h.db.CountUsageLast24h(userID, db.EndpointScan)
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

	var req scanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_body", nil)
		return
	}
	if len(req.Images) == 0 {
		writeError(w, http.StatusBadRequest, "no_images", nil)
		return
	}
	if len(req.Images) > 5 {
		writeError(w, http.StatusBadRequest, "too_many_images", nil)
		return
	}

	ingredients, usage, err := h.anthropic.AnalyzeImages(req.Images)
	if err != nil {
		slog.Error("anthropic analyze failed", "err", err, "uid", userID)
		writeError(w, http.StatusBadGateway, "upstream_failed", nil)
		return
	}
	if err := h.db.RecordUsage(userID, db.EndpointScan, usage.InputTokens, usage.OutputTokens); err != nil {
		slog.Error("record usage failed", "err", err)
	}
	writeJSON(w, http.StatusOK, scanResponse{Ingredients: ingredients})
}
