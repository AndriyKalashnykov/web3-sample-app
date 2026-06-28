import { test, expect, type Page } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'

const TEST_ADDRESS = '0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf'

// Poll the rendered "Last Block: <n>" until it updates from 0 to a real block
// height. The callback is wrapped in try/catch: an in-flight React re-render
// (the form disables/re-enables during the async query) can detach the node
// mid-`innerText`, which `expect.poll` treats as a HARD failure rather than a
// retry — returning 0 on a throw keeps it polling. (rules/common/testing.md)
async function pollBlockGreaterThanZero(page: Page) {
  await expect
    .poll(
      async () => {
        try {
          const text = await page.getByText(/Last Block:/).innerText()
          const match = text.match(/Last Block:\s*(\d+)/)
          return match ? Number(match[1]) : 0
        } catch {
          return 0
        }
      },
      { timeout: 30_000, intervals: [500, 1000, 2000] },
    )
    .toBeGreaterThan(0)
}

// After a query lands (block > 0), the "Balance: <value>" line must render a
// well-formed non-negative decimal — NOT just any non-empty text. This catches a
// format/ABI regression (formatEther/formatUnits change, DAI ABI/contract drift)
// that returns a block but garbage balance ("NaN", "undefined", "[object Object]").
async function expectBalanceIsNumeric(page: Page) {
  const text = await page.getByText(/Balance:/).innerText()
  const match = text.match(/Balance:\s*([0-9]+(?:\.[0-9]+)?)\b/)
  expect(match, `Balance line "${text}" is not a plain decimal`).not.toBeNull()
  expect(Number(match![1])).toBeGreaterThanOrEqual(0)
}

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
    // `block` renders as "Last Block: <n>" (see src/locales/en.json).
    await pollBlockGreaterThanZero(page)
    // …and the Balance line must render a real numeric value, not just a block.
    await expectBalanceIsNumeric(page)
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

    await pollBlockGreaterThanZero(page)
    // The DAI balance line (formatUnits over the balanceOf read) must also render
    // a well-formed number — a DAI-specific ABI/contract regression that returns
    // a block but garbage balance is caught here, not just at the block counter.
    await expectBalanceIsNumeric(page)
  })

  test('home page has no critical or serious accessibility violations (axe)', async ({
    page,
  }) => {
    // Emulate reduced motion via emulateMedia (NOT config `use.reducedMotion`,
    // which is shadowed by the `devices['Desktop Chrome']` use block) so axe
    // reads settled colors, never mid-transition blends. (rules/common/testing.md)
    await page.emulateMedia({ reducedMotion: 'reduce' })
    await page.goto('/')
    await expect(page.locator('#root')).toBeVisible()

    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .analyze()
    const blocking = results.violations.filter(
      (v) => v.impact === 'critical' || v.impact === 'serious',
    )
    expect(
      blocking,
      `axe critical/serious violations: ${JSON.stringify(blocking.map((v) => v.id))}`,
    ).toEqual([])
  })
})
