#!/usr/bin/env sh
#
# Pattern C runtime config injection: substitute env vars into a single
# file (`index.html`) at container startup, then start nginx. The SPA reads
# `window.__CONFIG__` (set by the inline script in index.html) — no JS
# bundle rewriting required.
#
# Source template lives at /usr/share/nginx/html/index.html.template
# (renamed from index.html in Dockerfile.prod). Output is written to
# /usr/share/nginx/html/index.html on every container start.

set -eu

TEMPLATE=/usr/share/nginx/html/index.html.template
OUT=/usr/share/nginx/html/index.html

# Restrict envsubst to known SPA config vars so unrelated env entries don't
# accidentally get substituted into the HTML if they happen to share a name
# with something in the template.
envsubst '$VITE_RPCENDPOINT $VITE_BASE_URL' < "$TEMPLATE" > "$OUT"

exec nginx -g 'daemon off;'
