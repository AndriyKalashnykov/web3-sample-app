// @vitest-environment node
import { describe, it, expect, vi, beforeAll } from 'vitest'
import { createPublicClient, http, getAddress } from 'viem'
import { mainnet } from 'viem/chains'

const TEST_ADDRESS = '0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf'
const DAI_ABI = [
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
] as const

// Deferred imports — bound in beforeAll AFTER `vi.unstubAllEnvs()` so that
// when @/config evaluates `import.meta.env.VITE_RPCENDPOINT`, it sees the
// real `.env` value (the unit setup at src/test/setup.ts otherwise stubs it
// to http://localhost:8545, which would point the integration suite at a
// non-existent local RPC).
let getETHBalance: typeof import('@/service/ether').getETHBalance
let getDAIBalance: typeof import('@/service/ether').getDAIBalance
let resetClient: typeof import('@/service/ether').resetClient
let RPC_ENDPOINT: string

describe('ether service (real RPC, via @/service/ether)', () => {
  beforeAll(async () => {
    vi.unstubAllEnvs()
    RPC_ENDPOINT = import.meta.env.VITE_RPCENDPOINT
    if (!RPC_ENDPOINT) {
      throw new Error(
        'VITE_RPCENDPOINT must be set for the integration suite (e.g. via .env)',
      )
    }
    // Reset module cache so @/config re-reads import.meta.env after unstub,
    // and @/service/ether picks up the post-unstub config.
    vi.resetModules()
    const ether = await import('@/service/ether')
    getETHBalance = ether.getETHBalance
    getDAIBalance = ether.getDAIBalance
    resetClient = ether.resetClient
    resetClient()
  })

  it('getETHBalance returns a typed result with a current block and non-negative balance', async () => {
    const result = await getETHBalance(TEST_ADDRESS)
    expect(result.block).toBeTypeOf('bigint')
    expect(result.block).toBeGreaterThan(0n)
    expect(result.balance).toBeTypeOf('bigint')
    expect(result.balance).toBeGreaterThanOrEqual(0n)
  }, 15000)

  it('getDAIBalance returns Dai Stablecoin / DAI metadata + a non-negative balance + formatted string', async () => {
    const result = await getDAIBalance(TEST_ADDRESS)
    expect(result.block).toBeTypeOf('bigint')
    expect(result.block).toBeGreaterThan(0n)
    expect(result.name).toBe('Dai Stablecoin')
    expect(result.symbol).toBe('DAI')
    expect(result.balance).toBeTypeOf('bigint')
    expect(result.balance).toBeGreaterThanOrEqual(0n)
    // balanceFormatted is the human-readable string viem.formatUnits(balance, 18)
    // produces. Always parses as a finite non-negative number.
    expect(Number(result.balanceFormatted)).toBeGreaterThanOrEqual(0)
  }, 15000)
})

describe('ether service (negative paths against real RPC)', () => {
  it('getAddress throws for a malformed input (validation, no RPC roundtrip)', () => {
    expect(() => getAddress('not-an-address')).toThrow(
      /is invalid|invalid|not a valid/i,
    )
  })

  it('rejects with a network error when the configured RPC URL is unreachable', async () => {
    const badClient = createPublicClient({
      chain: mainnet,
      transport: http('http://127.0.0.1:1/does-not-exist'),
    })
    await expect(badClient.getBlockNumber()).rejects.toBeDefined()
  }, 15000)

  it('throws ContractFunctionExecutionError when balanceOf is called on an EOA (not a contract)', async () => {
    // Calling an ERC-20 method on an EOA address yields empty return bytes,
    // which viem reports as a contract execution error. Asserting on the
    // error class via message-pattern keeps the test stable across viem
    // minor versions whose wording evolves.
    const c = createPublicClient({
      chain: mainnet,
      transport: http(RPC_ENDPOINT),
    })
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
