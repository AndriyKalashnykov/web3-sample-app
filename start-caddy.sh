#!/usr/bin/env sh
#
# Pattern C runtime config injection (Caddy variant). Substitutes env
# vars into a single file (`config.js`) at container startup, then
# starts Caddy. The SPA loads `<script src="/config.js">` from
# index.html, which sets `window.__CONFIG__` before the SPA bundle
# runs.
#
# Why an external file (not an inline script): the Caddy `header`
# block sends Content-Security-Policy `script-src 'self'`, which
# forbids inline scripts without a nonce or hash. An external file
# under `/` is allowed by `'self'` without weakening CSP.
#
# Source template lives at /srv/config.js.template (renamed from
# config.js in Dockerfile.prod, originally placed under `public/` so
# Vite serves it as-is in dev). Output is written to /srv/config.js
# on every container start.

set -eu

TEMPLATE=/srv/config.js.template
OUT=/srv/config.js

# Restrict envsubst to known SPA config vars so unrelated env entries
# don't accidentally get substituted into the file if they happen to
# share a name with something in the template.
envsubst '$VITE_RPCENDPOINT $VITE_BASE_URL' < "$TEMPLATE" > "$OUT"

# The Caddy image's default CMD points at /etc/caddy/Caddyfile via
# `caddyfile` adapter; replicate that under exec so the container's
# main process is caddy itself (correct PID 1 semantics).
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
