# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Dev Commands

All commands go through the Makefile. Use `make help` to list targets.

```bash
make deps          # install prerequisite tools (nvm, node, pnpm)
make deps-act      # install act for local CI
make deps-hadolint # install hadolint for Dockerfile linting
make deps-k8s      # install kubectl, kind, yq
make install       # pnpm install (skips if node_modules is current)
make build         # tsc + vite build (runs install first)
make lint          # prettier --check + hadolint linting of both Dockerfiles
make format        # prettier --write
make check         # lint + test + build in one command
make test          # run tests once (vitest)
make test-watch    # run tests in watch mode
make test-coverage # run tests with coverage report
make run           # dev server at http://localhost:8080
make ci-install    # pnpm install --frozen-lockfile (CI only, no deps)
make ci-run        # run CI workflow locally via act
make upgrade       # upgrade dependencies
make deps-prune    # check for unused npm dependencies
make deps-prune-check # verify no prunable dependencies (CI gate)
```

## Testing

Vitest with React Testing Library and jsdom. Config in `vitest.config.ts`, global setup in `src/test/setup.ts`.

- **Unit tests**: `src/store/models/__tests__/` (Redux Toolkit slices), `src/service/ether/__tests__/` (ether service with mocked ethers.js)
- **Integration tests**: `src/components/__tests__/` (AccountForm, Counter, App — rendered with providers)
- **Test utilities**: `src/test/test-utils.tsx` exports `renderWithProviders` (wraps components in Redux Provider, MUI ThemeProvider, MemoryRouter)

The ether service tests mock `ethers.JsonRpcProvider` and `ethers.Contract` to avoid real network calls. Component tests mock the `@/service/ether` module entirely.

## Tool Versions

All tool versions are pinned as constants at the top of the Makefile. `make deps` installs missing tools to `~/.local/bin` (no sudo). Node.js version is `lts/*` via `.node-version` (used by nvm and CI).

## Architecture

This is a React SPA that queries Ethereum blockchain balances (ETH and DAI) via ethers.js v6.

### Entry Flow

`src/main.tsx` → mounts `<App>` wrapped in MUI `ThemeProvider` + Redux `Provider`

`src/App.tsx` → renders `Header`/`Footer` layout with `react-router-dom` `BrowserRouter`. Routes defined in `src/router/index.ts` map paths to page components.

### Key Layers

- **Pages** (`src/pages/`): Route-level components (`index/` = home, `about/`)
- **Components** (`src/components/`): `AccountForm` (blockchain query UI), `Counter` (Redux demo), `Layout` (Header/Footer with MUI drawer nav), `Logo`
- **Ethereum service** (`src/service/ether/ether.ts`): Uses `ethers.JsonRpcProvider` to query ETH balances and DAI token contract. RPC endpoint comes from `VITE_RPCENDPOINT` env var.
- **State** (`src/store/`): Redux Toolkit with slices for `counter` (`counterSlice.ts`) and `common` (`commonSlice.ts`). Uses `configureStore`, `createSlice`, and typed hooks (`useAppDispatch`, `useAppSelector`).
- **i18n** (`src/locale.ts`): i18next with `react-i18next`, static English translations from `src/locales/en.json`

### Path Alias

`@/` maps to `src/` — configured in both `tsconfig.json` (`paths`) and `vite.config.ts` (`resolve.alias`).

### Styling

Tailwind CSS v4 with `@tailwindcss/postcss`. Custom colors (`primary`, `secondary`) in `tailwind.config.js`. CSS files using `@apply` outside the main entry need `@reference "tailwindcss"` directive (see `src/App.css`). MUI v7 theme in `src/theme.tsx`.

### Build

Vite 8 with oxc minifier (not terser). Console and debugger statements are stripped in production via `build.oxc.compress` in `vite.config.ts`. Vendor chunks are split via `rolldownOptions.output.manualChunks` (function, not object — Rolldown requirement) into `vendor-react`, `vendor-mui`, and `vendor-ethers`. Routes are lazy-loaded with `React.lazy()` + `<Suspense>`.

## CI/CD

- **ci.yml**: Separate jobs: `lint` → `test` + `build` (parallel) on push to main, tag push (`v*`), PRs, manual dispatch, and `workflow_call`. Docker image build+push to GHCR only on tag push (uses `Dockerfile.prod`). Docker job gated with `startsWith(github.ref, 'refs/tags/')`.
- **cleanup-runs.yml**: Weekly cleanup of old workflow runs (keeps 5, deletes after 7 days).
- **cleanup-images.yml**: Weekly cleanup of untagged GHCR images (keeps 5 most recent).
- All GitHub Actions pinned to commit SHAs. Renovate manages dependency updates with automerge enabled (major updates delayed 3 days).

## Docker

- **Dockerfile**: Dev image (Node alpine + pnpm dev server on port 8080)
- **Dockerfile.prod**: Multi-stage build (Node builder → nginx-unprivileged on port 8080)
- **`.dockerignore`**: Excludes `node_modules`, `dist`, `.git`
- **`.hadolint.yaml`**: Configures hadolint rule ignores for Dockerfile linting
- Both Dockerfiles use `pnpm install --frozen-lockfile` and copy lockfiles before source for layer caching

## Conventions

- Package manager: **pnpm** (not npm/yarn)
- Node.js version: **LTS** via `.node-version` (not hardcoded)
- TypeScript: **6.x** with `moduleResolution: "bundler"` (no `baseUrl`, no `esModuleInterop`)
- Formatting: **prettier** only (no eslint)
- Dockerfile linting: **hadolint** via `make lint` (installed by `deps-hadolint` target)
- Commit messages: conventional commits (`feat:`, `fix:`, `chore:`, `ci:`, `refactor:`, `docs:`, `perf:`)
- Release: `make release` validates semver format (`vN.N.N`) before tagging
- State management: **Redux Toolkit** with `createSlice` pattern (migrated from Rematch)

## Upgrade Backlog

Last reviewed: 2026-04-04. Review on next pass — resolve actionable items, remove stale ones.

- [x] ~~**Remove stale `.eslintrc.js`**~~ — deleted (2026-04-03)
- [x] ~~**Remove dead `src/service/_api/` and `src/utils/util.ts`**~~ — deleted (2026-04-04), unused since Rematch migration
- [x] ~~**Remove unused deps `axios`, `i18next-http-backend`, `pretty-quick`**~~ — removed (2026-04-04)
- [ ] **Monitor ethers.js maintainer activity** — 635 open issues, single maintainer (ricmoo), last push 2026-02-13. If responsiveness declines further, evaluate `viem` as alternative.
- [ ] **Update nginx base image** — `1.29.5-alpine` → `1.29.7-alpine` when Docker image is published (Renovate handles via digest)

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.yml` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
