#!/usr/bin/env sh
#
# Pattern C runtime config injection: substitute env vars into a single
# file (`config.js`) at container startup, then start nginx. The SPA loads
# `<script src="/config.js">` from index.html, which sets
# `window.__CONFIG__` before the SPA bundle runs.
#
# Why an external file (not an inline script): nginx CSP is
# `script-src 'self'`, which forbids inline scripts without a nonce or
# hash. An external file under `/` is allowed by `'self'` without
# weakening CSP.
#
# Source template lives at /usr/share/nginx/html/config.js.template
# (renamed from config.js in Dockerfile.prod, originally placed under
# `public/` so Vite serves it as-is in dev). Output is written to
# /usr/share/nginx/html/config.js on every container start.

set -eu

TEMPLATE=/usr/share/nginx/html/config.js.template
OUT=/usr/share/nginx/html/config.js

# Restrict envsubst to known SPA config vars so unrelated env entries don't
# accidentally get substituted into the file if they happen to share a name
# with something in the template.
envsubst '$VITE_RPCENDPOINT $VITE_BASE_URL' < "$TEMPLATE" > "$OUT"

exec nginx -g 'daemon off;'
