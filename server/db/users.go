package db

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
)

type User struct {
	ID        string
	AppleSub  string
	Tier      string
	CreatedAt string
}

func (db *DB) UpsertUserByAppleSub(appleSub string) (*User, error) {
	id, err := newID()
	if err != nil {
		return nil, err
	}
	// ON CONFLICT DO NOTHING makes concurrent first sign-ins race-safe:
	// whichever insert wins, the SELECT below returns the surviving row.
	if _, err := db.Exec(`INSERT INTO users (id, apple_sub) VALUES (?, ?) ON CONFLICT(apple_sub) DO NOTHING`, id, appleSub); err != nil {
		return nil, fmt.Errorf("insert user: %w", err)
	}
	row := db.QueryRow(`SELECT id, apple_sub, tier, created_at FROM users WHERE apple_sub = ?`, appleSub)
	var u User
	if err := row.Scan(&u.ID, &u.AppleSub, &u.Tier, &u.CreatedAt); err != nil {
		return nil, err
	}
	return &u, nil
}

func (db *DB) UserByID(id string) (*User, error) {
	row := db.QueryRow(`SELECT id, apple_sub, tier, created_at FROM users WHERE id = ?`, id)
	var u User
	if err := row.Scan(&u.ID, &u.AppleSub, &u.Tier, &u.CreatedAt); err != nil {
		return nil, err
	}
	return &u, nil
}

func (db *DB) DeleteUser(id string) error {
	tx, err := db.Begin()
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`DELETE FROM usage_events WHERE user_id = ?`, id); err != nil {
		return fmt.Errorf("delete usage_events: %w", err)
	}
	if _, err := tx.Exec(`DELETE FROM users WHERE id = ?`, id); err != nil {
		return fmt.Errorf("delete user: %w", err)
	}
	return tx.Commit()
}

func newID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(b[:]), nil
}
