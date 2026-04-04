import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { Provider } from 'react-redux'
import { ThemeProvider } from '@mui/material/styles'
import { configureStore } from '@reduxjs/toolkit'
import counterReducer from '@/store/counterSlice'
import commonReducer from '@/store/commonSlice'
import { theme } from '@/theme'
import App from '@/App'

vi.mock('@/service/ether', () => ({
  provider: null,
  ETHbalance: 0,
  ETHblock: 0,
  DAIBalance: 0,
  DAIblock: 0,
  DAIContractName: '',
  DAISymbol: '',
  DAIBalanceFormatted: '0',
  getProvider: vi.fn(),
  getETHBalance: vi.fn().mockResolvedValue([0, 0n]),
  getDAIBalance: vi.fn().mockResolvedValue([0, '', '', 0n, '0']),
}))

vi.mock('ethers', () => ({
  ethers: {
    isAddress: vi.fn(() => false),
    formatEther: vi.fn(() => '0.0'),
  },
}))

function renderApp() {
  const store = configureStore({
    reducer: { counter: counterReducer, common: commonReducer },
  })
  return render(
    <Provider store={store}>
      <ThemeProvider theme={theme}>
        <App />
      </ThemeProvider>
    </Provider>,
  )
}

describe('App component', () => {
  it('renders the header with app name', async () => {
    renderApp()
    expect(await screen.findByText('web3-sample-app')).toBeInTheDocument()
  })

  it('renders the footer with version', () => {
    renderApp()
    expect(screen.getByText(/v0\.0\.1/)).toBeInTheDocument()
  })

  it('renders without crashing', () => {
    expect(() => renderApp()).not.toThrow()
  })
})
