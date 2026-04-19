import { defineConfig } from 'vitest/config'
import { join } from 'path'

export default defineConfig({
  resolve: {
    alias: {
      '@': join(__dirname, 'src'),
    },
  },
  test: {
    environment: 'node',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.integration.test.{ts,tsx}'],
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
})
