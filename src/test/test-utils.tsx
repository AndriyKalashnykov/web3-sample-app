import { render, RenderOptions } from '@testing-library/react'
import { Provider } from 'react-redux'
import { ThemeProvider } from '@mui/material/styles'
import { MemoryRouter } from 'react-router-dom'
import { init } from '@rematch/core'
import { models } from '@/store/models'
import { theme } from '@/theme'
import { ReactElement } from 'react'

function createTestStore() {
  return init({ models })
}

interface ExtendedRenderOptions extends Omit<RenderOptions, 'wrapper'> {
  store?: ReturnType<typeof createTestStore>
  route?: string
}

function renderWithProviders(
  ui: ReactElement,
  {
    store = createTestStore(),
    route = '/',
    ...renderOptions
  }: ExtendedRenderOptions = {},
) {
  function Wrapper({ children }: { children: React.ReactNode }) {
    return (
      <Provider store={store}>
        <ThemeProvider theme={theme}>
          <MemoryRouter initialEntries={[route]}>{children}</MemoryRouter>
        </ThemeProvider>
      </Provider>
    )
  }

  return { store, ...render(ui, { wrapper: Wrapper, ...renderOptions }) }
}

export { renderWithProviders, createTestStore }
export { screen, waitFor, act } from '@testing-library/react'
export { default as userEvent } from '@testing-library/user-event'
