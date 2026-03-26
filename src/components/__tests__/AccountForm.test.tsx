import { describe, it, expect, vi, beforeEach } from 'vitest'
import {
  renderWithProviders,
  screen,
  userEvent,
  waitFor,
} from '@/test/test-utils'
import AccountForm from '@/components/AccountForm'

const mockGetBlockNumber = vi.fn().mockResolvedValue(12345)
const mockProvider = {
  ready: Promise.resolve(),
  getBlockNumber: mockGetBlockNumber,
  getBalance: vi.fn().mockResolvedValue(0n),
}

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
  getETHBalance: vi.fn().mockResolvedValue([12345, 0n]),
  getDAIBalance: vi.fn().mockResolvedValue([12345, 'Dai', 'DAI', 0n, '0.0']),
}))

vi.mock('ethers', () => ({
  ethers: {
    isAddress: vi.fn(() => false),
    formatEther: vi.fn((val) => {
      if (typeof val === 'bigint') return (Number(val) / 1e18).toString()
      return '0.0'
    }),
  },
}))

describe('AccountForm component', () => {
  beforeEach(async () => {
    vi.clearAllMocks()
    vi.spyOn(window, 'alert').mockImplementation(() => {})

    const etherMod = await import('@/service/ether')
    Object.defineProperty(etherMod, 'provider', {
      value: mockProvider,
      writable: true,
    })
    vi.mocked(etherMod.getProvider).mockImplementation(async () => {
      Object.defineProperty(etherMod, 'provider', {
        value: mockProvider,
        writable: true,
      })
    })
    mockGetBlockNumber.mockResolvedValue(12345)
  })

  it('renders the address input with placeholder', () => {
    renderWithProviders(<AccountForm />)
    expect(screen.getByPlaceholderText('Address')).toBeInTheDocument()
  })

  it('renders balance and block labels', () => {
    renderWithProviders(<AccountForm />)
    expect(screen.getByText(/Balance:/)).toBeInTheDocument()
    expect(screen.getByText(/Last Block:/)).toBeInTheDocument()
  })

  it('renders the Get Balance button', () => {
    renderWithProviders(<AccountForm />)
    expect(screen.getByText('Get Balance')).toBeInTheDocument()
  })

  it('renders ETH and DAI asset options', () => {
    renderWithProviders(<AccountForm />)
    const select = screen.getByRole('combobox')
    expect(select).toBeInTheDocument()
    const options = screen.getAllByRole('option')
    expect(options).toHaveLength(2)
    expect(options[0]).toHaveTextContent('ETH')
    expect(options[1]).toHaveTextContent('DAI')
  })

  it('accepts text in the address input', async () => {
    renderWithProviders(<AccountForm />)
    const user = userEvent.setup()
    const input = screen.getByPlaceholderText('Address')
    await user.type(input, '0xabc')
    expect(input).toHaveValue('0xabc')
  })

  it('shows alert when provider fails', async () => {
    mockGetBlockNumber.mockRejectedValue(new Error('network error'))
    renderWithProviders(<AccountForm />)

    await waitFor(() => {
      expect(window.alert).toHaveBeenCalled()
    })
  })

  it('calls getETHBalance when Get Balance is clicked', async () => {
    const etherMod = await import('@/service/ether')
    renderWithProviders(<AccountForm />)
    const user = userEvent.setup()

    await user.click(screen.getByText('Get Balance'))

    await waitFor(() => {
      expect(etherMod.getETHBalance).toHaveBeenCalled()
    })
  })

  it('displays balance for address 0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf', async () => {
    const etherMod = await import('@/service/ether')
    const { ethers } = await import('ethers')
    const balanceWei = 1500000000000000000n // 1.5 ETH

    vi.mocked(ethers.isAddress).mockReturnValue(true)
    vi.mocked(ethers.formatEther).mockReturnValue('1.5')
    vi.mocked(etherMod.getETHBalance).mockImplementation(async () => {
      Object.defineProperty(etherMod, 'ETHbalance', {
        value: balanceWei,
        writable: true,
        configurable: true,
      })
      Object.defineProperty(etherMod, 'ETHblock', {
        value: 20000000,
        writable: true,
        configurable: true,
      })
      return [20000000, balanceWei]
    })

    renderWithProviders(<AccountForm />)
    const user = userEvent.setup()

    const input = screen.getByPlaceholderText('Address')
    await user.type(
      input,
      '0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf',
    )
    await user.click(screen.getByText('Get Balance'))

    await waitFor(() => {
      expect(etherMod.getETHBalance).toHaveBeenCalled()
    })

    await waitFor(() => {
      expect(screen.getByText(/Balance:.*1\.5/)).toBeInTheDocument()
      expect(screen.getByText(/Last Block:.*20000000/)).toBeInTheDocument()
    })
  })
})
