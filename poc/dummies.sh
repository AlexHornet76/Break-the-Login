#!/usr/bin/env bash
# poc/setup_test_users.sh
# Usage: ./poc/setup_test_users.sh

set +e
set +o pipefail

source "$(dirname "$0")/config.sh"

REGISTER_URL="$BASE_URL/register"

mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/setup_users_$(date +%s).txt"
: > "$OUT_FILE"

log() { echo "$*" | tee -a "$OUT_FILE"; }

# user-ii de test
ATTACKER_EMAIL="attacker@yahoo.com"
ATTACKER_PASS="AttackerPass123!"

VICTIM_EMAIL="victim@yahoo.com"
VICTIM_PASS="VictimPass123!"


# inregistreaza attacker
log "[1] register attacker"
CODE="$(curl -s -o /tmp/reg1.json -w "%{http_code}" \
    -X POST "$REGISTER_URL" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$ATTACKER_EMAIL\",\"password\":\"$ATTACKER_PASS\"}")"
log "    status: $CODE | $(tr -d '\n' < /tmp/reg1.json)"

# inregistreaza victim
log "[2] register victim"
CODE="$(curl -s -o /tmp/reg2.json -w "%{http_code}" \
    -X POST "$REGISTER_URL" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$VICTIM_EMAIL\",\"password\":\"$VICTIM_PASS\"}")"
log "    status: $CODE | $(tr -d '\n' < /tmp/reg2.json)"

log ""
log "attacker : $ATTACKER_EMAIL / $ATTACKER_PASS"
log "victim   : $VICTIM_EMAIL / $VICTIM_PASS"
log ""

# salveaza credentialele intr-un fisier separat pentru reutilizare in alte PoC-uri
CREDS_FILE="$OUT_DIR/test_users.env"
cat > "$CREDS_FILE" <<EOF
ATTACKER_EMAIL="$ATTACKER_EMAIL"
ATTACKER_PASS="$ATTACKER_PASS"
VICTIM_EMAIL="$VICTIM_EMAIL"
VICTIM_PASS="$VICTIM_PASS"
EOF

log "credentials saved: $CREDS_FILE"
log "[DONE] output: $OUT_FILE"