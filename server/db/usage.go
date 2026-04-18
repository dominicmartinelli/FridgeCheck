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

func (db *DB) RecordUsage(userID string, endpoint Endpoint, tokensIn, tokensOut int) error {
	id, err := newID()
	if err != nil {
		return err
	}
	if _, err := db.Exec(`
		INSERT INTO usage_events (id, user_id, endpoint, tokens_in, tokens_out)
		VALUES (?, ?, ?, ?, ?)
	`, id, userID, string(endpoint), tokensIn, tokensOut); err != nil {
		return fmt.Errorf("insert usage_event: %w", err)
	}
	return nil
}

func (db *DB) UsageToday(userID string) (map[Endpoint]int, error) {
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
