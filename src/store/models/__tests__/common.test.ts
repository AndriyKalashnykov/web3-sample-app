import { describe, it, expect } from 'vitest'
import { configureStore } from '@reduxjs/toolkit'
import counterReducer from '@/store/counterSlice'
import commonReducer, { setLanguage } from '@/store/commonSlice'

function createStore() {
  return configureStore({
    reducer: { counter: counterReducer, common: commonReducer },
  })
}

describe('common slice', () => {
  it('has initial language of en', () => {
    const store = createStore()
    expect(store.getState().common.language).toBe('en')
  })

  it('updates language via setLanguage action', () => {
    const store = createStore()
    store.dispatch(setLanguage('fr'))
    expect(store.getState().common.language).toBe('fr')
  })

  it('returns a new state object (immutable from outside)', () => {
    const store = createStore()
    const before = store.getState().common
    store.dispatch(setLanguage('de'))
    const after = store.getState().common
    expect(before).not.toBe(after)
    expect(before.language).toBe('en')
    expect(after.language).toBe('de')
  })
})
