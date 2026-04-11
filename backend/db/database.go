package db

import (
	"database/sql"
	"log"

	_ "github.com/mattn/go-sqlite3"
)

var DB *sql.DB

func Init() {
	var err error
	DB, err = sql.Open("sqlite3", "./db/Break-the-Login.db")
	if err != nil {
		log.Fatal("Nu se poate deschide baza de date:", err)
	}
	createTables()
}

func createTables() {
	query := `
	CREATE TABLE IF NOT EXISTS users (
		id            INTEGER PRIMARY KEY AUTOINCREMENT,
		email         TEXT UNIQUE NOT NULL,
		password      TEXT NOT NULL,        -- bcrypt hash
		role          TEXT DEFAULT 'USER',
		created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,

		failed_logins INTEGER DEFAULT 0,
		locked_until  DATETIME,

		token_version INTEGER DEFAULT 0      -- 4.5: revoke tokens on logout/reset
	);

	CREATE TABLE IF NOT EXISTS audit_logs (
		id          INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id     INTEGER,
		action      TEXT NOT NULL,
		ip_address  TEXT,
		timestamp   DATETIME DEFAULT CURRENT_TIMESTAMP,
		resource    TEXT,
		resource_id TEXT
	);

	CREATE TABLE IF NOT EXISTS reset_tokens (
		id         INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id    INTEGER NOT NULL,

		token_hash TEXT NOT NULL UNIQUE,     -- 4.6: store hash, not raw token
		expires_at DATETIME NOT NULL,        -- 4.6: expiry
		used_at    DATETIME,                 -- 4.6: one-time use
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

		FOREIGN KEY (user_id) REFERENCES users(id)
	);

	CREATE TABLE IF NOT EXISTS tickets (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		title TEXT NOT NULL,
		description TEXT,
		severity TEXT DEFAULT 'LOW',
		status TEXT DEFAULT 'OPEN',
		owner_id INTEGER NOT NULL,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		FOREIGN KEY (owner_id) REFERENCES users(id)
	);
	`
	_, err := DB.Exec(query)
	if err != nil {
		log.Fatal("Eroare creare tabele:", err)
	}
	log.Println("Baza de date initializata.")
}
