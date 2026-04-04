#!/usr/bin/env bash
source "$(dirname "$0")/config.sh"

echo "  4.1 - Teste politica parola"
echo "  Endpoint: $BASE_URL/register"
echo

# fisier pentru rezultate pe care il golim la inceput
OUT_FILE="$OUT_DIR/41_results.txt"
: > "$OUT_FILE"  

register(){
    local email="$1"
    local pass="$2"
    echo "    email=$email"
    echo "    password=$pass"
    curl -s -i -X POST "$BASE_URL/register" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$pass\"}" \
    | tee -a "$OUT_FILE"
    echo | tee -a "$OUT_FILE"
}

# sufix unic aproape sigur 
RAND="$(date +%s)$RANDOM"

echo -e "\n1) Failing Length (< 10 characters)"
EMAIL="len_${RAND}@example.com"
register "$EMAIL" "76"

echo -e "\n2) Failing Uppercase Check (no uppercase)"
EMAIL="up_${RAND}@example.com"
register "$EMAIL" "faraliteramare1$"

echo -e "\n3) Failing Lowercase Check (no lowercase)"
EMAIL="low_${RAND}@example.com"
register "$EMAIL" "FARALITERAMICA1$"

echo -e "\n4) Failing Digit Check (no digit)"
EMAIL="num_${RAND}@example.com"
register "$EMAIL" "Faranumar$"

echo -e "\n5) Failing Special Char Check (no special char)"
EMAIL="spec_${RAND}@example.com"
register "$EMAIL" "FaraSpeciale1"

echo -e "\n6) SUCCESS (meets all criteria)"
EMAIL="success_${RAND}@example.com"
register "$EMAIL" "ParolaDeosebitDeBuna1$"

if grep -q '"message"' "$OUT_FILE"; then
  exit 0
else
  exit 1
fi
