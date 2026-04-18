#!/usr/bin/env bash

DB_PATH="${1:-/home/alexhornet76/DASS/Break-the-Login/backend/db/Break-the-Login.db}"

echo "4.2 - Citire parole din DB"
echo "    DB_PATH=$DB_PATH"
echo

sqlite3 "$DB_PATH" <<'SQL'
.headers on
.mode column
.width 5 30 30 10 20
SELECT id, email, password, role, created_at FROM users ORDER BY id DESC LIMIT 10;
SQL

