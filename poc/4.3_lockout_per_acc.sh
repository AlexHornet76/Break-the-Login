#!/usr/bin/env bash
# poc/4.3_lockout_per_account.sh
# Testeaza lockout per cont: 10 parole gresite + 1 parola corecta
# Vulnerable: Parola corectă → login reuseste 
# Fixed: Parola corecta → login refuzat (cont blocat) 

set +e
source "$(dirname "$0")/config.sh"

EMAIL="${1:-}"
CORRECT_PASS="${2:-}"

if [ -z "$EMAIL" ] || [ -z "$CORRECT_PASS" ]; then
    echo "Usage: $0 <email> <correct_password>"
    exit 2
fi

LOGIN_URL="$BASE_URL/login"
OUT_FILE="$OUT_DIR/43_lockout_$(date +%s).txt"
mkdir -p "$OUT_DIR"
: > "$OUT_FILE"

echo "[4.3] Lockout per account — Correct password after attack" | tee -a "$OUT_FILE"
echo "Email: $EMAIL" | tee -a "$OUT_FILE"
echo "Strategy: 10 wrong passwords + 1 correct password" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

# Step 1: 10 failed attempts
echo "[STEP 1] 10 failed login attempts" | tee -a "$OUT_FILE"

for i in $(seq 1 10); do
    CODE="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$LOGIN_URL" \
        -H "Content-Type: application/json" \
        -d '{"email":"'"$EMAIL"'","password":"wrong'$i'"}')"
    
    echo "  Try $i -> HTTP $CODE" | tee -a "$OUT_FILE"
    sleep 3  # 3s delay, evit rate limit per IP
done

echo | tee -a "$OUT_FILE"

# Step 2: Correct password
echo "[STEP 2] Try CORRECT password" | tee -a "$OUT_FILE"

CODE_CORRECT="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$LOGIN_URL" \
    -H "Content-Type: application/json" \
    -d '{"email":"'"$EMAIL"'","password":"'"$CORRECT_PASS"'"}')"

echo "  Correct password -> HTTP $CODE_CORRECT" | tee -a "$OUT_FILE"

echo | tee -a "$OUT_FILE"
echo "=== VERDICT ===" | tee -a "$OUT_FILE"

if [ "$CODE_CORRECT" = "200" ]; then
    echo "VULNERABLE: nu e lockout" | tee -a "$OUT_FILE"
    exit 1
elif [ "$CODE_CORRECT" = "401" ]; then
    echo "FIXED: cont blocat" | tee -a "$OUT_FILE"
    exit 0
fi