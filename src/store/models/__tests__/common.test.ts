import { describe, it, expect } from 'vitest'
import { init } from '@rematch/core'
import { models } from '@/store/models'

function createStore() {
  return init({ models })
}

describe('common model', () => {
  it('has initial language of en', () => {
    const store = createStore()
    expect(store.getState().common.language).toBe('en')
  })

  it('updates language via SET_LANGUAGE reducer', () => {
    const store = createStore()
    store.dispatch.common.SET_LANGUAGE('fr')
    expect(store.getState().common.language).toBe('fr')
  })

  it('returns a new state object (immutable)', () => {
    const store = createStore()
    const before = store.getState().common
    store.dispatch.common.SET_LANGUAGE('de')
    const after = store.getState().common
    expect(before).not.toBe(after)
    expect(before.language).toBe('en')
    expect(after.language).toBe('de')
  })

  it('updates language via setLanguage effect', async () => {
    const store = createStore()
    await store.dispatch.common.setLanguage('fr')
    expect(store.getState().common.language).toBe('fr')
  })
})
