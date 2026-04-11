#!/usr/bin/env bash
# poc/4.3A_rate_limit_ip.sh
# Test: rate limiting per IP

set +e
source "$(dirname "$0")/config.sh"

LOGIN_URL="$BASE_URL/login"
OUT_FILE="$OUT_DIR/43_rate_limit_$(date +%s).txt"
mkdir -p "$OUT_DIR"
: > "$OUT_FILE"

EMAIL="nonexistent_$(date +%s)@test.com"

echo "[4.3] Rate limiting per IP" | tee -a "$OUT_FILE"

for i in $(seq 1 20); do
  res="$(curl -s -i -X POST "$LOGIN_URL" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"wrong$i\"}")"

  code="$(echo "$res" | awk 'NR==1{print $2}')"

  echo "Try $i -> HTTP $code" | tee -a "$OUT_FILE"

  if [ "$code" = "429" ]; then
    echo "[FIXED] Rate limit activ dupa $i requesturi" | tee -a "$OUT_FILE"
    exit 0
  fi
done

echo "[VULNERABLE] Nu exista rate limit" | tee -a "$OUT_FILE"