import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach, vi } from 'vitest'
import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import en from '@/locales/en.json'

i18n.use(initReactI18next).init({
  fallbackLng: 'en',
  lng: 'en',
  debug: false,
  resources: { en: { translation: en } },
  interpolation: { escapeValue: false },
})

vi.stubEnv('VITE_RPCENDPOINT', 'http://localhost:8545')

afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
})
