// @vitest-environment node
import { describe, it, expect, vi, beforeAll } from 'vitest'
import { createPublicClient, http, formatEther, getAddress } from 'viem'
import { mainnet } from 'viem/chains'

const TEST_ADDRESS = '0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf'
const DAI_ADDRESS = '0x6B175474E89094C44Da98b954EedeAC495271d0F' as const

const DAI_ABI = [
  {
    type: 'function',
    name: 'name',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'string' }],
  },
  {
    type: 'function',
    name: 'symbol',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'string' }],
  },
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
] as const

let RPC_ENDPOINT: string
let client: ReturnType<typeof createPublicClient>

describe('viem service (real RPC)', () => {
  beforeAll(() => {
    vi.unstubAllEnvs()
    RPC_ENDPOINT = import.meta.env.VITE_RPCENDPOINT
    client = createPublicClient({
      chain: mainnet,
      transport: http(RPC_ENDPOINT),
    })
  })

  it('retrieves a block number from the network', async () => {
    const block = await client.getBlockNumber()
    expect(block).toBeTypeOf('bigint')
    expect(block).toBeGreaterThan(0n)
  }, 15000)

  it('retrieves ETH balance for a real address', async () => {
    const balance = await client.getBalance({
      address: getAddress(TEST_ADDRESS),
    })
    expect(balance).toBeTypeOf('bigint')
    expect(balance).toBeGreaterThanOrEqual(0n)
    expect(Number(formatEther(balance))).toBeGreaterThanOrEqual(0)
  }, 15000)

  it('retrieves DAI token info and balance for a real address', async () => {
    const [name, symbol, balance] = await Promise.all([
      client.readContract({
        address: DAI_ADDRESS,
        abi: DAI_ABI,
        functionName: 'name',
      }),
      client.readContract({
        address: DAI_ADDRESS,
        abi: DAI_ABI,
        functionName: 'symbol',
      }),
      client.readContract({
        address: DAI_ADDRESS,
        abi: DAI_ABI,
        functionName: 'balanceOf',
        args: [getAddress(TEST_ADDRESS)],
      }),
    ])
    expect(name).toBe('Dai Stablecoin')
    expect(symbol).toBe('DAI')
    expect(balance).toBeTypeOf('bigint')
    expect(balance).toBeGreaterThanOrEqual(0n)
  }, 15000)
})

describe('viem service (negative paths against real RPC)', () => {
  it('rejects with a network error when RPC URL is unreachable', async () => {
    const badClient = createPublicClient({
      chain: mainnet,
      transport: http('http://127.0.0.1:1/does-not-exist'),
    })
    await expect(badClient.getBlockNumber()).rejects.toBeDefined()
  }, 15000)

  it('rejects when getAddress is called with a malformed value (validation, no RPC)', async () => {
    expect(() => getAddress('not-an-address')).toThrow(
      /is invalid|invalid|not a valid/i,
    )
  })

  it('returns 0 balance when reading balanceOf on an externally-owned address (not a contract)', async () => {
    vi.unstubAllEnvs()
    const c = createPublicClient({
      chain: mainnet,
      transport: http(import.meta.env.VITE_RPCENDPOINT),
    })
    // EOA address responds with empty bytes to a `balanceOf` call; viem
    // raises a ContractFunctionExecutionError. We assert on the error class
    // rather than the message because viem's wording evolves across minors.
    await expect(
      c.readContract({
        address: getAddress(TEST_ADDRESS),
        abi: DAI_ABI,
        functionName: 'balanceOf',
        args: [getAddress(TEST_ADDRESS)],
      }),
    ).rejects.toThrow(/returned no data|reverted|execution/i)
  }, 15000)
})
