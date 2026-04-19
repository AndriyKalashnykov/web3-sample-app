import {
  createPublicClient,
  http,
  formatEther as viemFormatEther,
  formatUnits as viemFormatUnits,
  getAddress,
  parseAbi,
  type Address,
  type PublicClient,
} from 'viem'
import { mainnet } from 'viem/chains'

// DAI ERC-20 mainnet contract — hardcoded canonical address (was previously
// resolved via ENS `dai.tokens.ethers.eth`; pinning the address eliminates
// an unnecessary RPC roundtrip and the ENS dependency).
const DAI_ADDRESS: Address = '0x6B175474E89094C44Da98b954EedeAC495271d0F'

const DAI_ABI = parseAbi([
  'function name() view returns (string)',
  'function symbol() view returns (string)',
  'function balanceOf(address) view returns (uint256)',
])

export type ETHResult = { block: bigint; balance: bigint }
export type DAIResult = {
  block: bigint
  name: string
  symbol: string
  balance: bigint
  balanceFormatted: string
}

let cachedClient: PublicClient | undefined

function getClient(): PublicClient {
  if (cachedClient) return cachedClient
  const url = import.meta.env.VITE_RPCENDPOINT
  if (!url) throw new Error('VITE_RPCENDPOINT is not configured')
  cachedClient = createPublicClient({
    chain: mainnet,
    transport: http(url),
  })
  return cachedClient
}

// Reset the cached client — used by tests that mutate VITE_RPCENDPOINT
// across cases (the viem PublicClient holds onto the transport URL).
export function resetClient(): void {
  cachedClient = undefined
}

export async function getETHBalance(account: string): Promise<ETHResult> {
  const client = getClient()
  const address = getAddress(account)
  const [block, balance] = await Promise.all([
    client.getBlockNumber(),
    client.getBalance({ address }),
  ])
  return { block, balance }
}

export async function getDAIBalance(account: string): Promise<DAIResult> {
  const client = getClient()
  const address = getAddress(account)
  const [block, name, symbol, balance] = await Promise.all([
    client.getBlockNumber(),
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
      args: [address],
    }),
  ])
  return {
    block,
    name,
    symbol,
    balance,
    balanceFormatted: viemFormatUnits(balance, 18),
  }
}

// Re-export viem helpers callers use directly (e.g. AccountForm formats
// the displayed wei balance with formatEther). Keeps viem out of the
// component layer.
export const formatEther = viemFormatEther
export const formatUnits = viemFormatUnits
export { getAddress }
