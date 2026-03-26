# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Dev Commands

All commands go through the Makefile. Use `make help` to list targets.

```bash
make install      # pnpm install (skips if node_modules is current)
make build        # tsc + vite build (runs install first)
make lint         # prettier --check
make format       # prettier --write
make check        # lint + build in one command
make run          # dev server at http://localhost:8080
make ci-install   # pnpm install --frozen-lockfile (CI only)
make ci-run       # run CI workflow locally via act
```

There are no tests in this project. The `build` target (which runs `tsc`) serves as the type-checking gate.

## Architecture

This is a React SPA that queries Ethereum blockchain balances (ETH and DAI) via ethers.js v6.

### Entry Flow

`src/main.tsx` → mounts `<App>` wrapped in MUI `ThemeProvider` + Redux `Provider`

`src/App.tsx` → renders `Header`/`Footer` layout with `react-router-dom` `BrowserRouter`. Routes defined in `src/router/index.ts` map paths to page components.

### Key Layers

- **Pages** (`src/pages/`): Route-level components (`index/` = home, `about/`)
- **Components** (`src/components/`): `AccountForm` (blockchain query UI), `Counter` (Redux demo), `Layout` (Header/Footer with MUI drawer nav), `Logo`
- **Ethereum service** (`src/service/ether/ether.ts`): Uses `ethers.JsonRpcProvider` to query ETH balances and DAI token contract. RPC endpoint comes from `VITE_RPCENDPOINT` env var.
- **State** (`src/store/`): Rematch (Redux wrapper) with models for `counter` and `common` (language). Not Redux Toolkit — uses `@rematch/core` `createModel` pattern.
- **i18n** (`src/locale.ts`): i18next with static English translations from `src/locales/en.json`

### Path Alias

`@/` maps to `src/` — configured in both `tsconfig.json` (`paths`) and `vite.config.ts` (`resolve.alias`).

### Styling

Tailwind CSS v4 with `@tailwindcss/postcss`. Custom colors (`primary`, `secondary`) in `tailwind.config.js`. CSS files using `@apply` outside the main entry need `@reference "tailwindcss"` directive (see `src/App.css`). MUI v7 theme in `src/theme.tsx`.

## CI/CD

- **ci.yml**: `ci-install` → `lint` → `build` on every push/PR. Docker image build+push to GHCR only on tag push.
- All GitHub Actions pinned to commit SHAs. Renovate manages dependency updates with automerge for non-major.
- TypeScript is pinned to `<6.0.0` in `renovate.json` — do not upgrade to TS 6.x.

## Conventions

- Package manager: **pnpm** (not npm/yarn)
- Formatting: **prettier** only (no eslint)
- Commit messages: conventional commits (`feat:`, `fix:`, `chore:`, `ci:`, `refactor:`, `docs:`)
