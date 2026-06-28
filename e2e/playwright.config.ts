import { defineConfig, devices } from '@playwright/test'

const BASE = process.env.E2E_BASE_URL ?? 'http://localhost:8080'

export default defineConfig({
  testDir: '.',
  testMatch: /.*\.spec\.ts/,
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  // retries:0 locally keeps the gate honest (a flaky test fails loudly). On CI we
  // allow ONE retry ONLY because these tests hit a real external JSON-RPC
  // (ethereum-rpc.publicnode.com) whose cold-start latency / transient rate-limit
  // is genuine environmental jitter, not a product flake. A deterministic
  // regression still fails both attempts.
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: BASE,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
})
