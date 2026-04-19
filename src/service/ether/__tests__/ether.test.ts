import { describe, it, expect, vi, beforeEach } from 'vitest'

// A canonical valid Ethereum address (checksummed) so viem's getAddress
// doesn't reject the input before our service code runs.
const TEST_ADDRESS = '0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf'

const mockClient = {
  getBlockNumber: vi.fn().mockResolvedValue(12345n),
  getBalance: vi.fn().mockResolvedValue(1000000000000000000n),
  readContract: vi.fn().mockImplementation(async ({ functionName }) => {
    if (functionName === 'name') return 'Dai Stablecoin'
    if (functionName === 'symbol') return 'DAI'
    if (functionName === 'balanceOf') return 500000000000000000n
    throw new Error(`unexpected functionName: ${functionName}`)
  }),
}

vi.mock('viem', async () => {
  const actual = await vi.importActual<typeof import('viem')>('viem')
  return {
    ...actual,
    createPublicClient: vi.fn(() => mockClient),
    http: vi.fn(() => 'mock-transport'),
  }
})

describe('ether service', () => {
  beforeEach(async () => {
    vi.clearAllMocks()
    // Restore default mock behaviors after vi.clearAllMocks().
    mockClient.getBlockNumber.mockResolvedValue(12345n)
    mockClient.getBalance.mockResolvedValue(1000000000000000000n)
    mockClient.readContract.mockImplementation(async ({ functionName }) => {
      if (functionName === 'name') return 'Dai Stablecoin'
      if (functionName === 'symbol') return 'DAI'
      if (functionName === 'balanceOf') return 500000000000000000n
      throw new Error(`unexpected functionName: ${functionName}`)
    })
    // Reset cached PublicClient between tests so createPublicClient is
    // re-invoked and the test can assert against the call.
    const { resetClient } = await import('@/service/ether/ether')
    resetClient()
  })

  it('getETHBalance creates a viem client with the env RPC endpoint', async () => {
    const { getETHBalance } = await import('@/service/ether/ether')
    await getETHBalance(TEST_ADDRESS)
    const { createPublicClient, http } = await import('viem')
    expect(http).toHaveBeenCalledWith('http://localhost:8545')
    expect(createPublicClient).toHaveBeenCalled()
  })

  it('getETHBalance returns block number and balance', async () => {
    const { getETHBalance } = await import('@/service/ether/ether')
    const result = await getETHBalance(TEST_ADDRESS)
    expect(mockClient.getBlockNumber).toHaveBeenCalled()
    expect(mockClient.getBalance).toHaveBeenCalledWith({
      address: TEST_ADDRESS,
    })
    expect(result).toEqual({
      block: 12345n,
      balance: 1000000000000000000n,
    })
  })

  it('getETHBalance propagates network errors', async () => {
    mockClient.getBlockNumber.mockRejectedValueOnce(new Error('network error'))
    const { getETHBalance } = await import('@/service/ether/ether')
    await expect(getETHBalance(TEST_ADDRESS)).rejects.toThrow('network error')
  })

  it('getDAIBalance returns token info and balance', async () => {
    const { getDAIBalance } = await import('@/service/ether/ether')
    const result = await getDAIBalance(TEST_ADDRESS)
    expect(mockClient.readContract).toHaveBeenCalledTimes(3)
    expect(result).toEqual({
      block: 12345n,
      name: 'Dai Stablecoin',
      symbol: 'DAI',
      balance: 500000000000000000n,
      balanceFormatted: '0.5',
    })
  })

  it('getDAIBalance propagates contract errors', async () => {
    mockClient.readContract.mockImplementationOnce(async () => {
      throw new Error('contract error')
    })
    const { getDAIBalance } = await import('@/service/ether/ether')
    await expect(getDAIBalance(TEST_ADDRESS)).rejects.toThrow('contract error')
  })

  it('getETHBalance rejects malformed addresses before calling RPC', async () => {
    const { getETHBalance } = await import('@/service/ether/ether')
    await expect(getETHBalance('not-an-address')).rejects.toThrow(
      /is invalid|invalid address|not a valid/i,
    )
    expect(mockClient.getBalance).not.toHaveBeenCalled()
  })
})
