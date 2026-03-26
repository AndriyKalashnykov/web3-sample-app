import { describe, it, expect } from 'vitest'
import {
  renderWithProviders,
  screen,
  userEvent,
} from '@/test/test-utils'
import Counter from '@/components/Counter'

describe('Counter component', () => {
  it('renders with initial count of 0', () => {
    renderWithProviders(<Counter />)
    expect(screen.getByText(/Click me - 0/)).toBeInTheDocument()
  })

  it('increments on click', async () => {
    renderWithProviders(<Counter />)
    const user = userEvent.setup()
    await user.click(screen.getByText(/Click me - 0/))
    expect(screen.getByText(/Click me - 1/)).toBeInTheDocument()
  })

  it('increments multiple times', async () => {
    renderWithProviders(<Counter />)
    const user = userEvent.setup()
    const el = screen.getByText(/Click me - 0/)
    await user.click(el)
    await user.click(screen.getByText(/Click me - 1/))
    await user.click(screen.getByText(/Click me - 2/))
    expect(screen.getByText(/Click me - 3/)).toBeInTheDocument()
  })
})
