#!/usr/bin/env bash
# poc/unlock_account.sh
#
# Usage:
#   ./poc/unlock_account.sh <email> [db_path]
 
source "$(dirname "$0")/config.sh"
 
TARGET_EMAIL="${1:-}"
DB_PATH="${2:-$(dirname "$0")/../backend/db/Break-the-Login.db}"
 
if [ -z "$TARGET_EMAIL" ]; then
  echo "Usage: $0 <email> [db_path]"
  exit 2
fi
 
sqlite3 "$DB_PATH" \
  "UPDATE users SET failed_logins = 0, locked_until = NULL WHERE email = '$TARGET_EMAIL';"