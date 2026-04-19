#!/usr/bin/env bash
#
# E2E HTTP smoke + assertion suite against the deployed SPA.
#
# Expects $BASE to point at the SPA (e.g. http://localhost:8080 via
# `kubectl port-forward`, or a LoadBalancer IP). Defaults to localhost:8080.

set -euo pipefail

BASE="${BASE:-http://localhost:8080}"
EXPECTED_RPC="${EXPECTED_RPC:-https://ethereum-rpc.publicnode.com}"
PASS=0
FAIL=0

assert_status() {
  local method="$1" url="$2" expected="$3"
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' -X "$method" "$url")
  if [[ "$status" == "$expected" ]]; then
    echo "PASS: $method $url -> $status"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $method $url -> $status (expected $expected)"
    FAIL=$((FAIL + 1))
  fi
}

assert_body_contains() {
  local url="$1" expected="$2"
  local body
  body=$(curl -sf "$url" || true)
  if echo "$body" | grep -q "$expected"; then
    echo "PASS: GET $url contains '$expected'"
    PASS=$((PASS + 1))
  else
    echo "FAIL: GET $url missing '$expected'"
    FAIL=$((FAIL + 1))
  fi
}

assert_redirect_target() {
  local url="$1" expected_status="$2" expected_location_pattern="$3"
  local location status
  status=$(curl -s -o /dev/null -w '%{http_code}' "$url")
  location=$(curl -sI "$url" | awk '/^[Ll]ocation:/{print $2}' | tr -d '\r')
  if [[ "$status" == "$expected_status" ]] && [[ "$location" =~ $expected_location_pattern ]]; then
    echo "PASS: GET $url -> $status Location=$location"
    PASS=$((PASS + 1))
  else
    echo "FAIL: GET $url -> $status Location=$location (expected $expected_status + ~$expected_location_pattern)"
    FAIL=$((FAIL + 1))
  fi
}

assert_any_chunk_contains() {
  # SPA chunk-splits via Vite + Rolldown. The VITE_RPCENDPOINT value lands in
  # whichever chunk imports the ether service — index-*.js by default, but
  # could move under refactor. Crawl primary scripts referenced from index.html
  # AND any lazy chunks they import via `"./assets/..."` strings.
  local pattern="$1"
  local primary_assets lazy_chunks asset_urls
  primary_assets=$(curl -sf "$BASE/" | grep -oE '/assets/[^"'\'']+\.js' | sort -u || true)
  # Rolldown emits lazy-chunk references as bare basenames (NOT quoted, NOT
  # as `./assets/...` paths). Match the well-known chunk prefixes. CSS and
  # non-existent siblings get filtered later by the curl probe (404s skipped).
  lazy_chunks=$(for a in $primary_assets; do
    curl -sf "${BASE}${a}" \
      | grep -oE '\b(index|about|vendor-[a-z]+|i18next|rolldown-runtime)-[A-Za-z0-9_-]{8}\b' \
      | awk '{print "/assets/" $0 ".js"}' || true
  done | sort -u || true)
  asset_urls=$(printf '%s\n%s\n' "$primary_assets" "$lazy_chunks" | sort -u | sed '/^$/d')
  if [[ -z "$asset_urls" ]]; then
    echo "FAIL: no /assets/*.js URLs found in served HTML"
    FAIL=$((FAIL + 1))
    return
  fi
  for asset in $asset_urls; do
    if curl -sf "${BASE}${asset}" | grep -q "$pattern"; then
      echo "PASS: ${BASE}${asset} contains '$pattern' (Vite baked VITE_RPCENDPOINT into bundle)"
      PASS=$((PASS + 1))
      return
    fi
  done
  echo "FAIL: '$pattern' not found in any served chunk: $(echo "$asset_urls" | tr '\n' ' ')"
  FAIL=$((FAIL + 1))
}

echo "=== E2E suite against $BASE (expecting RPC=$EXPECTED_RPC injected into JS) ==="

# Health probes (nginx custom routes)
assert_status GET "$BASE/internal/isalive" 200
assert_status GET "$BASE/internal/isready" 200
assert_body_contains "$BASE/internal/isalive" "ALIVE"
assert_body_contains "$BASE/internal/isready" "READY"

# SPA root and shell markup
assert_status GET "$BASE/" 200
assert_body_contains "$BASE/" '<div id="root">'
assert_body_contains "$BASE/" 'web3-sample-app'

# SPA fallback (any unknown path serves index.html, 200, NOT 404)
assert_status GET "$BASE/some/unknown/route" 200
assert_body_contains "$BASE/some/unknown/route" '<div id="root">'

# Asset pipeline — missing asset under /assets/ should 404 (no SPA fallback there)
assert_status GET "$BASE/assets/does-not-exist.js" 404

# Public RPC redirect (nginx /publicnode -> 307 to public RPC)
assert_redirect_target "$BASE/publicnode" 307 "ethereum-rpc.publicnode.com"

# Bundle env coverage — VITE_RPCENDPOINT must appear in some served chunk
# (Vite bakes it at build time; if it's missing, the SPA cannot reach the RPC).
assert_any_chunk_contains "$EXPECTED_RPC"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
