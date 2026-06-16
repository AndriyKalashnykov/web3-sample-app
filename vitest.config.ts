import { defineConfig } from 'vitest/config'
import { join } from 'path'

export default defineConfig({
  resolve: {
    alias: {
      '@': join(__dirname, 'src'),
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    server: {
      deps: {
        // MUI 9.1.x ships .mjs that directory-imports react-transition-group
        // (e.g. `react-transition-group/TransitionGroupContext`), which Node's
        // native ESM resolver rejects. Inlining routes these through Vite's
        // transform pipeline, where directory imports resolve correctly.
        inline: ['@mui/material', 'react-transition-group'],
      },
    },
    include: ['src/**/__tests__/**/*.test.{ts,tsx}'],
    exclude: ['**/node_modules/**', '**/dist/**', '**/*.integration.test.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      include: ['src/**/*.{ts,tsx}'],
      exclude: [
        'src/test/**',
        'src/**/*.d.ts',
        'src/main.tsx',
        'src/vite-env.d.ts',
      ],
    },
  },
})
