// AccountForm.tsx
import React, { useState } from 'react'
import { t } from 'i18next'
import {
  formatEther,
  getAddress,
  getDAIBalance,
  getETHBalance,
} from '@/service/ether'
import { config } from '@/config'

const RPCENDPOINT = config.VITE_RPCENDPOINT || 'not configured'
const ERRMSG = 'Could not retrieve info from blockchain using\n'

function isValidAddress(value: string): boolean {
  try {
    getAddress(value)
    return true
  } catch {
    return false
  }
}

const AccountForm = () => {
  const [destinationAddress, setDestinationAddress] = useState('')
  const [balance, setBalance] = useState<bigint>(0n)
  const [block, setBlock] = useState(0)
  const [asset, setAsset] = useState('ETH')
  const [disable, setDisable] = useState(false)

  const getBalance = async (_event?: unknown) => {
    if (!isValidAddress(destinationAddress)) return
    setDisable(true)
    setBalance(0n)
    setBlock(0)
    const assetCbValue: string = (
      document.getElementById('selectAsset') as HTMLInputElement
    ).value

    try {
      if (assetCbValue == 'ETH') {
        const result = await getETHBalance(destinationAddress)
        setBalance(result.balance)
        setBlock(Number(result.block))
      } else {
        const result = await getDAIBalance(destinationAddress)
        setBalance(result.balance)
        setBlock(Number(result.block))
      }
    } catch (e) {
      console.error(e)
      alert(ERRMSG + RPCENDPOINT)
    } finally {
      setDisable(false)
    }
  }

  const handleChange = (event?: React.ChangeEvent<HTMLSelectElement>) => {
    try {
      setAsset(event!.target.value)
      void getBalance(event)
    } catch (e) {
      console.log(e instanceof Error ? e.message : e)
    }
  }

  return (
    <div className="p-5 shadow text-left flex flex-col">
      <div className="pt-1 font-normal">
        <input
          disabled={disable}
          placeholder={t('address')}
          value={destinationAddress}
          className="w-96 border form-control mb-5 text-sm text-neutral-700"
          onChange={(event) => {
            setDestinationAddress(event.target.value)
          }}
          onKeyUp={() => {
            void getBalance()
          }}
        />
        <select
          value={asset}
          disabled={disable}
          name="selectAsset"
          id="selectAsset"
          className="text-neutral-700"
          onChange={handleChange}
        >
          <option value="ETH">ETH</option>
          <option value="DAI">DAI</option>
        </select>
      </div>

      <div className="pt-1 font-bold text-neutral-700">
        <>
          {t('balance')}: {formatEther(balance)}
        </>
      </div>
      <div className="pt-1 font-bold text-neutral-700">
        <>
          {t('block')}: {block}
        </>
      </div>
      <div className="pt-4">
        <button
          style={{ float: 'right' }}
          disabled={disable}
          id="GetBalanceButton"
          name="GetBalanceButton"
          className="text-sm bg-primary text-white px-6 py-2 btn rounded-full shadow shadow-gray-500/50"
          onClick={getBalance}
        >
          <span>Get Balance</span>
        </button>
      </div>
    </div>
  )
}

export default AccountForm
