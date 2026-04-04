import { DefaultLanguage } from '@/locale'
import { createSlice, type PayloadAction } from '@reduxjs/toolkit'

export type CommonState = {
  language: string
}

const commonSlice = createSlice({
  name: 'common',
  initialState: {
    language: DefaultLanguage,
  } as CommonState,
  reducers: {
    setLanguage: (state, action: PayloadAction<string>) => {
      state.language = action.payload
    },
  },
})

export const { setLanguage } = commonSlice.actions
export default commonSlice.reducer
