#!/usr/bin/env bash
# poc/4.4_user_enumeration_messages.sh
#
# PoC: demonstreaza mesaje diferite pentru:
#  - user inexistent
#  - parola gresita (user existent)

set +e
set +o pipefail

source "$(dirname "$0")/config.sh"

EXISTING_EMAIL="${1:-}"
WRONG_PASS="${2:-WrongPass_$(date +%s)!}"

LOGIN_URL="$BASE_URL/login"
mkdir -p "$OUT_DIR"

OUT_FILE="$OUT_DIR/44_user_enum_messages_$(date +%s).txt"
: > "$OUT_FILE"

echo "=== PoC 4.4: Mesaje diferite (user inexistent vs parola gresita) ===" | tee -a "$OUT_FILE"
echo "Endpoint: $LOGIN_URL" | tee -a "$OUT_FILE"
echo "Existing: $EXISTING_EMAIL" | tee -a "$OUT_FILE"
echo "Wrong Password: $WRONG_PASS" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

request_login() {
  local label="$1"
  local email="$2"
  local pass="$3"

  local resp code body
  resp="$(curl -s -i -X POST "$LOGIN_URL" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$pass\"}")"

  code="$(echo "$resp" | awk 'NR==1{print $2}')"
  body="$(echo "$resp" | awk 'BEGIN{h=1} h && /^\r?$/{h=0; next} !h' | tr -d '\n' | sed 's/[[:space:]]\+/ /g')"

  echo "[$label] email=$email" | tee -a "$OUT_FILE"
  echo "HTTP $code" | tee -a "$OUT_FILE"
  echo "Body: $body" | tee -a "$OUT_FILE"
  echo | tee -a "$OUT_FILE"
}

# 1) user existent + parola gresita
request_login "CASE 1: existing user + wrong password" "$EXISTING_EMAIL" "$WRONG_PASS"

# 2) user inexistent + orice parola
NONEXIST_EMAIL="no_such_user_$(date +%s)$RANDOM@example.com"
request_login "CASE 2: non-existent user + wrong password" "$NONEXIST_EMAIL" "$WRONG_PASS"

echo "[DONE] Output: $OUT_FILE" | tee -a "$OUT_FILE"