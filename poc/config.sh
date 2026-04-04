#!/usr/bin/env bash

#config proiect 
export BASE_URL="${BASE_URL:-http://localhost:8080/api}"

#unde salvam dovezi (req/resp)
export OUT_DIR="${OUT_DIR:-./out}"
mkdir -p "$OUT_DIR"

echo "[PASS] BASE_URL=$BASE_URL"
echo "[PASS] OUT_DIR=$OUT_DIR"