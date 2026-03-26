import { describe, it, expect } from 'vitest'
import { init } from '@rematch/core'
import { models } from '@/store/models'

function createStore() {
  return init({ models })
}

describe('counter model', () => {
  it('has initial state of 0', () => {
    const store = createStore()
    expect(store.getState().counter).toBe(0)
  })

  it('increments via SET_NUMBER reducer', () => {
    const store = createStore()
    store.dispatch.counter.SET_NUMBER(1)
    expect(store.getState().counter).toBe(1)
  })

  it('decrements via SET_NUMBER reducer', () => {
    const store = createStore()
    store.dispatch.counter.SET_NUMBER(1)
    store.dispatch.counter.SET_NUMBER(-1)
    expect(store.getState().counter).toBe(0)
  })

  it('increments via inc effect', async () => {
    const store = createStore()
    await store.dispatch.counter.inc(1)
    expect(store.getState().counter).toBe(1)
  })

  it('decrements via inc effect with negative payload', async () => {
    const store = createStore()
    await store.dispatch.counter.inc(5)
    await store.dispatch.counter.inc(-2)
    expect(store.getState().counter).toBe(3)
  })
})
