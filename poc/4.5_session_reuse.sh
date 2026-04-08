#!/usr/bin/env bash
# poc/4.5_session_reuse.sh
# Usage: ./poc/4.5_session_reuse.sh <email> <password>

set +e
set +o pipefail

source "$(dirname "$0")/config.sh"

EMAIL="${1:-}"
PASS="${2:-}"

if [ -z "$EMAIL" ] || [ -z "$PASS" ]; then
    echo "Usage: $0 <email> <password>"
    exit 2
fi

LOGIN_URL="$BASE_URL/login"
ME_URL="$BASE_URL/me"
LOGOUT_URL="$BASE_URL/logout"

mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/45_session_reuse_$(date +%s).txt"
COOKIEJAR="$OUT_DIR/45_cookies.txt"
: > "$OUT_FILE"

log() { echo "$*" | tee -a "$OUT_FILE"; }

log "=== 4.5: session reuse after logout ==="
log "target: $BASE_URL | user: $EMAIL"
log ""

# step 1: login, save cookie jar
log "[1] login"
CODE_LOGIN="$(curl -s -o "$OUT_DIR/45_login.json" -c "$COOKIEJAR" \
    -w "%{http_code}" -X POST "$LOGIN_URL" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")"
log "    status: $CODE_LOGIN"

if [ "$CODE_LOGIN" != "200" ] && [ "$CODE_LOGIN" != "201" ]; then
    log "    login failed, aborting"
    exit 1
fi

# step 2: confirm session works before logout
log "[2] GET /me (pre-logout)"
CODE_ME1="$(curl -s -o /dev/null -b "$COOKIEJAR" -w "%{http_code}" "$ME_URL")"
log "    status: $CODE_ME1"

# step 3: logout — cookiejar NOT cleared on purpose
log "[3] logout"
CODE_LOGOUT="$(curl -s -o /dev/null -b "$COOKIEJAR" \
    -w "%{http_code}" -X POST "$LOGOUT_URL" \
    -H "Content-Type: application/json")"
log "    status: $CODE_LOGOUT"

# step 4: try same cookie after logout
log "[4] GET /me (post-logout, same cookie)"
CODE_ME2="$(curl -s -o /dev/null -b "$COOKIEJAR" -w "%{http_code}" "$ME_URL")"
log "    status: $CODE_ME2"

log ""
log "=== verdict ==="
if [ "$CODE_ME1" = "200" ] && [ "$CODE_ME2" = "200" ]; then
    log "[VULNERABLE] cookie still valid after logout"
    exit 1
elif [ "$CODE_ME1" != "200" ]; then
    log "[INCONCLUSIVE] /me failed before logout too ($CODE_ME1)"
    exit 2
else
    log "[OK] session invalidated correctly ($CODE_ME2)"
    exit 0
fi