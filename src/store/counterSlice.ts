import { createSlice, type PayloadAction } from '@reduxjs/toolkit'

export type CounterState = number

const counterSlice = createSlice({
  name: 'counter',
  initialState: 0 as CounterState,
  reducers: {
    increment: (_state, action: PayloadAction<number>) => {
      return _state + action.payload
    },
  },
})

export const { increment } = counterSlice.actions
export default counterSlice.reducer
