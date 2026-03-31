import { ethers } from 'ethers'

export let provider: ethers.JsonRpcProvider
export let ETHbalance: bigint
export let ETHblock: number

export let DAIContractName: string
export let DAISymbol: string
export let DAIBalance: bigint
export let DAIBalanceFormatted: string
export let DAIblock: number

export async function getProvider() {
  provider = new ethers.JsonRpcProvider(import.meta.env.VITE_RPCENDPOINT)
  await provider.ready
}

export async function getETHBalance(account: string) {
  try {
    ETHblock = 0
    ETHbalance = 0n
    getProvider()

    return Promise.all([
      (ETHblock = await provider.getBlockNumber()),
      (ETHbalance = await provider.getBalance(account)),
    ]).catch((error) => {
      console.log(error)
      return [null, null, null]
    })
  } catch (error) {
    console.log(error)
  }
}

export async function getDAIBalance(address: string) {
  try {
    DAIblock = 0
    DAIBalance = 0n
    getProvider()

    const daiAddress = 'dai.tokens.ethers.eth'
    const daiAbi = [
      'function name() view returns (string)',
      'function symbol() view returns (string)',
      'function balanceOf(address) view returns (uint)',
      'function transfer(address to, uint amount)',
      'event Transfer(address indexed from, address indexed to, uint amount)',
    ]
    const daiContract = new ethers.Contract(daiAddress, daiAbi, provider)

    return Promise.all([
      (DAIblock = await provider.getBlockNumber()),
      (DAIContractName = await daiContract.name()),
      (DAISymbol = await daiContract.symbol()),
      (DAIBalance = await daiContract.balanceOf(address)),
      (DAIBalanceFormatted = ethers.formatUnits(DAIBalance, 18)),
    ]).catch((error) => {
      console.log(error)
      return [null, null, null]
    })
  } catch (error) {
    console.log(error)
  }
}
