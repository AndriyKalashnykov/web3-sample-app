// @vitest-environment node
import { describe, it, expect, vi, beforeAll } from 'vitest'
import { ethers } from 'ethers'

let RPC_ENDPOINT: string
const TEST_ADDRESS = '0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf'

describe('ether service (real RPC)', () => {
  let provider: ethers.JsonRpcProvider

  beforeAll(() => {
    vi.unstubAllEnvs()
    RPC_ENDPOINT = import.meta.env.VITE_RPCENDPOINT
  })

  it('retrieves a block number from the network', async () => {
    provider = new ethers.JsonRpcProvider(RPC_ENDPOINT)
    const block = await provider.getBlockNumber()
    expect(block).toBeGreaterThan(0)
  }, 15000)

  it('retrieves ETH balance for a real address', async () => {
    const balance = await provider.getBalance(TEST_ADDRESS)
    expect(balance).toBeTypeOf('bigint')
    expect(balance).toBeGreaterThanOrEqual(0n)

    const formatted = ethers.formatEther(balance)
    expect(Number(formatted)).toBeGreaterThanOrEqual(0)
  }, 15000)

  it('retrieves DAI token info and balance for a real address', async () => {
    const daiAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
    const daiAbi = [
      'function name() view returns (string)',
      'function symbol() view returns (string)',
      'function balanceOf(address) view returns (uint)',
    ]
    const daiContract = new ethers.Contract(daiAddress, daiAbi, provider)

    const [name, symbol, balance] = await Promise.all([
      daiContract.name(),
      daiContract.symbol(),
      daiContract.balanceOf(TEST_ADDRESS),
    ])

    expect(name).toBe('Dai Stablecoin')
    expect(symbol).toBe('DAI')
    expect(balance).toBeTypeOf('bigint')
    expect(balance).toBeGreaterThanOrEqual(0n)
  }, 15000)
})
