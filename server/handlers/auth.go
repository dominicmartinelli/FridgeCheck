package handlers

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"fridgecheck/auth"
	"fridgecheck/db"
)

type AuthHandler struct {
	users    *db.DB
	verifier *auth.AppleVerifier
	secret   string
}

func NewAuthHandler(database *db.DB, verifier *auth.AppleVerifier, jwtSecret string) *AuthHandler {
	return &AuthHandler{users: database, verifier: verifier, secret: jwtSecret}
}

type appleExchangeRequest struct {
	IdentityToken string `json:"identityToken"`
}

type sessionResponse struct {
	Session string `json:"session"`
	UserID  string `json:"userId"`
}

func (h *AuthHandler) Apple(w http.ResponseWriter, r *http.Request) {
	var req appleExchangeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.IdentityToken == "" {
		writeError(w, http.StatusBadRequest, "missing_identity_token", nil)
		return
	}
	appleSub, err := h.verifier.Verify(req.IdentityToken)
	if err != nil {
		slog.Warn("apple verify failed", "err", err)
		writeError(w, http.StatusUnauthorized, "invalid_apple_token", nil)
		return
	}
	user, err := h.users.UpsertUserByAppleSub(appleSub)
	if err != nil {
		slog.Error("upsert user failed", "err", err)
		writeError(w, http.StatusInternalServerError, "db_error", nil)
		return
	}
	session, err := auth.IssueSession(user.ID, h.secret)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "session_mint_failed", nil)
		return
	}
	writeJSON(w, http.StatusOK, sessionResponse{Session: session, UserID: user.ID})
}
