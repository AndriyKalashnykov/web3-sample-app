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
make e2e            # KinD + cloud-provider-kind LB + curl assertions (e2e/e2e-test.sh); CI e2e job also runs make e2e-browser
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
make cleanup-caches # delete GHA caches from merged or deleted branches (called by cleanup-runs.yml)
make cleanup-images # delete untagged GHCR images, keep 5 (called by cleanup-images.yml)
```

## Tool Versions (mise)

`.mise.toml` is the single source of truth for every pinned tool: Node.js, pnpm, hadolint, kubectl, kind, yq, Trivy, gitleaks, act, and `npm:renovate`. `make deps` bootstraps mise via `https://mise.run` (installs to `~/.local/bin`, no sudo) and then runs `mise install` to provision the rest. CI uses `jdx/mise-action` so local and CI read the same `.mise.toml`. Renovate tracks updates via the native `mise` manager.

Three Docker-image versions stay pinned as Makefile constants (with `# renovate:` annotations) because mise can't manage Docker images: `MERMAID_CLI_VERSION` (mermaid lint), `ZAP_VERSION` (DAST), `CLOUD_PROVIDER_KIND_VERSION` (KinD LoadBalancer controller). `KIND_NODE_IMAGE` is also a Makefile constant but is bumped together with the `aqua:kubernetes-sigs/kind` mise pin (see KinD release notes for matched node image — not independently trackable).

## Testing

Four-layer test pyramid. Each layer has its own Makefile target, vitest/Playwright config, and CI job:

| Layer | Target | Config | Files | Speed | What it covers |
|-------|--------|--------|-------|-------|----------------|
| Unit + Component | `make test` | `vitest.config.ts` (excludes `**/*.integration.test.*`) | `src/store/models/__tests__/`, `src/service/ether/__tests__/ether.test.ts`, `src/components/__tests__/` | ~1s | Pure functions, Redux slices, mocked ether service, components rendered via `renderWithProviders` |
| Integration | `make integration-test` | `vitest.integration.config.ts` (`include: ['**/*.integration.test.ts']`, 30s timeout, node env) | `src/service/ether/__tests__/ether.integration.test.ts` | ~5s | Ether service against the real `VITE_RPCENDPOINT` (block fetch, ETH/DAI balance, malformed-input negative paths) |
| E2E (curl) | `make e2e` | `e2e/e2e-test.sh` | KinD + cloud-provider-kind LoadBalancer (kind Docker network IP) | ~30s | nginx routes (`/internal/isalive`, `/internal/isready`, `/publicnode` → 307, SPA fallback, missing asset 404) + verifies `start-nginx.sh` substituted `VITE_RPCENDPOINT` into `/config.js` (also runs `make e2e-browser` in CI — Playwright Chromium against deployed SPA, asserts real RPC roundtrip updates block counter) |
| E2E (browser) | `make e2e-browser` | `e2e/playwright.config.ts` + `e2e/account-form.spec.ts` | KinD + cloud-provider-kind + Playwright Chromium | ~45s | AccountForm renders, real RPC roundtrip updates the displayed block number |

Notes:
- `make test` and `make integration-test` are independent — the `test` job runs unit + component (no network), `integration-test` job runs the real-RPC suite (needs outbound HTTPS).
- `e2e` and `dast` are gated `if: vars.ACT != 'true'` in CI because KinD-in-Docker inside act isn't reliable. Run them locally.
- The CI `e2e` job runs both `make e2e` (curl) AND `make e2e-browser` (Playwright Chromium against the deployed SPA) — Playwright is the only layer that catches CSP violations and runtime SPA bugs.
- The ether unit tests mock viem's `createPublicClient`; component tests mock the `@/service/ether` module entirely.

## Architecture

This is a React SPA that queries Ethereum blockchain balances (ETH and DAI) via viem 2. There is no backend — all blockchain calls happen in the browser against an external JSON-RPC endpoint configured via `VITE_RPCENDPOINT`.

### Entry Flow

`src/main.tsx` → mounts `<App>` wrapped in MUI `ThemeProvider` + Redux `Provider`

`src/App.tsx` → renders `Header`/`Footer` layout with `react-router-dom` `BrowserRouter`. Routes defined in `src/router/index.ts` map paths to page components, lazy-loaded with `React.lazy()` + `<Suspense>`.

### Key Layers

- **Pages** (`src/pages/`): Route-level components (`index/` = home, `about/`)
- **Components** (`src/components/`): `AccountForm` (blockchain query UI), `Counter` (Redux demo), `Layout` (Header/Footer with MUI drawer nav), `Logo`
- **Ethereum service** (`src/service/ether/ether.ts`): Uses viem's `createPublicClient` (mainnet, http transport) to query ETH balances and DAI token contract reads. Exposes `getETHBalance(addr)` and `getDAIBalance(addr)` returning typed result objects (`{block, balance}` / `{block, name, symbol, balance, balanceFormatted}`). RPC endpoint comes from `config.VITE_RPCENDPOINT` (resolved at module load via `src/config.ts` — see "Runtime env-var injection" below). DAI contract address hardcoded to canonical mainnet `0x6B17…1d0F` (no ENS lookup). Re-exports `formatEther`, `formatUnits`, `getAddress` so the component layer doesn't import viem directly.
- **Runtime config** (`src/config.ts`): Single source of truth for env-derived runtime values. Reads `window.__CONFIG__` first (set by `<script src="/config.js">` in `index.html`; in production `/config.js` is generated per-container-start by `start-nginx.sh`'s envsubst pass over `config.js.template`), falls through to `import.meta.env` when the placeholder is still literal (i.e. `pnpm dev` or test). Both `ether.ts` and `AccountForm.tsx` consume the typed `config` object — no other module reads `import.meta.env.VITE_*` directly. **External file, not inline**: nginx CSP is `script-src 'self'`, which forbids inline scripts without a per-deploy nonce/hash; `/config.js` under `/` is allowed by `'self'` without weakening CSP.
- **State** (`src/store/`): Redux Toolkit with slices for `counter` (`counterSlice.ts`) and `common` (`commonSlice.ts`). Uses `configureStore`, `createSlice`, and typed hooks (`useAppDispatch`, `useAppSelector`).
- **i18n** (`src/locale.ts`): i18next with `react-i18next`, static English translations from `src/locales/en.json`

### Runtime env-var injection (Pattern C)

`Dockerfile.prod` is environment-agnostic — `public/config.js` contains `window.__CONFIG__ = { VITE_RPCENDPOINT: "${VITE_RPCENDPOINT}", VITE_BASE_URL: "${VITE_BASE_URL}" }` with literal placeholders. Vite copies it to `dist/config.js` as-is at build time; `Dockerfile.prod` renames it to `dist/config.js.template`. At container startup, `start-nginx.sh` runs `envsubst` against that single template (variables restricted to `$VITE_RPCENDPOINT $VITE_BASE_URL`) and writes the result to `/usr/share/nginx/html/config.js`. `index.html` loads it via `<script src="/config.js"></script>` (external — not inline — so strict CSP `script-src 'self'` applies without a per-deploy nonce/hash). The SPA reads `window.__CONFIG__` via `src/config.ts`. Bundled JS AND `index.html` are byte-identical across deployments — only `/config.js` changes per env. K8s `ConfigMap` in `k8s/cm.yaml` provides values in-cluster. nginx serves `/config.js` with `Cache-Control: no-store` so deploys pick up new values immediately.

### Path Alias

`@/` maps to `src/` — configured in both `tsconfig.json` (`paths`) and `vite.config.ts` (`resolve.alias`).

### Styling

Tailwind CSS v4 with `@tailwindcss/postcss`. Custom colors (`primary`, `secondary`) in `tailwind.config.js`. CSS files using `@apply` outside the main entry need `@reference "tailwindcss"` directive (see `src/App.css`). MUI v9 theme in `src/theme.tsx`.

### Build

Vite (oxc minifier, not terser). Console and debugger statements are stripped in production via `build.oxc.compress` in `vite.config.ts`. Vendor chunks are split via `rolldownOptions.output.manualChunks` (function, not object — Rolldown requirement) into `vendor-react`, `vendor-mui`, and `vendor-viem` (covers `viem`, `@noble/*`, `@scure/*`, `abitype`, `isows`, `ws`). See `package.json` for current framework versions.

## CI/CD

- **ci.yml** job DAG: `changes` → `static-check` → (`test`, `integration-test`, `build` parallel) → (`e2e`, `dast`, `docker` parallel) → `ci-pass` (aggregator).
  - `changes`: job-level path filter via `dorny/paths-filter`. Doc-only diffs (`**.md` outside `CLAUDE.md`, `docs/**`, `LICENSE`, `**.png`, etc.) set `outputs.code = false` → every heavy job short-circuits via `if: needs.changes.outputs.code == 'true'`. Tag pushes force `code = true` to avoid the empty-diff escape hatch. The workflow itself always runs so `ci-pass` always reports a status — Repository-Rulesets-safe.
  - `static-check`: composite of lint + vulncheck + trivy-fs + trivy-config + secrets + mermaid-lint + deps-prune-check via `make static-check`.
  - `integration-test`: real-RPC vitest suite (`make integration-test`).
  - `e2e`: KinD + `cloud-provider-kind` (real LoadBalancer Service IPs on the kind Docker network) + `make e2e` (curl) + `make e2e-browser` (Playwright Chromium). Gated `if: vars.ACT != 'true'`.
  - `dast`: parallel with `docker`/`e2e`. Builds `:scan` image via shared cache, boots it, runs OWASP ZAP baseline (`-I`, FAIL-only blocking). Cached ZAP image (~3.4GB). Gated `if: vars.ACT != 'true'`. Uploads HTML/JSON/MD report.
  - `docker`: Pattern A. Validation gates (Trivy image scan, smoke test, multi-arch build) run on **every push**; publish + cosign sign-by-digest are step-level gated to tag pushes only — catches multi-arch / signing regressions before tag day instead of on it.
    - Gate 1: Build for scan (`load: true`, linux/amd64) into local docker daemon
    - Gate 2: Trivy image scan (`CRITICAL,HIGH` blocking, `vuln,secret,misconfig` scanners)
    - Gate 3: Smoke test (`docker run` + `curl /internal/isalive`)
    - Build (push: ${{ tag }}): multi-arch (`linux/amd64,linux/arm64`), `provenance: false` + `sbom: false` (keeps GHCR "OS / Arch" tab rendering)
    - Cosign keyless OIDC signing by digest on tag push (requires `id-token: write`)
  - `ci-pass`: aggregator gate. Fails if any upstream job failed OR was cancelled.
- All tools (Node, pnpm, hadolint, kubectl, kind, yq, Trivy, gitleaks, act, **renovate**) come from `.mise.toml` via `jdx/mise-action`. `cloud-provider-kind` runs as a Docker container pinned via `CLOUD_PROVIDER_KIND_VERSION` Makefile constant. `ZAP_VERSION` is duplicated between Makefile and workflow `env:` block; both annotations are tracked by Renovate's workflow custom-regex manager so they bump in lockstep.
- **cleanup-runs.yml**: Weekly cleanup — `make cleanup-runs` (workflow runs > 7d) + `make cleanup-caches` (caches from merged or deleted branches).
- **cleanup-images.yml**: Weekly cleanup of untagged GHCR images (`make cleanup-images`).
- All GitHub Actions pinned to commit SHAs. Renovate manages dependency updates with platform automerge enabled (major updates delayed 3 days).

## Image Publishing & Hardening

The `docker` job in `ci.yml` ships images on tag pushes; on non-tag pushes it runs the same Trivy + smoke + multi-arch validation build with `push: false`. See README "Pre-push image hardening" for the user-facing gate table and `cosign verify` command. To re-harden / extend, run `/harden-image-pipeline`.

`make ci-run-tag` exercises the `docker` job locally under act (synthetic tag-push event); cosign signing fails under act (no OIDC) — expected.

## Docker

- **Dockerfile**: Dev image (Node alpine + pnpm dev server on port 8080); `corepack enable pnpm` (no `npm install -g`). See `Dockerfile` for the pinned base image digest.
- **Dockerfile.prod**: Multi-stage build (Node alpine builder → `nginxinc/nginx-unprivileged` on port 8080, `USER 101`); OCI labels (artifacthub, vendor, license) baked in via `LABEL` instructions; both stages pin base images by SHA256 digest. See `Dockerfile.prod` for the pinned tags.
- **`packageManager` field** in `package.json` pins pnpm so corepack uses the project-declared version.
- **`.dockerignore`**: Excludes `node_modules`, `dist`, `.git`, `e2e`, `zap-output`, `playwright-report`, `test-results`, `.env`.
- **`.hadolint.yaml`**: Configures hadolint rule ignores for Dockerfile linting.
- **`nginx/nginx.conf`**: `server_tokens off;` (no version leak), `default_type` on probe routes (preserves security-header inheritance), `location /assets/ { try_files $uri =404; }` (missing assets 404 instead of SPA fallback).
- Both Dockerfiles use `pnpm install --frozen-lockfile` and copy lockfiles before source for layer caching.

## Conventions

- Package manager: **pnpm only** (no `npm`, no `npx` — Makefile uses `pnpm dlx`; Dockerfiles use `corepack enable pnpm`; `packageManager` field in package.json).
- Tool versioning: **mise** via `.mise.toml` (single source of truth across local + CI). Includes `npm:renovate`, `aqua:` pins for kubectl/kind/yq/hadolint/act/trivy/gitleaks. Docker-image tools (`MERMAID_CLI_VERSION`, `ZAP_VERSION`, `CLOUD_PROVIDER_KIND_VERSION`) stay as Makefile constants (Renovate-tracked) since mise can't manage Docker images directly. `KIND_NODE_IMAGE` is also a Makefile constant but bumped together with `aqua:kubernetes-sigs/kind` per KinD release notes.
- Multi-session safety: `KIND_CLUSTER_NAME := $(APP_NAME)` and every `kubectl` invocation goes through `KUBECTL := kubectl --context=kind-$(KIND_CLUSTER_NAME)` so a parallel `make` from a sibling KinD project can't silently steer recipes to the wrong cluster.
- Node.js: pinned in `.mise.toml` (currently `node = "24"`); `.node-version` retained as a fallback marker.
- TypeScript: **6.x** with `moduleResolution: "bundler"` (no `baseUrl`, no `esModuleInterop`).
- Formatting: **prettier** only (no eslint).
- Static analysis: **prettier + hadolint + Trivy fs + Trivy config + gitleaks + mermaid-lint**, composed in `make static-check`.
- Commit messages: conventional commits (`feat:`, `fix:`, `chore:`, `ci:`, `refactor:`, `docs:`, `perf:`).
- Release: `make release` validates semver format (`vN.N.N`), writes `version.txt`, commits and pushes the tag.
- State management: **Redux Toolkit** with `createSlice` pattern (migrated from Rematch).

## Upgrade Backlog

Last reviewed: 2026-05-07 (post `/project-review` apply — kubectl context safety, kindccm pruning, cloud-provider-kind via Docker, Rulesets-safe `changes` job, Pattern A on-every-push validation, Renovate dedupe).

- [ ] **`vite.config.ts` hardcodes `server.port: 8080`** — fine for dev (matches container/k8s/nginx), but PORT env var doesn't propagate there. Low priority; `.env.example` documents the coupling.
- [ ] **No SBOM published with the image** — Pattern A intentionally disables `sbom: true` to keep the GHCR "OS / Arch" tab rendering. If a downstream consumer needs an SPDX SBOM (e.g. `cosign download attestation --predicate-type https://spdx.dev/Document`), opt into Pattern B and accept the GHCR UI regression.
- [ ] **Architecture diagram tech-strings drift** — README's C4 diagrams hardcode framework version strings (e.g. `"React 19 SPA, viem 2"`). Renovate cannot update these. Re-run `/architecture-diagrams` after any major bump.

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
