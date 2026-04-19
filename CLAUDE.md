# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Dev Commands

All commands go through the Makefile. Use `make help` to list targets.

```bash
make deps           # install mise + all pinned tools (node, pnpm, hadolint, kubectl, kind, yq, trivy, gitleaks, act)
make install        # pnpm install (uses --frozen-lockfile when CI=true)
make build          # tsc + vite build (depends on install)
make lint           # prettier --check + hadolint
make format         # prettier --write
make test           # vitest run (unit + component, excludes *.integration.test.*)
make test-watch     # vitest in watch mode
make test-coverage  # vitest with coverage report
make integration-test # vitest run -c vitest.integration.config.ts (real RPC)
make e2e            # KinD + curl assertions against deployed nginx (e2e/e2e-test.sh)
make e2e-browser    # Playwright Chromium against the deployed SPA
make run            # dev server at http://localhost:8080
make vulncheck      # pnpm audit --audit-level=moderate
make trivy-fs       # Trivy fs scan (vuln + secret + misconfig)
make trivy-config   # Trivy IaC scan (k8s + Dockerfiles)
make secrets        # gitleaks over git history
make mermaid-lint   # validate ```mermaid blocks via minlag/mermaid-cli
make static-check   # composite gate: lint + vulncheck + trivy-fs + trivy-config + secrets + mermaid-lint + deps-prune-check
make check          # static-check + test + build (full local pipeline)
make ci             # CI pipeline: install + static-check + test + build
make ci-run         # run the GitHub Actions workflow locally via act
make upgrade        # pnpm upgrade
make deps-prune     # advisory: list unused npm dependencies
make deps-prune-check # CI gate: fail if unused deps exist
make renovate-validate # validate renovate.json
make cleanup-runs   # delete workflow runs older than 7 days (called by cleanup-runs.yml)
make cleanup-images # delete untagged GHCR images, keep 5 (called by cleanup-images.yml)
```

## Tool Versions (mise)

`.mise.toml` is the single source of truth for every pinned tool: Node.js, pnpm, hadolint, kubectl, kind, yq, Trivy, gitleaks, act. `make deps` bootstraps mise via `https://mise.run` (installs to `~/.local/bin`, no sudo) and then runs `mise install` to provision the rest. CI uses `jdx/mise-action` so local and CI read the same `.mise.toml`. Renovate tracks updates via the `mise` manager + the `# renovate:` inline comments on the `aqua:` pins.

`MERMAID_CLI_VERSION` and `RENOVATE_VERSION` are pinned as Makefile constants (with `# renovate:` annotations) because they're invoked via Docker / `npx`, not mise.

## Testing

Three-layer test pyramid. Each layer has its own Makefile target, vitest/Playwright config, and CI job:

| Layer | Target | Config | Files | Speed | What it covers |
|-------|--------|--------|-------|-------|----------------|
| Unit + Component | `make test` | `vitest.config.ts` (excludes `**/*.integration.test.*`) | `src/store/models/__tests__/`, `src/service/ether/__tests__/ether.test.ts`, `src/components/__tests__/` | ~1s | Pure functions, Redux slices, mocked ether service, components rendered via `renderWithProviders` |
| Integration | `make integration-test` | `vitest.integration.config.ts` (`include: ['**/*.integration.test.ts']`, 30s timeout, node env) | `src/service/ether/__tests__/ether.integration.test.ts` | ~5s | Ether service against the real `VITE_RPCENDPOINT` (block fetch, ETH/DAI balance, malformed-input negative paths) |
| E2E (curl) | `make e2e` | `e2e/e2e-test.sh` | KinD-deployed SPA via `kubectl port-forward` | ~30s | nginx routes (`/internal/isalive`, `/internal/isready`, `/publicnode` → 307, SPA fallback, missing asset 404) + verifies `start-nginx.sh` substituted `VITE_RPCENDPOINT` into served JS |
| E2E (browser) | `make e2e-browser` | `e2e/playwright.config.ts` + `e2e/account-form.spec.ts` | KinD-deployed SPA via Playwright Chromium | ~45s | AccountForm renders, real RPC roundtrip updates the displayed block number |

Notes:
- `make test` and `make integration-test` are independent — the `test` job runs unit + component (no network), `integration-test` job runs the real-RPC suite (needs outbound HTTPS).
- `e2e` is gated `if: ${{ vars.ACT != 'true' }}` in CI because KinD inside act isn't reliable; run `make e2e` locally.
- `e2e-browser` is local-dev only by default (Chromium download is heavy); promote to CI when browser-regression coverage becomes valuable.
- The ether unit tests mock `ethers.JsonRpcProvider` and `ethers.Contract`; component tests mock the `@/service/ether` module entirely.

## Architecture

This is a React SPA that queries Ethereum blockchain balances (ETH and DAI) via ethers.js v6. There is no backend — all blockchain calls happen in the browser against an external JSON-RPC endpoint configured via `VITE_RPCENDPOINT`.

### Entry Flow

`src/main.tsx` → mounts `<App>` wrapped in MUI `ThemeProvider` + Redux `Provider`

`src/App.tsx` → renders `Header`/`Footer` layout with `react-router-dom` `BrowserRouter`. Routes defined in `src/router/index.ts` map paths to page components, lazy-loaded with `React.lazy()` + `<Suspense>`.

### Key Layers

- **Pages** (`src/pages/`): Route-level components (`index/` = home, `about/`)
- **Components** (`src/components/`): `AccountForm` (blockchain query UI), `Counter` (Redux demo), `Layout` (Header/Footer with MUI drawer nav), `Logo`
- **Ethereum service** (`src/service/ether/ether.ts`): Uses `ethers.JsonRpcProvider` to query ETH balances and DAI token contract. RPC endpoint comes from `VITE_RPCENDPOINT` env var. DAI contract resolved via ENS name `dai.tokens.ethers.eth`.
- **State** (`src/store/`): Redux Toolkit with slices for `counter` (`counterSlice.ts`) and `common` (`commonSlice.ts`). Uses `configureStore`, `createSlice`, and typed hooks (`useAppDispatch`, `useAppSelector`).
- **i18n** (`src/locale.ts`): i18next with `react-i18next`, static English translations from `src/locales/en.json`

### Runtime env-var injection

`Dockerfile.prod` builds with placeholder env values; `start-nginx.sh` runs `envsubst` against the served JS bundles at container startup so `VITE_RPCENDPOINT` can be set per-environment without rebuilding the image. The K8s `ConfigMap` in `k8s/cm.yaml` provides this value in cluster.

### Path Alias

`@/` maps to `src/` — configured in both `tsconfig.json` (`paths`) and `vite.config.ts` (`resolve.alias`).

### Styling

Tailwind CSS v4 with `@tailwindcss/postcss`. Custom colors (`primary`, `secondary`) in `tailwind.config.js`. CSS files using `@apply` outside the main entry need `@reference "tailwindcss"` directive (see `src/App.css`). MUI v7 theme in `src/theme.tsx`.

### Build

Vite 8 with oxc minifier (not terser). Console and debugger statements are stripped in production via `build.oxc.compress` in `vite.config.ts`. Vendor chunks are split via `rolldownOptions.output.manualChunks` (function, not object — Rolldown requirement) into `vendor-react`, `vendor-mui`, and `vendor-ethers`.

## CI/CD

- **ci.yml**: `static-check` → `test` + `build` (parallel) → `docker` (tag-push only) → `ci-pass` (aggregator). Uses `jdx/mise-action` to provision tools from `.mise.toml`. `static-check` job runs `make static-check` (composite of lint + vulncheck + trivy-fs + trivy-config + secrets + mermaid-lint + deps-prune-check). Docker job multi-arch (`linux/amd64,linux/arm64`) with `provenance: false` + `sbom: false` so the GHCR Packages "OS / Arch" tab renders.
- **cleanup-runs.yml**: Weekly cleanup of old workflow runs (calls `make cleanup-runs`) + caches from merged branches.
- **cleanup-images.yml**: Weekly cleanup of untagged GHCR images (calls `make cleanup-images`).
- All GitHub Actions pinned to commit SHAs. Renovate manages dependency updates with platform automerge enabled (major updates delayed 3 days).

## Docker

- **Dockerfile**: Dev image (Node alpine + pnpm dev server on port 8080)
- **Dockerfile.prod**: Multi-stage build (Node builder → `nginxinc/nginx-unprivileged:1.29.5-alpine` on port 8080); OCI labels (artifacthub, vendor, license) baked in via `LABEL` instructions
- **`.dockerignore`**: Excludes `node_modules`, `dist`, `.git`
- **`.hadolint.yaml`**: Configures hadolint rule ignores for Dockerfile linting
- Both Dockerfiles use `pnpm install --frozen-lockfile` and copy lockfiles before source for layer caching

## Conventions

- Package manager: **pnpm** (not npm/yarn)
- Tool versioning: **mise** via `.mise.toml` (single source of truth across local + CI)
- Node.js: pinned in `.mise.toml` (currently `node = "24"`); `.node-version` retained as a fallback marker
- TypeScript: **6.x** with `moduleResolution: "bundler"` (no `baseUrl`, no `esModuleInterop`)
- Formatting: **prettier** only (no eslint)
- Static analysis: **prettier + hadolint + Trivy fs + Trivy config + gitleaks + mermaid-lint**, composed in `make static-check`
- Commit messages: conventional commits (`feat:`, `fix:`, `chore:`, `ci:`, `refactor:`, `docs:`, `perf:`)
- Release: `make release` validates semver format (`vN.N.N`), writes `version.txt`, commits and pushes the tag
- State management: **Redux Toolkit** with `createSlice` pattern (migrated from Rematch)

## Upgrade Backlog

Last reviewed: 2026-04-19. Review on next pass — resolve actionable items, remove stale ones.

- [x] ~~**Remove stale `.eslintrc.js`**~~ — deleted (2026-04-03)
- [x] ~~**Remove dead `src/service/_api/` and `src/utils/util.ts`**~~ — deleted (2026-04-04)
- [x] ~~**Remove unused deps `axios`, `i18next-http-backend`, `pretty-quick`**~~ — removed (2026-04-04)
- [x] ~~**Migrate from nvm + per-tool curl installers to mise**~~ — done (2026-04-19), `.mise.toml` is now the source of truth
- [x] ~~**Add composite `static-check` Makefile target**~~ — done (2026-04-19), includes Trivy fs/config + gitleaks + mermaid-lint
- [x] ~~**CI: switch to `jdx/mise-action` and `make static-check`**~~ — done (2026-04-19)
- [x] ~~**CI: add `ci-pass` aggregator job**~~ — done (2026-04-19)
- [x] ~~**Isolate `ether.integration.test.ts` from `make test`**~~ — done (2026-04-19), `vitest.integration.config.ts` + `make integration-test` + dedicated CI job; default `make test` excludes `**/*.integration.test.*`
- [x] ~~**Add `make e2e` target**~~ — done (2026-04-19), KinD + `kubectl port-forward` + `e2e/e2e-test.sh` (curl) + `e2e/account-form.spec.ts` (Playwright); CI `e2e` job gated `if: vars.ACT != 'true'`
- [ ] **Harden image publish pipeline** — current `docker` job pushes without Trivy image scan, smoke test, or cosign signing. Run `/harden-image-pipeline` for the canonical Pattern A migration.
- [ ] **Evaluate ethers.js → viem migration** — Bus factor = 1 (ricmoo), no release since 2025-12-03, no commits since 2026-02-13, 635 open issues. viem has 464 contributors, multiple releases/month, near npm download parity. Migration effort: major.
- [ ] **K8s deployment: enable resource requests/limits** — Currently commented out in `k8s/deployment.yaml`. Required for production workloads.
- [ ] **K8s deployment: add securityContext** — Missing `runAsNonRoot`, `readOnlyRootFilesystem` in `k8s/deployment.yaml`.
- [ ] **Dockerfile: migrate from `npm install -g pnpm` to corepack** — Both Dockerfiles use `npm --global install pnpm`; modern Node.js ships corepack which manages pnpm natively (`corepack enable pnpm`).

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `.mise.toml` | `/makefile` (mise version-manager rules live there) |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |
| `Dockerfile`, `Dockerfile.prod` (when changing publish pipeline) | `/harden-image-pipeline` |
| Any file under `e2e/`, `tests/integration/`, or new test layers | `/test-coverage-analysis` |
| Any markdown with ` ```mermaid `, or files under `docs/diagrams/` | `/architecture-diagrams` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
