/**
 * Runtime configuration for the SPA — bridges the gap between server env
 * vars (in production) and Vite build-time env (during local dev / tests).
 *
 * Production flow:
 *   1. Container starts.
 *   2. start-nginx.sh runs `envsubst` against `index.html.template`,
 *      writing real env values into the inline `window.__CONFIG__` script.
 *   3. Browser loads index.html → `window.__CONFIG__` is populated before
 *      any module code runs.
 *   4. This file reads from `window.__CONFIG__` and exposes a typed object.
 *
 * Local dev / unit tests:
 *   - `pnpm dev` serves index.html as-is with literal `${VITE_RPCENDPOINT}`
 *     placeholder strings inside `window.__CONFIG__`. We detect the
 *     placeholder pattern and fall through to `import.meta.env`, which
 *     Vite populates from `.env` automatically.
 *   - jsdom tests can stub `window.__CONFIG__` directly.
 */

declare global {
  interface Window {
    __CONFIG__?: {
      VITE_RPCENDPOINT?: string
      VITE_BASE_URL?: string
    }
  }
}

export interface AppConfig {
  VITE_RPCENDPOINT: string
  VITE_BASE_URL: string
}

const PLACEHOLDER_RE = /^\$\{[A-Z_]+\}$/

function isUnreplacedPlaceholder(v: string | undefined): v is string {
  return typeof v === 'string' && PLACEHOLDER_RE.test(v)
}

function pick(
  runtimeValue: string | undefined,
  buildTimeValue: string | undefined,
  fallback: string,
): string {
  if (runtimeValue && !isUnreplacedPlaceholder(runtimeValue))
    return runtimeValue
  if (buildTimeValue) return buildTimeValue
  return fallback
}

function readConfig(): AppConfig {
  const runtime = typeof window !== 'undefined' ? window.__CONFIG__ : undefined
  return {
    VITE_RPCENDPOINT: pick(
      runtime?.VITE_RPCENDPOINT,
      import.meta.env.VITE_RPCENDPOINT as string | undefined,
      '',
    ),
    VITE_BASE_URL: pick(
      runtime?.VITE_BASE_URL,
      import.meta.env.VITE_BASE_URL as string | undefined,
      '/api/',
    ),
  }
}

// Cached at module load. Tests that need to override should use vi.mock
// or set window.__CONFIG__ before importing modules that depend on this.
export const config: AppConfig = readConfig()
