import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'

// These tests directly exercise the precedence logic in src/config.ts:
//
//   pick(runtime, buildtime, fallback) =
//     runtime  if runtime is defined AND not the literal "${VAR}" placeholder
//     buildtime  if defined
//     fallback  otherwise
//
// The module reads `window.__CONFIG__` and `import.meta.env` once at module
// load, so each case mutates window.__CONFIG__ + the env stubs and uses
// vi.resetModules() to force a fresh evaluation.

describe('config (Pattern C runtime config)', () => {
  beforeEach(() => {
    vi.resetModules()
    // Each test stubs its own runtime + buildtime values explicitly, so
    // start from a clean slate — drop any leftover __CONFIG__ from setup
    // or a prior case.
    Reflect.deleteProperty(
      window as unknown as Record<string, unknown>,
      '__CONFIG__',
    )
  })

  afterEach(() => {
    vi.unstubAllEnvs()
    Reflect.deleteProperty(
      window as unknown as Record<string, unknown>,
      '__CONFIG__',
    )
  })

  it('reads runtime value from window.__CONFIG__ when set to a real URL', async () => {
    ;(window as unknown as { __CONFIG__: Record<string, string> }).__CONFIG__ =
      {
        VITE_RPCENDPOINT: 'https://runtime.example/rpc',
        VITE_BASE_URL: '/runtime/',
      }
    const { config } = await import('@/config')
    expect(config.VITE_RPCENDPOINT).toBe('https://runtime.example/rpc')
    expect(config.VITE_BASE_URL).toBe('/runtime/')
  })

  it('falls through to import.meta.env when runtime value is the literal ${VAR} placeholder', async () => {
    ;(window as unknown as { __CONFIG__: Record<string, string> }).__CONFIG__ =
      {
        VITE_RPCENDPOINT: '${VITE_RPCENDPOINT}',
        VITE_BASE_URL: '${VITE_BASE_URL}',
      }
    vi.stubEnv('VITE_RPCENDPOINT', 'https://buildtime.example/rpc')
    vi.stubEnv('VITE_BASE_URL', '/buildtime/')
    const { config } = await import('@/config')
    expect(config.VITE_RPCENDPOINT).toBe('https://buildtime.example/rpc')
    expect(config.VITE_BASE_URL).toBe('/buildtime/')
  })

  it('treats runtime value as authoritative even when buildtime is also set', async () => {
    ;(window as unknown as { __CONFIG__: Record<string, string> }).__CONFIG__ =
      {
        VITE_RPCENDPOINT: 'https://override.example/rpc',
      }
    vi.stubEnv('VITE_RPCENDPOINT', 'https://buildtime.example/rpc')
    const { config } = await import('@/config')
    expect(config.VITE_RPCENDPOINT).toBe('https://override.example/rpc')
  })

  it('falls back to default when both runtime and buildtime are empty', async () => {
    vi.stubEnv('VITE_RPCENDPOINT', '')
    vi.stubEnv('VITE_BASE_URL', '')
    const { config } = await import('@/config')
    // VITE_RPCENDPOINT default is empty string (caller must supply or fail).
    // VITE_BASE_URL default is `/api/` per the readConfig() fallback.
    expect(config.VITE_RPCENDPOINT).toBe('')
    expect(config.VITE_BASE_URL).toBe('/api/')
  })

  it('handles a partially-substituted window.__CONFIG__ (one substituted, one placeholder)', async () => {
    ;(window as unknown as { __CONFIG__: Record<string, string> }).__CONFIG__ =
      {
        VITE_RPCENDPOINT: 'https://runtime.example/rpc',
        VITE_BASE_URL: '${VITE_BASE_URL}',
      }
    vi.stubEnv('VITE_BASE_URL', '/buildtime/')
    const { config } = await import('@/config')
    expect(config.VITE_RPCENDPOINT).toBe('https://runtime.example/rpc')
    expect(config.VITE_BASE_URL).toBe('/buildtime/')
  })

  it('does not match a value that merely contains "${...}" (only fully-literal placeholders fall through)', async () => {
    // PLACEHOLDER_RE is anchored: ^\$\{[A-Z_]+\}$. A URL that happens to embed
    // a "${...}" segment would NOT match — it's a real URL the operator chose.
    ;(window as unknown as { __CONFIG__: Record<string, string> }).__CONFIG__ =
      {
        VITE_RPCENDPOINT: 'https://example.com/rpc?hint=${ignored}',
      }
    vi.stubEnv('VITE_RPCENDPOINT', 'https://buildtime.example/rpc')
    const { config } = await import('@/config')
    expect(config.VITE_RPCENDPOINT).toBe(
      'https://example.com/rpc?hint=${ignored}',
    )
  })
})
