package handlers

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"fridgecheck/anthropic"
	"fridgecheck/db"
	"fridgecheck/middleware"
)

type ScanHandler struct {
	db        *db.DB
	anthropic *anthropic.Client
	model     string
	limitFor  func(tier string) int
}

func NewScanHandler(database *db.DB, client *anthropic.Client, model string, limitFor func(string) int) *ScanHandler {
	return &ScanHandler{db: database, anthropic: client, model: model, limitFor: limitFor}
}

type scanRequest struct {
	Images []string `json:"images"`
}

type scanResponse struct {
	Ingredients []anthropic.Ingredient `json:"ingredients"`
}

func (h *ScanHandler) Post(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	user, err := h.db.UserByID(userID)
	if err != nil {
		slog.Error("UserByID failed", "err", err, "uid", userID)
		writeError(w, http.StatusNotFound, "user_not_found", nil)
		return
	}
	limit := h.limitFor(user.Tier)

	used, err := h.db.CountUsageLast24h(userID, db.EndpointScan)
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

	var req scanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		slog.Warn("scan decode failed", "err", err, "uid", userID, "content_length", r.ContentLength)
		writeError(w, http.StatusBadRequest, "invalid_body", nil)
		return
	}
	slog.Info("scan received", "uid", userID, "images", len(req.Images), "content_length", r.ContentLength, "model", h.model)
	if len(req.Images) == 0 {
		writeError(w, http.StatusBadRequest, "no_images", nil)
		return
	}
	if len(req.Images) > 5 {
		writeError(w, http.StatusBadRequest, "too_many_images", nil)
		return
	}

	ingredients, usage, err := h.anthropic.AnalyzeImages(req.Images, h.model)
	if err != nil {
		slog.Error("anthropic analyze failed", "err", err, "uid", userID)
		if errors.Is(err, anthropic.ErrTruncated) {
			writeError(w, http.StatusBadGateway, "response_truncated", nil)
			return
		}
		writeError(w, http.StatusBadGateway, "upstream_failed", nil)
		return
	}
	if err := h.db.RecordUsage(userID, db.EndpointScan, usage.InputTokens, usage.OutputTokens); err != nil {
		slog.Error("record usage failed", "err", err)
	}
	slog.Info("scan ok", "uid", userID, "model", h.model, "ingredients", len(ingredients), "in_tokens", usage.InputTokens, "out_tokens", usage.OutputTokens)
	writeJSON(w, http.StatusOK, scanResponse{Ingredients: ingredients})
}
