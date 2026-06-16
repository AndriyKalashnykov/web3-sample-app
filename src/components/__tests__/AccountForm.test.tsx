import { describe, it, expect, vi, beforeEach } from 'vitest'
import {
  renderWithProviders,
  screen,
  userEvent,
  waitFor,
} from '@/test/test-utils'
import AccountForm from '@/components/AccountForm'

const TEST_ADDRESS = '0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf'

vi.mock('@/service/ether', () => ({
  getETHBalance: vi.fn().mockResolvedValue({ block: 12345n, balance: 0n }),
  getDAIBalance: vi.fn().mockResolvedValue({
    block: 12345n,
    name: 'Dai Stablecoin',
    symbol: 'DAI',
    balance: 0n,
    balanceFormatted: '0.0',
  }),
  formatEther: vi.fn((val: bigint) => (Number(val) / 1e18).toString()),
  formatUnits: vi.fn((val: bigint) => (Number(val) / 1e18).toString()),
  getAddress: vi.fn((value: string) => {
    if (!value || !value.startsWith('0x')) {
      throw new Error(`Address "${value}" is invalid.`)
    }
    return value
  }),
}))

describe('AccountForm component', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.spyOn(window, 'alert').mockImplementation(() => {})
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

  it('shows alert when getETHBalance throws', async () => {
    const etherMod = await import('@/service/ether')
    vi.mocked(etherMod.getETHBalance).mockRejectedValueOnce(
      new Error('network error'),
    )
    renderWithProviders(<AccountForm />)
    const user = userEvent.setup()

    await user.type(screen.getByPlaceholderText('Address'), TEST_ADDRESS)
    await user.click(screen.getByText('Get Balance'))

    await waitFor(() => {
      expect(window.alert).toHaveBeenCalled()
    })
  })

  it('does not call getETHBalance when address is empty', async () => {
    const etherMod = await import('@/service/ether')
    renderWithProviders(<AccountForm />)
    const user = userEvent.setup()

    await user.click(screen.getByText('Get Balance'))

    expect(etherMod.getETHBalance).not.toHaveBeenCalled()
    expect(window.alert).not.toHaveBeenCalled()
  })

  it('does not call getETHBalance via onKeyUp while typing an invalid address', async () => {
    // Each keystroke fires onKeyUp -> getBalance() -> isValidAddress(). The
    // mocked getAddress throws for any string that doesn't start with "0x",
    // so isValidAddress returns false and getBalance returns early. Asserts
    // that an in-progress address never triggers a wasted RPC roundtrip.
    const etherMod = await import('@/service/ether')
    renderWithProviders(<AccountForm />)
    const user = userEvent.setup()

    await user.type(screen.getByPlaceholderText('Address'), 'abc')

    expect(etherMod.getETHBalance).not.toHaveBeenCalled()
    expect(etherMod.getDAIBalance).not.toHaveBeenCalled()
  })

  it('calls getETHBalance when Get Balance is clicked with a valid address', async () => {
    const etherMod = await import('@/service/ether')
    renderWithProviders(<AccountForm />)
    const user = userEvent.setup()

    await user.type(screen.getByPlaceholderText('Address'), TEST_ADDRESS)
    await user.click(screen.getByText('Get Balance'))

    await waitFor(() => {
      expect(etherMod.getETHBalance).toHaveBeenCalled()
    })
  })

  it('displays balance for a valid address', async () => {
    const etherMod = await import('@/service/ether')
    const balanceWei = 1500000000000000000n // 1.5 ETH
    vi.mocked(etherMod.getETHBalance).mockResolvedValue({
      block: 20000000n,
      balance: balanceWei,
    })
    vi.mocked(etherMod.formatEther).mockReturnValue('1.5')

    renderWithProviders(<AccountForm />)
    const user = userEvent.setup()

    const input = screen.getByPlaceholderText('Address')
    await user.type(input, TEST_ADDRESS)
    await user.click(screen.getByText('Get Balance'))

    await waitFor(() => {
      expect(etherMod.getETHBalance).toHaveBeenCalled()
    })

    await waitFor(() => {
      expect(screen.getByText(/Balance:.*1\.5/)).toBeInTheDocument()
      expect(screen.getByText(/Last Block:.*20000000/)).toBeInTheDocument()
    })
  })

  it('queries getDAIBalance and displays its balance when DAI is selected', async () => {
    const etherMod = await import('@/service/ether')
    vi.mocked(etherMod.getDAIBalance).mockResolvedValue({
      block: 21000000n,
      name: 'Dai Stablecoin',
      symbol: 'DAI',
      balance: 2500000000000000000n, // 2.5 DAI (18 decimals)
      balanceFormatted: '2.5',
    })
    vi.mocked(etherMod.formatEther).mockReturnValue('2.5')

    renderWithProviders(<AccountForm />)
    const user = userEvent.setup()

    // Typing fires onKeyUp -> getBalance() with the default ETH asset; clear
    // that call history so the assertion below isolates the DAI selection.
    await user.type(screen.getByPlaceholderText('Address'), TEST_ADDRESS)
    vi.mocked(etherMod.getETHBalance).mockClear()
    vi.mocked(etherMod.getDAIBalance).mockClear()

    // Selecting DAI fires onChange -> handleChange -> getBalance(), which reads
    // the live <select> value ('DAI') and routes to getDAIBalance.
    await user.selectOptions(screen.getByRole('combobox'), 'DAI')

    await waitFor(() => {
      expect(etherMod.getDAIBalance).toHaveBeenCalled()
    })
    await waitFor(() => {
      expect(screen.getByText(/Balance:.*2\.5/)).toBeInTheDocument()
      expect(screen.getByText(/Last Block:.*21000000/)).toBeInTheDocument()
    })
  })
})
