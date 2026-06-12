package db

import "fmt"

type Endpoint string

const (
	EndpointScan    Endpoint = "scan"
	EndpointRecipes Endpoint = "recipes"
)

func (db *DB) CountUsageLast24h(userID string, endpoint Endpoint) (int, error) {
	row := db.QueryRow(`
		SELECT count(*) FROM usage_events
		WHERE user_id = ? AND endpoint = ? AND at > datetime('now', '-1 day')
	`, userID, string(endpoint))
	var n int
	if err := row.Scan(&n); err != nil {
		return 0, err
	}
	return n, nil
}

// ReserveUsage inserts a usage event *before* the upstream call so a burst of
// concurrent requests can't all pass the quota check together. Fill in token
// counts with SetUsageTokens once the call completes, or release the
// reservation with DeleteUsage if the call failed without spending tokens.
func (db *DB) ReserveUsage(userID string, endpoint Endpoint) (string, error) {
	id, err := newID()
	if err != nil {
		return "", err
	}
	if _, err := db.Exec(`
		INSERT INTO usage_events (id, user_id, endpoint, tokens_in, tokens_out)
		VALUES (?, ?, ?, 0, 0)
	`, id, userID, string(endpoint)); err != nil {
		return "", fmt.Errorf("insert usage_event: %w", err)
	}
	return id, nil
}

func (db *DB) SetUsageTokens(id string, tokensIn, tokensOut int) error {
	if _, err := db.Exec(`
		UPDATE usage_events SET tokens_in = ?, tokens_out = ? WHERE id = ?
	`, tokensIn, tokensOut, id); err != nil {
		return fmt.Errorf("update usage_event: %w", err)
	}
	return nil
}

func (db *DB) DeleteUsage(id string) error {
	if _, err := db.Exec(`DELETE FROM usage_events WHERE id = ?`, id); err != nil {
		return fmt.Errorf("delete usage_event: %w", err)
	}
	return nil
}

// UsageLast24h returns per-endpoint event counts in the rolling 24h window —
// the same window CountUsageLast24h enforces quotas against.
func (db *DB) UsageLast24h(userID string) (map[Endpoint]int, error) {
	rows, err := db.Query(`
		SELECT endpoint, count(*) FROM usage_events
		WHERE user_id = ? AND at > datetime('now', '-1 day')
		GROUP BY endpoint
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[Endpoint]int{EndpointScan: 0, EndpointRecipes: 0}
	for rows.Next() {
		var ep string
		var n int
		if err := rows.Scan(&ep, &n); err != nil {
			return nil, err
		}
		out[Endpoint(ep)] = n
	}
	return out, rows.Err()
}
