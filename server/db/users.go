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
	row := db.QueryRow(`SELECT id, apple_sub, tier, created_at FROM users WHERE apple_sub = ?`, appleSub)
	var u User
	err := row.Scan(&u.ID, &u.AppleSub, &u.Tier, &u.CreatedAt)
	if err == nil {
		return &u, nil
	}
	id, err := newID()
	if err != nil {
		return nil, err
	}
	if _, err := db.Exec(`INSERT INTO users (id, apple_sub) VALUES (?, ?)`, id, appleSub); err != nil {
		return nil, fmt.Errorf("insert user: %w", err)
	}
	return db.UserByID(id)
}

func (db *DB) UserByID(id string) (*User, error) {
	row := db.QueryRow(`SELECT id, apple_sub, tier, created_at FROM users WHERE id = ?`, id)
	var u User
	if err := row.Scan(&u.ID, &u.AppleSub, &u.Tier, &u.CreatedAt); err != nil {
		return nil, err
	}
	return &u, nil
}

func newID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(b[:]), nil
}
