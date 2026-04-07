#!/usr/bin/env bash
# poc/4.5_cookie_flags_and_token_expiry.sh
#
# PoC pentru:
#  (A) cookie auth_token fara HttpOnly / Secure / SameSite
#  (B) JWT fara expirare (sau expirare prea lunga)

set +e
set +o pipefail

source "$(dirname "$0")/config.sh"

EMAIL="${1:-}"
PASS="${2:-}"

LOGIN_URL="$BASE_URL/login"
mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/45_cookie_and_jwt_$(date +%s).txt"
: > "$OUT_FILE"

echo "4.5: Cookie flags + JWT expiry" | tee -a "$OUT_FILE"
echo "Endpoint: $LOGIN_URL" | tee -a "$OUT_FILE"
echo "User: $EMAIL" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

RESP_HEADERS="$OUT_DIR/45_headers.txt"
RESP_BODY="$OUT_DIR/45_body.json"

# -D headers, -o body
curl -s -D "$RESP_HEADERS" -o "$RESP_BODY" \
  -X POST "$LOGIN_URL" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" >/dev/null

echo "[1] Set-Cookie from response:" | tee -a "$OUT_FILE"
grep -i '^set-cookie:' "$RESP_HEADERS" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

COOKIE_LINE="$(grep -i '^set-cookie:' "$RESP_HEADERS" | head -n 1)"

echo "[2] Cookie flag checks (HttpOnly / Secure / SameSite)" | tee -a "$OUT_FILE"
if echo "$COOKIE_LINE" | grep -qi "httponly"; then
  echo "  HttpOnly: PRESENT" | tee -a "$OUT_FILE"
else
  echo "  HttpOnly: MISSING  <-- VULNERABLE (XSS poate citi token-ul din cookie)" | tee -a "$OUT_FILE"
fi

if echo "$COOKIE_LINE" | grep -qi "secure"; then
  echo "  Secure:   PRESENT" | tee -a "$OUT_FILE"
else
  echo "  Secure:   MISSING  <-- VULNERABLE (cookie trimis si pe HTTP)" | tee -a "$OUT_FILE"
fi

if echo "$COOKIE_LINE" | grep -qi "samesite="; then
  echo "  SameSite: PRESENT" | tee -a "$OUT_FILE"
else
  echo "  SameSite: MISSING  <-- VULNERABLE (CSRF risk mai mare)" | tee -a "$OUT_FILE"
fi
echo | tee -a "$OUT_FILE"

TOKEN="$(jq -r '.token // empty' "$RESP_BODY")"
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "[3] JWT token not found in body (field .token). Body saved: $RESP_BODY" | tee -a "$OUT_FILE"
  echo "[DONE] Output: $OUT_FILE" | tee -a "$OUT_FILE"
  exit 0
fi

echo "[3] JWT token extracted from JSON body (.token)." | tee -a "$OUT_FILE"

# decode JWT payload (base64url)
PAYLOAD_B64URL="$(echo "$TOKEN" | cut -d. -f2)"

PAYLOAD_JSON="$(python3 - <<'PY'
import os, base64, json, sys
p = os.environ.get("PAYLOAD_B64URL","")
# base64url -> base64 padding
p += "=" * (-len(p) % 4)
data = base64.urlsafe_b64decode(p.encode())
sys.stdout.write(data.decode(errors="replace"))
PY
)"

echo | tee -a "$OUT_FILE"
echo "[4] JWT payload (decoded, signature NOT verified):" | tee -a "$OUT_FILE"
echo "$PAYLOAD_JSON" | jq -c . 2>/dev/null | tee -a "$OUT_FILE" || {
  echo "$PAYLOAD_JSON" | tee -a "$OUT_FILE"
}
echo | tee -a "$OUT_FILE"

EXP="$(echo "$PAYLOAD_JSON" | jq -r '.exp // empty' 2>/dev/null)"
NOW="$(date +%s)"

echo "[5] Expiry checks" | tee -a "$OUT_FILE"
if [ -z "$EXP" ] || [ "$EXP" = "null" ]; then
  echo "  exp: MISSING <-- VULNERABLE (token fara expirare)" | tee -a "$OUT_FILE"
else
  echo "  now: $NOW" | tee -a "$OUT_FILE"
  echo "  exp: $EXP" | tee -a "$OUT_FILE"
  if [ "$EXP" -le "$NOW" ]; then
    echo "  status: EXPIRED already (ciudat)" | tee -a "$OUT_FILE"
  else
    TTL=$((EXP - NOW))
    echo "  ttl_seconds: $TTL" | tee -a "$OUT_FILE"
    
    if [ "$TTL" -gt 86400 ]; then
      echo "  verdict: TOO LONG <-- VULNERABLE (expirare prea lunga, > 1 day)" | tee -a "$OUT_FILE"
    else
      echo "  verdict: OK (ttl <= 1 day)" | tee -a "$OUT_FILE"
    fi
  fi
fi

echo | tee -a "$OUT_FILE"
echo "[DONE] Output: $OUT_FILE" | tee -a "$OUT_FILE"