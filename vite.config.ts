import { defineConfig } from 'vite'
import { join } from 'path'
import react from '@vitejs/plugin-react'

const resolve = (dir: string) => join(__dirname, dir)

// https://vitejs.dev/config/
export default defineConfig({
  resolve: {
    alias: {
      '@': resolve('src'),
    },
  },
  build: {
    target: 'esnext',
    oxc: {
      compress: {
        drop_console: true,
        drop_debugger: true,
      },
    },
    rolldownOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules/react') || id.includes('node_modules/react-dom') || id.includes('node_modules/react-router')) {
            return 'vendor-react'
          }
          if (id.includes('node_modules/@mui') || id.includes('node_modules/@emotion')) {
            return 'vendor-mui'
          }
          if (id.includes('node_modules/ethers')) {
            return 'vendor-ethers'
          }
        },
      },
    },
  },
  server: {
    port: 8080,
  },
  plugins: [
    react(),
  ],
})
