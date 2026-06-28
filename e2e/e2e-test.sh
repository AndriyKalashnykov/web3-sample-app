#!/usr/bin/env bash
#
# E2E HTTP smoke + assertion suite against the deployed SPA.
#
# Expects $BASE to point at the SPA (e.g. a LoadBalancer IP, or a
# `kubectl port-forward`). If unset, BASE is composed from HEALTHCHECK_HOST
# and APP_INTERNAL_PORT (sourced from .env.example / .env).

set -euo pipefail

# Load committed defaults (.env.example = source of truth) + optional local
# override (.env). We do NOT `source` these: the app's `.env` is a Vite dotenv
# file (`KEY = 'value'` — spaces + quotes) that the shell can't execute. This
# tolerant parser accepts both `KEY=value` and `KEY = 'value'`. BASE is never
# set in either file (the caller computes it from the LB IP), so it's safe.
load_env_file() {
  [ -f "$1" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    [ "${line#*=}" = "$line" ] && continue            # skip lines without '='
    key=${line%%=*}; val=${line#*=}
    key=$(printf '%s' "$key" | tr -d '[:space:]')     # strip spaces around key
    val=${val#"${val%%[![:space:]]*}"}                # ltrim
    val=${val%"${val##*[![:space:]]}"}                # rtrim
    val=${val#[\"\']}; val=${val%[\"\']}              # strip one layer of quotes
    case "$key" in [A-Za-z_]*) export "$key=$val" ;; esac
  done < "$1"
}
load_env_file .env.example
load_env_file .env

# Inline fallbacks mirror .env.example so the script runs even if it's absent.
HEALTHCHECK_HOST="${HEALTHCHECK_HOST:-localhost}"
APP_INTERNAL_PORT="${APP_INTERNAL_PORT:-8080}"
EXPECTED_RPC="${EXPECTED_RPC:-https://ethereum-rpc.publicnode.com}"
VITE_BASE_URL="${VITE_BASE_URL:-/api/}"
# BASE: caller-provided (LB IP) wins; otherwise compose from host+port.
BASE="${BASE:-http://${HEALTHCHECK_HOST}:${APP_INTERNAL_PORT}}"
# Host portion of EXPECTED_RPC — single-sources the /publicnode redirect
# assertion below instead of re-typing the hostname literal.
EXPECTED_RPC_HOST="${EXPECTED_RPC#http://}"; EXPECTED_RPC_HOST="${EXPECTED_RPC_HOST#https://}"
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

assert_header_present() {
  # Asserts that an HTTP response header is present and matches a regex.
  # Catches the "header silently dropped because a `location` block defined
  # its own `add_header`/`header`" failure mode that the web-server config
  # (Caddy `header { defer }` today, nginx server-scope add_header previously)
  # is meant to prevent — but a future handler that bypasses `defer` could
  # silently shadow these. Assert at the wire.
  local url="$1" header="$2" pattern="$3"
  local value
  value=$(curl -sI "$url" \
    | awk -v h="$header" 'tolower($1)==tolower(h":"){sub(/^[^:]*:[ \t]*/,""); print}' \
    | tr -d '\r')
  if [[ -z "$value" ]]; then
    echo "FAIL: GET $url is missing header '$header'"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ ! "$value" =~ $pattern ]]; then
    echo "FAIL: GET $url header '$header' = '$value' (expected ~$pattern)"
    FAIL=$((FAIL + 1))
    return
  fi
  echo "PASS: GET $url header '$header' = '$value'"
  PASS=$((PASS + 1))
}

assert_header_absent() {
  # Asserts an HTTP response header is NOT present (e.g. the Caddyfile's
  # `-Server` directive must suppress the "Server: Caddy" token).
  local url="$1" header="$2" value
  value=$(curl -sI "$url" \
    | awk -v h="$header" 'tolower($1)==tolower(h":"){sub(/^[^:]*:[ \t]*/,""); print}' \
    | tr -d '\r')
  if [[ -n "$value" ]]; then
    echo "FAIL: GET $url unexpectedly carries header '$header' = '$value'"
    FAIL=$((FAIL + 1))
    return
  fi
  echo "PASS: GET $url has no '$header' header"
  PASS=$((PASS + 1))
}

assert_real_asset_cached() {
  # A real hashed build asset (referenced by index.html) MUST be served 200
  # with the immutable long-cache header from the Caddyfile `handle /assets/*`
  # block. Resolves a live asset path from the served index rather than
  # guessing the hashed filename.
  local asset
  asset=$(curl -sf "$BASE/" | grep -oE '/assets/[A-Za-z0-9._-]+\.js' | head -1 || true)
  if [[ -z "$asset" ]]; then
    echo "FAIL: could not find an /assets/*.js reference in index.html"
    FAIL=$((FAIL + 1))
    return
  fi
  assert_status GET "$BASE$asset" 200
  assert_header_present "$BASE$asset" 'Cache-Control' 'max-age=31536000.*immutable'
}

assert_config_var_substituted() {
  # Generic Pattern-C check: /config.js must have the given ${VAR} placeholder
  # replaced (no literal left) and assign the expected substituted value.
  local var="$1" expected="$2" cfg
  cfg=$(curl -sf "$BASE/config.js" || true)
  if echo "$cfg" | grep -qF "\${$var}"; then
    echo "FAIL: envsubst did not replace \${$var} in /config.js"
    FAIL=$((FAIL + 1))
    return
  fi
  if echo "$cfg" | grep -qF "$var: \"$expected\""; then
    echo "PASS: /config.js $var substituted with '$expected'"
    PASS=$((PASS + 1))
  else
    echo "FAIL: /config.js $var not substituted with '$expected'"
    FAIL=$((FAIL + 1))
  fi
}

assert_runtime_config_substituted() {
  # Pattern C: start-caddy.sh runs envsubst on config.js.template at container
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

# Health probes (Caddy custom routes)
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
# A real hashed asset must be 200 + immutable long-cache.
assert_real_asset_cached

# Public RPC redirect (Caddy /publicnode -> 307 to public RPC). The target is
# env-driven (`{$PUBLIC_RPC_URL:…}` in the Caddyfile, set by the k8s ConfigMap).
# This asserts the deployed default; to exercise the override path, deploy with a
# distinct PUBLIC_RPC_URL in k8s/cm.yaml and re-run — the Location must follow it.
assert_redirect_target "$BASE/publicnode" 307 "$EXPECTED_RPC_HOST"

# Pattern C runtime config — VITE_RPCENDPOINT must be substituted into the
# external /config.js loaded by index.html, written by start-caddy.sh's envsubst
# pass. If the placeholder is still literal, container startup is broken.
assert_runtime_config_substituted "$EXPECTED_RPC"
# VITE_BASE_URL is the second var envsubst substitutes — verify its placeholder
# was replaced too (the deployed ConfigMap sets it to /api/).
assert_config_var_substituted 'VITE_BASE_URL' "$VITE_BASE_URL"

# index.html must reference /config.js as an external script — proves the
# init container's seed-html step copied the bundled HTML into the writable
# emptyDir before Caddy booted (otherwise the served index would be either
# 404 or the bare unsubstituted template). This is the only assertion that
# distinguishes "config.js exists at the right path" from "the SPA actually
# loads it on every page render".
assert_body_contains "$BASE/" '<script src="/config.js"></script>'

# Security headers must reach the client on the SPA root, /config.js, AND on
# /internal/* (whose `respond` handler could shadow the deferred set). The
# Caddyfile's `header { defer ... }` sets these for every response, but a
# future handler that calls `header`/`respond` without `defer` could silently
# shadow them — assert at the wire on each handler that emits its own response.
for path in "/" "/config.js" "/internal/isalive"; do
  assert_header_present "$BASE$path" 'Content-Security-Policy'    "default-src 'self'"
  assert_header_present "$BASE$path" 'X-Frame-Options'           'DENY'
  assert_header_present "$BASE$path" 'X-Content-Type-Options'    'nosniff'
  assert_header_present "$BASE$path" 'Referrer-Policy'           'strict-origin-when-cross-origin'
  assert_header_present "$BASE$path" 'Cross-Origin-Opener-Policy'   'same-origin'
  assert_header_present "$BASE$path" 'Cross-Origin-Resource-Policy' 'same-origin'
  assert_header_present "$BASE$path" 'Permissions-Policy'        'camera=\(\)'
  # `-Server` in the Caddyfile drops the "Server: Caddy" token (server_tokens off).
  assert_header_absent "$BASE$path" 'Server'
done

# /assets/* defines its OWN `header` block (immutable Cache-Control), the exact
# shape that can silently shadow the global security-header set. Resolve a real
# hashed asset and assert the security headers survive on it too.
HEADER_ASSET=$(curl -sf "$BASE/" | grep -oE '/assets/[A-Za-z0-9._-]+\.js' | head -1 || true)
if [[ -n "$HEADER_ASSET" ]]; then
  assert_header_present "$BASE$HEADER_ASSET" 'Content-Security-Policy' "default-src 'self'"
  assert_header_present "$BASE$HEADER_ASSET" 'X-Content-Type-Options'  'nosniff'
else
  echo "FAIL: could not resolve an /assets/*.js path for the header-shadow check"
  FAIL=$((FAIL + 1))
fi

# /config.js must be served with Cache-Control: no-store so the browser
# always re-fetches it on deploy — otherwise a stale runtime config sticks
# until the user hard-reloads.
assert_header_present "$BASE/config.js" 'Cache-Control' 'no-store'
# /config.js is loaded as an external <script> under CSP `script-src 'self'`, so
# the browser must receive a JavaScript MIME or it refuses to execute it (which
# would break runtime config silently). Assert the Content-Type at the wire.
assert_header_present "$BASE/config.js" 'Content-Type' '(text|application)/javascript'

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
