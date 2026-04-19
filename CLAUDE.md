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

Four-layer test pyramid. Each layer has its own Makefile target, vitest/Playwright config, and CI job:

| Layer | Target | Config | Files | Speed | What it covers |
|-------|--------|--------|-------|-------|----------------|
| Unit + Component | `make test` | `vitest.config.ts` (excludes `**/*.integration.test.*`) | `src/store/models/__tests__/`, `src/service/ether/__tests__/ether.test.ts`, `src/components/__tests__/` | ~1s | Pure functions, Redux slices, mocked ether service, components rendered via `renderWithProviders` |
| Integration | `make integration-test` | `vitest.integration.config.ts` (`include: ['**/*.integration.test.ts']`, 30s timeout, node env) | `src/service/ether/__tests__/ether.integration.test.ts` | ~5s | Ether service against the real `VITE_RPCENDPOINT` (block fetch, ETH/DAI balance, malformed-input negative paths) |
| E2E (curl) | `make e2e` | `e2e/e2e-test.sh` | KinD + cloud-provider-kind LoadBalancer (kind Docker network IP) | ~30s | nginx routes (`/internal/isalive`, `/internal/isready`, `/publicnode` → 307, SPA fallback, missing asset 404) + verifies `start-nginx.sh` substituted `VITE_RPCENDPOINT` into served JS |
| E2E (browser) | `make e2e-browser` | `e2e/playwright.config.ts` + `e2e/account-form.spec.ts` | KinD + cloud-provider-kind + Playwright Chromium | ~45s | AccountForm renders, real RPC roundtrip updates the displayed block number |

Notes:
- `make test` and `make integration-test` are independent — the `test` job runs unit + component (no network), `integration-test` job runs the real-RPC suite (needs outbound HTTPS).
- `e2e` is gated `if: ${{ vars.ACT != 'true' }}` in CI because KinD inside act isn't reliable; run `make e2e` locally.
- `e2e-browser` is local-dev only by default (Chromium download is heavy); promote to CI when browser-regression coverage becomes valuable.
- The ether unit tests mock `ethers.JsonRpcProvider` and `ethers.Contract`; component tests mock the `@/service/ether` module entirely.

## Architecture

This is a React SPA that queries Ethereum blockchain balances (ETH and DAI) via viem 2. There is no backend — all blockchain calls happen in the browser against an external JSON-RPC endpoint configured via `VITE_RPCENDPOINT`.

### Entry Flow

`src/main.tsx` → mounts `<App>` wrapped in MUI `ThemeProvider` + Redux `Provider`

`src/App.tsx` → renders `Header`/`Footer` layout with `react-router-dom` `BrowserRouter`. Routes defined in `src/router/index.ts` map paths to page components, lazy-loaded with `React.lazy()` + `<Suspense>`.

### Key Layers

- **Pages** (`src/pages/`): Route-level components (`index/` = home, `about/`)
- **Components** (`src/components/`): `AccountForm` (blockchain query UI), `Counter` (Redux demo), `Layout` (Header/Footer with MUI drawer nav), `Logo`
- **Ethereum service** (`src/service/ether/ether.ts`): Uses viem's `createPublicClient` (mainnet, http transport) to query ETH balances and DAI token contract reads. Exposes `getETHBalance(addr)` and `getDAIBalance(addr)` returning typed result objects (`{block, balance}` / `{block, name, symbol, balance, balanceFormatted}`). RPC endpoint comes from `VITE_RPCENDPOINT` env var. DAI contract address hardcoded to canonical mainnet `0x6B17…1d0F` (no ENS lookup). Re-exports `formatEther`, `formatUnits`, `getAddress` so the component layer doesn't import viem directly.
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

- **ci.yml** job DAG: `static-check` → (`test`, `integration-test`, `build` parallel) → (`e2e`, `dast`, `docker` parallel) → `ci-pass` (aggregator).
  - `static-check`: composite of lint + vulncheck + trivy-fs + trivy-config + secrets + mermaid-lint + deps-prune-check via `make static-check`.
  - `integration-test`: real-RPC vitest suite (`make integration-test`).
  - `e2e`: KinD + `cloud-provider-kind` (real LoadBalancer Service IPs on the kind Docker network) + curl assertions via `make e2e`. Gated `if: vars.ACT != 'true'`.
  - `dast`: parallel with `docker`/`e2e`. Builds `:scan` image via shared cache, boots it, runs OWASP ZAP baseline (`-I`, FAIL-only blocking). Cached ZAP image (~3.4GB). Gated `if: vars.ACT != 'true'`. Uploads HTML/JSON/MD report.
  - `docker` (tag-push only): Pattern A pre-push gates → multi-arch publish → cosign sign-by-digest.
    - Gate 1: Build for scan (`load: true`, linux/amd64) into local docker daemon
    - Gate 2: Trivy image scan (`CRITICAL,HIGH` blocking, `vuln,secret,misconfig` scanners)
    - Gate 3: Smoke test (`docker run` + `curl /internal/isalive`)
    - Build & push: multi-arch (`linux/amd64,linux/arm64`), `provenance: false` + `sbom: false` (keeps GHCR "OS / Arch" tab rendering)
    - Cosign keyless OIDC signing by digest (requires `id-token: write`)
  - `ci-pass`: aggregator gate.
- All tools (Node, pnpm, hadolint, kubectl, kind, yq, Trivy, gitleaks, act, **renovate**) come from `.mise.toml` via `jdx/mise-action`. ZAP_VERSION pinned in Makefile + duplicated in workflow `env:` block (no shared source).
- **cleanup-runs.yml**: Weekly cleanup of old workflow runs (`make cleanup-runs`) + caches from merged branches.
- **cleanup-images.yml**: Weekly cleanup of untagged GHCR images (`make cleanup-images`).
- All GitHub Actions pinned to commit SHAs. Renovate manages dependency updates with platform automerge enabled (major updates delayed 3 days).

## Image Publishing & Hardening

The `docker` job in `ci.yml` ships images on tag pushes. See README "Pre-push image hardening" for the user-facing gate table and `cosign verify` command. To re-harden / extend, run `/harden-image-pipeline`.

`make ci-run-tag` exercises the `docker` job locally under act (synthetic tag-push event); cosign signing fails under act (no OIDC) — expected.

## Docker

- **Dockerfile**: Dev image (Node alpine + pnpm dev server on port 8080); `corepack enable pnpm` (no `npm install -g`)
- **Dockerfile.prod**: Multi-stage build (`node:24.15.0-alpine` builder → `nginxinc/nginx-unprivileged:1.29.8-alpine` on port 8080, `USER 101`); OCI labels (artifacthub, vendor, license) baked in via `LABEL` instructions; both stages pin base images by SHA256 digest
- **`packageManager` field** in `package.json` pins `pnpm@10.33.0` so corepack uses the project-declared version
- **`.dockerignore`**: Excludes `node_modules`, `dist`, `.git`, `e2e`, `zap-output`, `playwright-report`, `test-results`, `.env`
- **`.hadolint.yaml`**: Configures hadolint rule ignores for Dockerfile linting
- **`nginx/nginx.conf`**: `server_tokens off;` (no version leak), `default_type` on probe routes (preserves security-header inheritance), `location /assets/ { try_files $uri =404; }` (missing assets 404 instead of SPA fallback)
- Both Dockerfiles use `pnpm install --frozen-lockfile` and copy lockfiles before source for layer caching

## Conventions

- Package manager: **pnpm only** (no `npm`, no `npx` — Makefile uses `pnpm dlx`; Dockerfiles use `corepack enable pnpm`; `packageManager` field in package.json)
- Tool versioning: **mise** via `.mise.toml` (single source of truth across local + CI). Includes `npm:renovate`, `aqua:` pins for kubectl/kind/yq/hadolint/act/trivy/gitleaks. Docker-image tools (`MERMAID_CLI_VERSION`, `ZAP_VERSION`, `KIND_NODE_IMAGE`) stay as Makefile constants (Renovate-tracked) since mise can't manage Docker images directly.
- Node.js: pinned in `.mise.toml` (currently `node = "24"`); `.node-version` retained as a fallback marker
- TypeScript: **6.x** with `moduleResolution: "bundler"` (no `baseUrl`, no `esModuleInterop`)
- Formatting: **prettier** only (no eslint)
- Static analysis: **prettier + hadolint + Trivy fs + Trivy config + gitleaks + mermaid-lint**, composed in `make static-check`
- Commit messages: conventional commits (`feat:`, `fix:`, `chore:`, `ci:`, `refactor:`, `docs:`, `perf:`)
- Release: `make release` validates semver format (`vN.N.N`), writes `version.txt`, commits and pushes the tag
- State management: **Redux Toolkit** with `createSlice` pattern (migrated from Rematch)

## Upgrade Backlog

Last reviewed: 2026-04-19 (post `/upgrade-analysis` Wave 1+2+3 applied). Review on next pass — resolve actionable items, remove stale ones.

- [x] ~~**Remove stale `.eslintrc.js`**~~ — deleted (2026-04-03)
- [x] ~~**Remove dead `src/service/_api/` and `src/utils/util.ts`**~~ — deleted (2026-04-04)
- [x] ~~**Remove unused deps `axios`, `i18next-http-backend`, `pretty-quick`**~~ — removed (2026-04-04)
- [x] ~~**Migrate from nvm + per-tool curl installers to mise**~~ — done (2026-04-19), `.mise.toml` is now the source of truth
- [x] ~~**Add composite `static-check` Makefile target**~~ — done (2026-04-19), includes Trivy fs/config + gitleaks + mermaid-lint
- [x] ~~**CI: switch to `jdx/mise-action` and `make static-check`**~~ — done (2026-04-19)
- [x] ~~**CI: add `ci-pass` aggregator job**~~ — done (2026-04-19)
- [x] ~~**Isolate `ether.integration.test.ts` from `make test`**~~ — done (2026-04-19), `vitest.integration.config.ts` + `make integration-test` + dedicated CI job; default `make test` excludes `**/*.integration.test.*`
- [x] ~~**Add `make e2e` target**~~ — done (2026-04-19), KinD + `cloud-provider-kind` (LoadBalancer with real IPs on the kind Docker network — portfolio default) + `e2e/e2e-test.sh` (curl) + `e2e/account-form.spec.ts` (Playwright); CI `e2e` + `dast` jobs gated `if: vars.ACT != 'true'`
- [x] ~~**Harden image publish pipeline**~~ — done (2026-04-19), Pattern A: build-for-scan (load:true) → Trivy image scan (CRITICAL/HIGH blocking) → smoke test → multi-arch push → cosign keyless OIDC signing by digest. Separate `dast` job (OWASP ZAP baseline) parallel with `docker`. `provenance: false` + `sbom: false` keep GHCR "OS / Arch" tab rendering.
- [x] ~~**Dockerfile: migrate from `npm install -g pnpm` to corepack**~~ — done (2026-04-19), both Dockerfiles use `corepack enable pnpm`; `packageManager` field in package.json declares `pnpm@10.33.0`
- [x] ~~**Wave 4: ethers.js → viem migration**~~ — done (2026-04-19). Replaced `ethers.JsonRpcProvider`/`ethers.Contract` with viem's `createPublicClient` + `readContract` (mainnet chain, http transport). DAI ENS lookup (`dai.tokens.ethers.eth`) replaced by hardcoded canonical address `0x6B17…1d0F`. Service API now returns typed result objects instead of mutating module-level `let` exports — eliminates the `Promise.all([assignment-side-effect])` pattern. AccountForm reads from returned values. Tests rewritten: unit mocks `createPublicClient`, integration uses real RPC, AccountForm component test mocks the full module surface. vite.config.ts vendor chunk renamed `vendor-ethers` → `vendor-viem` (~253 KB, comparable size).
- [ ] **Wave 4: MUI v7 → v9** — `@mui/material` and `@mui/icons-material` are two majors behind (7.3.9 → 9.0.0). Stepwise: v7 → v8 (theme overhaul, `Grid` → `Grid2`), then v8 → v9 (layout breaking changes). Files affected: `src/components/AccountForm.tsx`, `src/components/Layout.tsx`, `src/theme.tsx`. Effort: 1–2 days incl. visual regression checks.
- [x] ~~**K8s deployment: enable resource requests/limits**~~ — done (2026-04-19), conservative defaults (cpu 10m/200m, mem 32Mi/64Mi) + per-init `5m/100m` and `16Mi/32Mi`.
- [x] ~~**K8s deployment: add securityContext**~~ — done (2026-04-19), pod-level `runAsNonRoot:true, runAsUser:101, runAsGroup:101, fsGroup:101, seccompProfile:RuntimeDefault`; container-level `readOnlyRootFilesystem:true, allowPrivilegeEscalation:false, capabilities.drop:[ALL]`. Init container `seed-html` copies baked HTML to a writable emptyDir so `start-nginx.sh`'s envsubst can rewrite the bundled JS at startup. `.trivyignore` cleared.

### Open (post-`/upgrade-analysis` deferred items)

- [ ] **`vite.config.ts` hardcodes `server.port: 8080`** — fine for dev (matches container/k8s/nginx), but PORT env var doesn't propagate there. Low priority; `.env.example` documents the coupling.
- [ ] **e2e lazy-chunk regex (`assert_any_chunk_contains` in `e2e/e2e-test.sh`) is project-specific** — relies on the well-known prefix list `index|about|vendor-…|i18next|rolldown-runtime`. If a refactor introduces a new chunk basename (e.g. via Vite plugin reshuffle), the env-injection assertion silently misses it. Consider a more permissive enumeration (e.g. probe every `/assets/*.js` referenced anywhere transitively) when this becomes a problem.
- [ ] **No SBOM published with the image** — Pattern A intentionally disables `sbom: true` to keep the GHCR "OS / Arch" tab rendering. If a downstream consumer needs an SPDX SBOM (e.g. `cosign download attestation --predicate-type https://spdx.dev/Document`), opt into Pattern B and accept the GHCR UI regression.
- [ ] **Architecture diagram tech-strings will drift on every framework bump** — README has 3 Mermaid blocks (C4Context, sequenceDiagram, C4Deployment) that name framework versions (`"React 19.2"`, `"TypeScript 6"`, `"Vite 8"`, `"ethers.js 6.16"`, `"nginx-unprivileged 1.29.8 on :8080"`, `"kindest/node v1.35.1"`). Renovate cannot update these strings. Re-run `/architecture-diagrams` after Wave 4 lands (or any later major bump).

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
