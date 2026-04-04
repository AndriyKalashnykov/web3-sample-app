import { describe, it, expect } from 'vitest'
import { configureStore } from '@reduxjs/toolkit'
import counterReducer, { increment } from '@/store/counterSlice'
import commonReducer from '@/store/commonSlice'

function createStore() {
  return configureStore({
    reducer: { counter: counterReducer, common: commonReducer },
  })
}

describe('counter slice', () => {
  it('has initial state of 0', () => {
    const store = createStore()
    expect(store.getState().counter).toBe(0)
  })

  it('increments via increment action', () => {
    const store = createStore()
    store.dispatch(increment(1))
    expect(store.getState().counter).toBe(1)
  })

  it('decrements via increment action with negative payload', () => {
    const store = createStore()
    store.dispatch(increment(1))
    store.dispatch(increment(-1))
    expect(store.getState().counter).toBe(0)
  })

  it('handles multiple increments', () => {
    const store = createStore()
    store.dispatch(increment(5))
    store.dispatch(increment(-2))
    expect(store.getState().counter).toBe(3)
  })
})
