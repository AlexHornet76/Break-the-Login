package db

import (
	"database/sql"
	"log"

	_ "github.com/mattn/go-sqlite3"
)

var DB *sql.DB

func Init() {
	var err error
	DB, err = sql.Open("sqlite3", "./Break-the-Login.db")
	if err != nil {
		log.Fatal("Nu se poate deschide baza de date:", err)
	}

	createTables()
}

func createTables() {
	// Tabelul users este vulnerabil
	// password este stocata in clar

	query := `
	CREATE TABLE IF NOT EXISTS users (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        email       TEXT UNIQUE NOT NULL,
        password    TEXT NOT NULL,        -- plain text
        role        TEXT DEFAULT 'USER',
        created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
        locked      BOOLEAN DEFAULT FALSE
    );
	CREATE TABLE iF NOT EXISTS audit_logs (
		id          INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id     INTEGER,
		action      TEXT NOT NULL,
		ip_address  TEXT,
		timestamp   DATETIME DEFAULT CURRENT_TIMESTAMP
	);
	`
	_, err := DB.Exec(query)
	if err != nil {
		log.Fatal("Eroare creare tabele:", err)
	}
	log.Println("Baza de date initializata.")
}
