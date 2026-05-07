import { test, expect } from '@playwright/test'

const TEST_ADDRESS = '0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf'

test.describe('Web3 Sample App — AccountForm', () => {
  test('renders the SPA shell and AccountForm controls', async ({ page }) => {
    await page.goto('/')

    await expect(page.locator('#root')).toBeVisible()

    // The address input + asset selector + Get Balance button must render.
    await expect(page.locator('input[placeholder]').first()).toBeVisible()
    await expect(page.locator('#selectAsset')).toBeVisible()
    await expect(page.locator('#GetBalanceButton')).toBeVisible()

    // Asset selector defaults to ETH.
    await expect(page.locator('#selectAsset')).toHaveValue('ETH')
  })

  test('queries an ETH balance against the real RPC and renders a numeric block', async ({
    page,
  }) => {
    await page.goto('/')

    // Type a known address with non-zero ETH balance and submit.
    await page.locator('input[placeholder]').first().fill(TEST_ADDRESS)
    await page.locator('#GetBalanceButton').click()

    // Block counter must update from 0 to a real block height (>0). 30s budget
    // covers cold RPC latency without masking a real failure. Translation key
    // `block` renders as "Last Block: <n>" (see src/locales/en.json) — match
    // by the unique label suffix, not a `^block` anchor.
    await expect
      .poll(
        async () => {
          const text = await page.getByText(/Last Block:/).innerText()
          const match = text.match(/Last Block:\s*(\d+)/)
          return match ? Number(match[1]) : 0
        },
        { timeout: 30_000, intervals: [500, 1000, 2000] },
      )
      .toBeGreaterThan(0)
  })

  test('queries a DAI balance via 3 contract reads and renders a numeric block', async ({
    page,
  }) => {
    // The DAI flow exercises a different code path from ETH: getDAIBalance
    // issues 3 viem.readContract calls (name/symbol/balanceOf) against the
    // canonical mainnet DAI contract 0x6B17…1d0F. ETH-only browser e2e
    // would miss a DAI-specific regression (ABI typo, contract-address
    // drift, viem readContract envelope change).
    await page.goto('/')

    // Switch the asset selector to DAI BEFORE filling the address so the
    // change-handler doesn't fire an ETH lookup against an empty input.
    await page.locator('#selectAsset').selectOption('DAI')
    await expect(page.locator('#selectAsset')).toHaveValue('DAI')

    await page.locator('input[placeholder]').first().fill(TEST_ADDRESS)
    await page.locator('#GetBalanceButton').click()

    await expect
      .poll(
        async () => {
          const text = await page.getByText(/Last Block:/).innerText()
          const match = text.match(/Last Block:\s*(\d+)/)
          return match ? Number(match[1]) : 0
        },
        { timeout: 30_000, intervals: [500, 1000, 2000] },
      )
      .toBeGreaterThan(0)
  })
})
