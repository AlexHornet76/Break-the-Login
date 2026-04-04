#!/usr/bin/env bash
set -euo pipefail

# determina foloderul cu poc-uri
POC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# evitam erori, in cazul in care nu exista fisiere
shopt -s nullglob

# adaugam permisiuni de executie
files=("$POC_DIR"/*.sh)
chmod +x "${files[@]}"

echo "[PASS] Setat executable (+x) pentru:"
for f in "${files[@]}"; do
  echo " - $(basename "$f")"
done