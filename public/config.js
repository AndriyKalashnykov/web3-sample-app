// Pattern C runtime config. In production, start-nginx.sh runs envsubst
// over `config.js.template` (this file, renamed in Dockerfile.prod) and
// writes the substituted output to /config.js at container start. The
// SPA loads it via <script src="/config.js"> in index.html. Loaded as
// an external file (not inline) so strict CSP `script-src 'self'`
// applies without a per-deploy nonce/hash.
//
// In `pnpm dev`, Vite serves this file as-is from public/ — the literal
// `${VAR}` placeholders below pass through unchanged, src/config.ts
// detects them via PLACEHOLDER_RE and falls through to import.meta.env.
window.__CONFIG__ = {
  VITE_RPCENDPOINT: "${VITE_RPCENDPOINT}",
  VITE_BASE_URL: "${VITE_BASE_URL}",
}
