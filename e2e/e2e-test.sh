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

assert_runtime_config_substituted() {
  # Pattern C: start-nginx.sh runs envsubst on config.js.template at container
  # start, producing /config.js with `window.__CONFIG__.VITE_RPCENDPOINT` set
  # to the real RPC URL from container env. Verify the file is reachable and
  # the placeholder was replaced (no literal `${VAR}`).
  local pattern="$1"
  local cfg
  cfg=$(curl -sf "$BASE/config.js" || true)
  if [[ -z "$cfg" ]]; then
    echo "FAIL: GET $BASE/config.js returned empty / 404"
    FAIL=$((FAIL + 1))
    return
  fi
  if ! echo "$cfg" | grep -q 'window.__CONFIG__'; then
    echo "FAIL: /config.js does not assign window.__CONFIG__"
    FAIL=$((FAIL + 1))
    return
  fi
  if echo "$cfg" | grep -q '\${VITE_RPCENDPOINT}'; then
    echo "FAIL: envsubst did not replace \${VITE_RPCENDPOINT} placeholder in /config.js"
    FAIL=$((FAIL + 1))
    return
  fi
  if echo "$cfg" | grep -q "VITE_RPCENDPOINT: \"$pattern\""; then
    echo "PASS: window.__CONFIG__.VITE_RPCENDPOINT substituted with '$pattern' in /config.js"
    PASS=$((PASS + 1))
  else
    echo "FAIL: /config.js's window.__CONFIG__.VITE_RPCENDPOINT does not contain '$pattern'"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== E2E suite against $BASE (expecting RPC=$EXPECTED_RPC injected into index.html) ==="

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

# Pattern C runtime config — VITE_RPCENDPOINT must be substituted into the
# inline window.__CONFIG__ script in /index.html by start-nginx.sh's envsubst
# pass. If the placeholder is still literal, container startup is broken.
assert_runtime_config_substituted "$EXPECTED_RPC"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
