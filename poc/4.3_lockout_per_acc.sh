#!/usr/bin/env bash
# poc/4.3_lockout_per_account.sh
# Test: lockout per cont


set +e
set +o pipefail

source "$(dirname "$0")/config.sh"

EMAIL="$1"
if [ -z "$EMAIL" ]; then
  echo "Usage: $0 <existing_email>"
  exit 2
fi

LOGIN_URL="$BASE_URL/login"
DB_PATH="$(dirname "$0")/../backend/db/Break-the-Login.db"

OUT_FILE="$OUT_DIR/43_lockout_$(date +%s).txt"
mkdir -p "$OUT_DIR"
: > "$OUT_FILE"

if [ -f "$(dirname "$0")/4.3_unlock_acc.sh" ]; then
  echo "[INFO] Resetting account state..." | tee -a "$OUT_FILE"
  "$(dirname "$0")/4.3_unlock_acc.sh" "$EMAIL" "$DB_PATH"
  echo | tee -a "$OUT_FILE"
fi

echo "[STEP] Sending failed login attempts..." | tee -a "$OUT_FILE"

for i in $(seq 1 12); do
  res="$(curl -s -i -X POST "$LOGIN_URL" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"wrong$i\"}")"

  code="$(echo "$res" | awk 'NR==1{print $2}')"

  echo "Try $i -> HTTP $code" | tee -a "$OUT_FILE"

# evitam rate limiter
  sleep 2
done

echo | tee -a "$OUT_FILE"

echo "[STEP] Checking DB state..." | tee -a "$OUT_FILE"

RESULT="$(sqlite3 "$DB_PATH" \
"SELECT failed_logins, locked_until FROM users WHERE email='$EMAIL';")"

FAILED="$(echo "$RESULT" | cut -d'|' -f1)"
LOCKED="$(echo "$RESULT" | cut -d'|' -f2)"

echo "DB state: failed_logins=$FAILED, locked_until=$LOCKED" | tee -a "$OUT_FILE"

echo | tee -a "$OUT_FILE"
echo "=== VERDICT ===" | tee -a "$OUT_FILE"

if [ "$FAILED" -ge 10 ] && [ -n "$LOCKED" ]; then
  echo "[FIXED] Lockout activ: cont blocat dupa prea multe incercari" | tee -a "$OUT_FILE"
  exit 0
else
  echo "[VULNERABLE] Lockout nu functioneaza corect" | tee -a "$OUT_FILE"
  exit 1
fi