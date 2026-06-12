package handlers

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"fridgecheck/anthropic"
	"fridgecheck/db"
)

// settleUsage settles a usage reservation after a failed upstream call: if
// tokens were spent anyway (e.g. the response was truncated) the event keeps
// its real counts and still draws quota; otherwise the reservation is
// released so failures don't count against the user.
func settleUsage(database *db.DB, usageID string, usage anthropic.Usage) {
	var err error
	if usage.InputTokens > 0 || usage.OutputTokens > 0 {
		err = database.SetUsageTokens(usageID, usage.InputTokens, usage.OutputTokens)
	} else {
		err = database.DeleteUsage(usageID)
	}
	if err != nil {
		slog.Error("settle usage reservation failed", "err", err, "usage_id", usageID)
	}
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("writeJSON failed", "err", err)
	}
}

func writeError(w http.ResponseWriter, status int, code string, extra map[string]any) {
	body := map[string]any{"error": code}
	for k, v := range extra {
		body[k] = v
	}
	writeJSON(w, status, body)
}
