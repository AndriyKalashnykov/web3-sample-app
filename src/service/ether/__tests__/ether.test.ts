import { describe, it, expect, vi, beforeEach } from 'vitest'

const mockGetBlockNumber = vi.fn().mockResolvedValue(12345)
const mockGetBalance = vi.fn().mockResolvedValue(1000000000000000000n)
const mockProvider = {
  ready: Promise.resolve(),
  getBlockNumber: mockGetBlockNumber,
  getBalance: mockGetBalance,
}

const mockContractName = vi.fn().mockResolvedValue('Dai Stablecoin')
const mockContractSymbol = vi.fn().mockResolvedValue('DAI')
const mockContractBalanceOf = vi.fn().mockResolvedValue(500000000000000000n)

vi.mock('ethers', () => {
  const MockJsonRpcProvider = vi.fn(function () {
    return mockProvider
  })
  const MockContract = vi.fn(function () {
    return {
      name: mockContractName,
      symbol: mockContractSymbol,
      balanceOf: mockContractBalanceOf,
    }
  })
  return {
    ethers: {
      JsonRpcProvider: MockJsonRpcProvider,
      Contract: MockContract,
      formatUnits: vi.fn(() => '0.5'),
    },
  }
})

describe('ether service', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('getProvider creates a provider with the env RPC endpoint', async () => {
    const { getProvider } = await import('@/service/ether/ether')
    await getProvider()
    const { ethers } = await import('ethers')
    expect(ethers.JsonRpcProvider).toHaveBeenCalledWith('http://localhost:8545')
  })

  it('getETHBalance returns block number and balance', async () => {
    const { getProvider, getETHBalance } = await import('@/service/ether/ether')
    await getProvider()
    const result = await getETHBalance(
      '0x1234567890abcdef1234567890abcdef12345678',
    )
    expect(mockGetBlockNumber).toHaveBeenCalled()
    expect(mockGetBalance).toHaveBeenCalledWith(
      '0x1234567890abcdef1234567890abcdef12345678',
    )
    expect(result).toBeDefined()
  })

  it('getETHBalance handles provider errors gracefully', async () => {
    mockGetBlockNumber.mockRejectedValueOnce(new Error('network error'))
    const { getProvider, getETHBalance } = await import('@/service/ether/ether')
    await getProvider()
    const result = await getETHBalance('0x1234')
    expect(result).toBeUndefined()
  })

  it('getDAIBalance returns token info and balance', async () => {
    const { getProvider, getDAIBalance } = await import('@/service/ether/ether')
    await getProvider()
    const result = await getDAIBalance(
      '0x1234567890abcdef1234567890abcdef12345678',
    )
    expect(mockContractName).toHaveBeenCalled()
    expect(mockContractSymbol).toHaveBeenCalled()
    expect(mockContractBalanceOf).toHaveBeenCalledWith(
      '0x1234567890abcdef1234567890abcdef12345678',
    )
    expect(result).toBeDefined()
  })

  it('getDAIBalance handles contract errors gracefully', async () => {
    mockContractName.mockRejectedValueOnce(new Error('contract error'))
    const { getProvider, getDAIBalance } = await import('@/service/ether/ether')
    await getProvider()
    const result = await getDAIBalance('0x1234')
    expect(result).toBeUndefined()
  })
})
