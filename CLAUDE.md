# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Dev Commands

All commands go through the Makefile. Use `make help` to list targets.

```bash
make deps           # install mise + all pinned tools (node, pnpm, hadolint, kubectl, kind, yq, trivy, gitleaks, act, container-structure-test)
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
make container-structure-test # validate prod image structure (USER, entrypoint, labels, files, caddy version)
make secrets        # gitleaks over git history
make mermaid-lint   # validate ```mermaid blocks via minlag/mermaid-cli
make diagrams       # render docs/diagrams/*.puml C4 sources to PNG via pinned plantuml/plantuml
make diagrams-check # drift gate: re-render + git diff (fails if committed PNGs are stale vs .puml)
make static-check   # composite gate: check-node-alignment + lint + vulncheck + trivy-fs + trivy-config + secrets + mermaid-lint + diagrams-check + deps-prune-check
make check          # static-check + test + build (full local pipeline)
make ci             # CI pipeline: install + static-check + test + integration-test + build
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

`.mise.toml` is the single source of truth for every pinned tool: Node.js, pnpm, hadolint, kubectl, kind, yq, Trivy, gitleaks, act, container-structure-test. `make deps` bootstraps mise via `https://mise.run` (installs to `~/.local/bin`, no sudo) and then runs `mise install` to provision the rest. CI uses `jdx/mise-action` so local and CI read the same `.mise.toml`. Renovate tracks updates via the native `mise` manager.

The Renovate CLI itself is deliberately **not** in `.mise.toml` — it is pinned as the `RENOVATE_VERSION` Makefile constant (`# renovate: datasource=npm depName=renovate`) and fetched on demand by `make renovate-validate` via `mise exec`, so `mise install` does not eagerly reinstall renovate's ~600-package npm tree on every `make deps`. Its near-daily self-bump is throttled to weekly in `renovate.json` (`matchDepNames:["renovate"]`).

Four Docker-image versions stay pinned as Makefile constants (with `# renovate:` annotations) because mise can't manage Docker images: `MERMAID_CLI_VERSION` (mermaid lint), `ZAP_VERSION` (DAST), `CLOUD_PROVIDER_KIND_VERSION` (KinD LoadBalancer controller), `PLANTUML_VERSION` (C4 diagram render). `KIND_NODE_IMAGE` is also a Makefile constant but is bumped together with the `aqua:kubernetes-sigs/kind` mise pin (see KinD release notes for matched node image — not independently trackable).

## Testing

Four-layer test pyramid. Each layer has its own Makefile target, vitest/Playwright config, and CI job:

| Layer | Target | Config | Files | Speed | What it covers |
|-------|--------|--------|-------|-------|----------------|
| Unit + Component | `make test` | `vitest.config.ts` (excludes `**/*.integration.test.*`) | `src/store/models/__tests__/`, `src/service/ether/__tests__/ether.test.ts`, `src/components/__tests__/` | ~1s | Pure functions, Redux slices, mocked ether service, components rendered via `renderWithProviders` |
| Integration | `make integration-test` | `vitest.integration.config.ts` (`include: ['**/*.integration.test.ts']`, 30s timeout, node env) | `src/service/ether/__tests__/ether.integration.test.ts` | ~5s | Ether service against the real `VITE_RPCENDPOINT` (block fetch, ETH/DAI balance, malformed-input negative paths) |
| E2E (curl) | `make e2e` | `e2e/e2e-test.sh` | KinD + cloud-provider-kind LoadBalancer (kind Docker network IP) | ~30s | Caddy routes (`/internal/isalive`, `/internal/isready`, `/publicnode` → 307, SPA fallback, missing asset 404) + verifies `start-caddy.sh` substituted `VITE_RPCENDPOINT` into `/config.js` (also runs `make e2e-browser` in CI — Playwright Chromium against deployed SPA, asserts real RPC roundtrip updates block counter) |
| E2E (browser) | `make e2e-browser` | `e2e/playwright.config.ts` + `e2e/account-form.spec.ts` | KinD + cloud-provider-kind + Playwright Chromium | ~45s | AccountForm renders; real ETH + DAI RPC roundtrips update the block counter AND render a well-formed numeric balance; an `@axe-core/playwright` scan asserts no critical/serious WCAG2A/AA a11y violations |

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
- **Runtime config** (`src/config.ts`): Single source of truth for env-derived runtime values. Reads `window.__CONFIG__` first (set by `<script src="/config.js">` in `index.html`; in production `/config.js` is generated per-container-start by `start-caddy.sh`'s envsubst pass over `config.js.template`), falls through to `import.meta.env` when the placeholder is still literal (i.e. `pnpm dev` or test). Both `ether.ts` and `AccountForm.tsx` consume the typed `config` object — no other module reads `import.meta.env.VITE_*` directly. **External file, not inline**: the Caddy CSP is `script-src 'self'`, which forbids inline scripts without a per-deploy nonce/hash; `/config.js` under `/` is allowed by `'self'` without weakening CSP.
- **State** (`src/store/`): Redux Toolkit with slices for `counter` (`counterSlice.ts`) and `common` (`commonSlice.ts`). Uses `configureStore`, `createSlice`, and typed hooks (`useAppDispatch`, `useAppSelector`).
- **i18n** (`src/locale.ts`): i18next with `react-i18next`, static English translations from `src/locales/en.json`

### Runtime env-var injection (Pattern C)

`Dockerfile.prod` is environment-agnostic — `public/config.js` contains `window.__CONFIG__ = { VITE_RPCENDPOINT: "${VITE_RPCENDPOINT}", VITE_BASE_URL: "${VITE_BASE_URL}" }` with literal placeholders. Vite copies it to `dist/config.js` as-is at build time; `Dockerfile.prod` renames it to `dist/config.js.template`. At container startup, `start-caddy.sh` runs `envsubst` against that single template (variables restricted to `$VITE_RPCENDPOINT $VITE_BASE_URL`) and writes the result to `/srv/config.js`. `index.html` loads it via `<script src="/config.js"></script>` (external — not inline — so strict CSP `script-src 'self'` applies without a per-deploy nonce/hash). The SPA reads `window.__CONFIG__` via `src/config.ts`. Bundled JS AND `index.html` are byte-identical across deployments — only `/config.js` changes per env. K8s `ConfigMap` in `k8s/cm.yaml` provides values in-cluster. Caddy serves `/config.js` with `Cache-Control: no-store` so deploys pick up new values immediately.

### Path Alias

`@/` maps to `src/` — configured in both `tsconfig.json` (`paths`) and `vite.config.ts` (`resolve.alias`).

### Styling

Tailwind CSS v4 with `@tailwindcss/postcss`. Custom colors (`primary`, `secondary`) in `tailwind.config.js`. CSS files using `@apply` outside the main entry need `@reference "tailwindcss"` directive (see `src/App.css`). MUI v9 theme in `src/theme.tsx`.

### Build

Vite (oxc minifier, not terser). Console and debugger statements are stripped in production via `build.oxc.compress` in `vite.config.ts`. Vendor chunks are split via `rolldownOptions.output.manualChunks` (function, not object — Rolldown requirement) into `vendor-react`, `vendor-mui`, and `vendor-viem` (covers `viem`, `@noble/*`, `@scure/*`, `abitype`, `isows`, `ws`). See `package.json` for current framework versions.

## CI/CD

- **ci.yml** job DAG: `changes` → `static-check` → (`test`, `integration-test`, `build` parallel) → (`e2e`, `dast`, `docker` parallel) → `ci-pass` (aggregator). A lightweight `mermaid-lint` job also runs off `changes` for **docs-only** changes — README mermaid blocks are docs-excluded from `code`, so `static-check`'s mermaid-lint never sees them; on code changes `static-check` covers mermaid instead, so the job is gated `docs == 'true' && code != 'true'`.
  - `changes`: job-level path filter via `dorny/paths-filter`. Doc-only diffs (`**.md` outside `CLAUDE.md`, `docs/**`, `specs/**`, `benchmarks/**`, `LICENSE`, `**.png`, etc.) set `outputs.code = false` → every heavy job short-circuits via `if: needs.changes.outputs.code == 'true'`. `docs/diagrams/**/*.puml` is re-included as `code` so a diagram-source edit runs `static-check`→`diagrams-check` (else a stale-PNG commit could merge under the docs gate). A second `outputs.docs` (any `**.md`) gates the `mermaid-lint` job. Tag pushes force `code = true` to avoid the empty-diff escape hatch. The workflow itself always runs so `ci-pass` always reports a status — Repository-Rulesets-safe.
  - `static-check`: composite of check-node-alignment + lint + vulncheck + trivy-fs + trivy-config + secrets + mermaid-lint + diagrams-check + deps-prune-check via `make static-check`.
  - `integration-test`: real-RPC vitest suite (`make integration-test`).
  - `e2e`: KinD + `cloud-provider-kind` (real LoadBalancer Service IPs on the kind Docker network) + `make e2e` (curl) + `make e2e-browser` (Playwright Chromium). Gated `if: vars.ACT != 'true'`.
  - `dast`: **tag-push only** (mirrors `docker` — `startsWith(github.ref, 'refs/tags/')`). Builds `:scan` image via shared cache, boots it, runs OWASP ZAP baseline (`-I`, FAIL-only blocking) at release. Cached ZAP image (~3.4GB). Also gated `if: vars.ACT != 'true'`. Uploads HTML/JSON/MD report. (Moved off every-push to keep ordinary commits cheap; the image is scanned for CVEs by `docker`'s Trivy gate at the same release.)
  - `docker`: **tag-push only** (job-level `if: … && startsWith(github.ref, 'refs/tags/')`). Build, Trivy image scan, container-structure-test, SBOM, smoke test, publish, and cosign sign-by-digest all run **only on release tags** (`make release` cuts a `vN.N.N` tag) — no image is built/scanned on ordinary commits. The Dockerfile is still compiled on every push by the `e2e` job (KinD deploy builds the prod image), so a broken Dockerfile is caught pre-tag there; only the image scan / structure-test / SBOM / publish are tag-gated.
    - Gate 1: Build for scan (`load: true`, linux/amd64) into local docker daemon
    - Gate 2: Trivy image scan (`CRITICAL,HIGH` blocking, `vuln,secret,misconfig` scanners)
    - Gate 2.5: container-structure-test (`make container-structure-test-only CST_IMAGE=web3-sample-app:scan` — reuses the scan image; single-sources the command + `container-structure-test.yaml` config; USER 1000, entrypoint, OCI labels, runtime files, CVE-patched caddy version)
    - Gate 2.7: SPDX SBOM via Trivy → uploaded as the `sbom-spdx` artifact (and cosign-attested by digest on tag push). Kept out of the buildx manifest (`sbom: false`) so the GHCR "OS / Arch" tab still renders
    - Gate 3: Smoke test (`docker run` + `curl /internal/isalive`)
    - Build + push (`push: true` — the job only runs on tags): single-arch (`linux/amd64`; arm64 dropped to keep CI fast), `provenance: false` + `sbom: false` (keeps GHCR "OS / Arch" tab rendering)
    - Cosign keyless OIDC signing by digest on tag push + SPDX SBOM attestation (requires `id-token: write`)
  - `ci-pass`: aggregator gate. Fails if any upstream job failed OR was cancelled.
- All tools (Node, pnpm, hadolint, kubectl, kind, yq, Trivy, gitleaks, act) come from `.mise.toml` via `jdx/mise-action`. (The Renovate CLI is the `RENOVATE_VERSION` Makefile pin, fetched lazily via `mise exec` — see Tool Versions.) `cloud-provider-kind` runs as a Docker container pinned via `CLOUD_PROVIDER_KIND_VERSION` Makefile constant. `ZAP_VERSION` is duplicated between Makefile and workflow `env:` block; both annotations are tracked by Renovate's workflow custom-regex manager so they bump in lockstep.
- **cleanup-runs.yml**: Weekly cleanup — `make cleanup-runs` (workflow runs > 7d) + `make cleanup-caches` (caches from merged or deleted branches).
- **cleanup-images.yml**: Weekly cleanup of untagged GHCR images (`make cleanup-images`).
- All GitHub Actions pinned to commit SHAs. Renovate manages dependency updates with PR automerge on green CI (`platformAutomerge: false` — race-safe for the required `ci-pass` check; major updates delayed 3 days).

## Image Publishing & Hardening

The `docker` job in `ci.yml` builds, scans, and ships images **on tag pushes only** (the whole job is gated `startsWith(github.ref, 'refs/tags/')`). See README "Release image hardening" for the user-facing gate table and `cosign verify` command. To re-harden / extend, run `/harden-image-pipeline`.

`make ci-run-tag` exercises the `docker` job locally under act (synthetic tag-push event); cosign signing fails under act (no OIDC) — expected.

## Docker

- **Dockerfile**: Dev image (Node alpine + pnpm dev server on port 8080); `corepack enable pnpm` (no `npm install -g`). See `Dockerfile` for the pinned base image digest.
- **Dockerfile.prod**: Three-stage build — (1) `node:24-alpine` builder produces the Vite bundle; (2) `caddy:2.11.4-builder-alpine` runs `xcaddy build v2.11.4` with `GOTOOLCHAIN=go1.26.4` to rebuild Caddy's stdlib past the Go MIME-header DoS (CVE-2026-42504; the vanilla `caddy:2.11.4-alpine` binary ships Go 1.26.3, still vulnerable — verified via `trivy image`). Caddy 2.11.4 already pins go-jose/v3 v3.0.5, so the earlier `--replace` workaround for CVE-2026-34986 is retired; (3) `caddy:2.11.4-alpine` runtime, with the rebuilt binary copied in over the bundled one, `gettext` added for `start-caddy.sh`'s envsubst pass, `cap_net_bind_service` stripped from `/usr/bin/caddy` (so the binary execs cleanly under K8s `capabilities.drop:[ALL]`), non-root `USER ${APP_UID}:${APP_GID}` (default `1000:1000`, build-arg overridable). The listen port is single-sourced through `ARG APP_INTERNAL_PORT=8080` → `ENV PORT` → Caddyfile `:{$PORT:8080}` → `EXPOSE`, so the K8s ConfigMap `PORT` actually drives the listen port. A `HEALTHCHECK` probes `/internal/isalive` via busybox `wget` (literal flag timings, `${HEALTHCHECK_HOST}:${PORT}` CMD body). All three stages pin base images by SHA256 digest. OCI labels (artifacthub, vendor, license) on the runtime stage. See `Dockerfile.prod` for the pinned tags.
- **`packageManager` field** in `package.json` pins pnpm so corepack uses the project-declared version.
- **`.dockerignore`**: Excludes `node_modules`, `dist`, `.git`, `e2e`, `zap-output`, `playwright-report`, `test-results`, `.env`.
- **`.env.example`**: Committed source of truth for operator-tunable values (`VITE_RPCENDPOINT`, `APP_INTERNAL_PORT`, e2e/Make timeouts). Copy to gitignored `.env` to override locally; shell scripts source it, the Makefile mirrors it as `?=` defaults.
- **`.hadolint.yaml`**: Configures hadolint rule ignores for Dockerfile linting.
- **`caddy/Caddyfile`**: `admin off` / `auto_https off` / `persist_config off` (no writable state dirs); a single `header { defer … }` block applies CSP + X-Frame-Options + X-Content-Type-Options + Referrer-Policy + COOP/CORP + Permissions-Policy to every response; `handle /assets/*` returns 404 for missing assets (never SPA-fallback) with `Cache-Control: public, max-age=31536000, immutable`; `handle /config.js` adds `Cache-Control: no-store`; `handle /publicnode` is a 307 redirect to `{$PUBLIC_RPC_URL:…}` (env-driven, defaults to the public node); the server listens on `:{$PORT:8080}` (ConfigMap-driven); `handle /internal/{isalive,isready}` use `respond` + `log_skip` (no access-log noise); the catch-all `handle` does `try_files {path} /index.html` for SPA fallback. **By design**, the CSP allows a `connect-src https:` wildcard (keeps `VITE_RPCENDPOINT` runtime-configurable) and omits COEP (it would block the cross-origin RPC fetch); the resulting ZAP `WARN-NEW` advisories are intentional, not findings — the DAST gate is FAIL-only (`FAIL-NEW: 0`).
- Both Dockerfiles use `pnpm install --frozen-lockfile` and copy lockfiles before source for layer caching.

## Conventions

- Package manager: **pnpm only** (no `npm`, no `npx` — Makefile uses `pnpm dlx`; Dockerfiles use `corepack enable pnpm`; `packageManager` field in package.json).
- Tool versioning: **mise** via `.mise.toml` (single source of truth across local + CI). Includes `aqua:` pins for kubectl/kind/yq/hadolint/act/trivy/gitleaks plus core node/pnpm. The Renovate CLI is pinned separately as `RENOVATE_VERSION` in the Makefile (npm datasource, fetched lazily via `mise exec`) so `make deps` doesn't eagerly reinstall its large dependency tree. Docker-image tools (`MERMAID_CLI_VERSION`, `ZAP_VERSION`, `CLOUD_PROVIDER_KIND_VERSION`, `PLANTUML_VERSION`) stay as Makefile constants (Renovate-tracked) since mise can't manage Docker images directly. `KIND_NODE_IMAGE` is also a Makefile constant but bumped together with `aqua:kubernetes-sigs/kind` per KinD release notes.
- Multi-session safety: `KIND_CLUSTER_NAME := $(APP_NAME)` and every `kubectl` invocation goes through `KUBECTL := kubectl --context=kind-$(KIND_CLUSTER_NAME)` so a parallel `make` from a sibling KinD project can't silently steer recipes to the wrong cluster.
- Node.js: pinned in `.mise.toml` (currently `node = "24"`); `.node-version` mirrors the major (`24`) and both Dockerfiles pin `node:24.x`. `make check-node-alignment` (first prerequisite of `static-check`) fails the build if any of these drift, and a Renovate cross-manager group bumps the mise + Dockerfile pins together.
- TypeScript: **6.x** with `moduleResolution: "bundler"` (no `baseUrl`, no `esModuleInterop`).
- Formatting: **prettier** only (no eslint).
- Parameter externalization: operator-tunable host/port/timeout values live in `.env.example` (committed source of truth; copy to gitignored `.env` to override). Shell scripts source `.env.example` then `.env`; the Makefile mirrors them as `?=` defaults; the SPA reads `VITE_*` at runtime via `/config.js` (Pattern C).
- Static analysis: **check-node-alignment + prettier + hadolint + Trivy fs + Trivy config + gitleaks + mermaid-lint + diagrams-check**, composed in `make static-check`.
- Commit messages: conventional commits (`feat:`, `fix:`, `chore:`, `ci:`, `refactor:`, `docs:`, `perf:`).
- Release: `make release` validates semver format (`vN.N.N`), writes `version.txt`, commits and pushes the tag.
- State management: **Redux Toolkit** with `createSlice` pattern (migrated from Rematch).

## Upgrade Backlog

Last reviewed: 2026-06-28 (`/architecture-diagrams` — converted the two inline Mermaid C4 diagrams (Context + Deployment) to **C4-PlantUML rendered PNGs** under `docs/diagrams/`: pinned `plantuml/plantuml` renderer (`PLANTUML_VERSION` Makefile constant), `make diagrams`/`diagrams-check` (version-stamped drift gate) wired into `static-check`, `ci.yml` `changes` filter re-includes `docs/diagrams/**/*.puml` as `code`, Renovate `custom.regex` manager tracks the C4-PlantUML `!include` version; the balance-query **sequence** diagram stays inline Mermaid. Plus the `/project-review` + `/test-coverage-analysis` + `/renovate` + `/readme` sweep, PRs #118/#120 — `npm:renovate` moved out of `.mise.toml` to a lazy `RENOVATE_VERSION` Makefile pin (no more ~600-pkg `make deps` reinstall); `cleanup-runs` rewritten to keep newest-5 **per workflow** + exclude open-PR head SHAs; `container-structure-test` split into a `-only` target so CI reuses the scan image; `_require-docker` guards; Renovate aqua `github-tags` `minimumReleaseAge` + `renovate` self-bump throttle; **`docker` + `dast` jobs gated to tag/release only** + **`e2e` prod-image build now gha-layer-cached** (`docker/setup-buildx-action` + `crazy-max/ghaction-github-runtime` token export + `DOCKER_BUILD_CACHE` var); SBOM-upload `vars.ACT` guard (fixed `make ci-run`); docs-gated `mermaid-lint` job; trivy-action repinned to its commit SHA; `persist-credentials:false` on the docker checkout; e2e security-header (`/assets`/`/internal`/`/config.js`) + balance-value + `@axe-core/playwright` a11y assertions; `getETHBalance` service-entry error test; README/CLAUDE doc sync incl. correcting the Renovate automerge description to PR-automerge (`platformAutomerge:false`)). Prior (2026-06-22): (`/ship-it` follow-up — `@types/node` 25→26 (tsc + tests verified), Renovate `caddy` group + a `xcaddy build vX.Y.Z` customManager so the rebuilt-binary version can't drift from the caddy FROM digests, confirmed the ZAP CSP/COEP advisories are intentional Caddyfile design; plus `/ship-it` — Stage 1 upgrades: caddy 2.11.3→2.11.4 + retired the go-jose `--replace` workaround (2.11.4 ships go-jose v3.0.5; kept the GOTOOLCHAIN stdlib rebuild for CVE-2026-42504), node 24.16.0→24.17.0, kind 0.31→0.32 + KIND_NODE_IMAGE v1.35.1→v1.36.1, pnpm 11.3→11.8, mise tool patches (act/kubectl/yq/trivy 0.70→0.71.2/renovate), react-router-dom 7.18 + viem 2.53; plus the `/project-review` apply — Renovate `Node` cross-manager group across mise + dockerfile managers, dropped redundant per-rule `automerge: true`, cleanup workflows `cancel-in-progress: false`, README H1 rename + tightened `cosign verify` identity-regexp + provisioned-tools/host-prereq doc, container-structure-test added to tool enumerations, Skills-table path corrections, C4Deployment element trim). Prior (2026-06-16): Node toolchain-alignment guard, `.env.example` parameter externalization, CI change-gate `!failure() && !cancelled()` hardening, Renovate `pinDigests` collision + `platformAutomerge` race fixes, e2e header/asset coverage, in-image HEALTHCHECK, container-structure-test gate, SPDX SBOM artifact + cosign attestation, Caddyfile `$PORT`/`$PUBLIC_RPC_URL` externalization, Dockerfile UID/port ARGs.

- [ ] **Architecture diagram tech-strings drift** — the C4 `.puml` sources in `docs/diagrams/` embed framework version strings (e.g. `"React 19 SPA, viem 2"`, `"Caddy 2 on :8080"`). Renovate cannot update these (`diagrams-check` only proves PNG↔source consistency, not source↔reality). Re-run `/architecture-diagrams` after any major bump, then `make diagrams` to re-render.
- [ ] **`.trivyignore` waivers for 3 base-image OS CVEs** — `CVE-2026-45447` (openssl), `CVE-2026-45186` (libexpat), `CVE-2026-6732` (libxml2) are present in the `caddy:2.11.4-alpine`/alpine-3.23 base; fixes are not yet in the alpine 3.23 repo (`apk upgrade` has no newer package), so they're waived with `exp:2026-07-22`. Reachability is nil (caddy is a static Go binary linking none of them). The Dockerfile's `apk --no-cache upgrade` pulls the fixes automatically once alpine ships them — remove the `.trivyignore` entries when `apk upgrade --simulate` shows the patched versions, or the waivers auto-expire on 2026-07-22 (re-evaluate then).
- [ ] **Daily cache-bust ARG on the runtime `apk --no-cache upgrade` layer** (`Dockerfile.prod`) — the runtime `apk upgrade` has no daily cache-bust ARG, so under the gha layer cache (now used by `e2e`, and by `docker`/`dast` on tags) the upgrade layer can replay stale and re-ship freshly-disclosed base-image OS CVEs (the class the `.trivyignore` waivers above track). Fix: add `ARG APK_UPGRADE_DATE` before the `RUN apk … upgrade` and pass `build-args: APK_UPGRADE_DATE=<daily date>` from the `build-push-action` steps. Flagged MEDIUM in the 2026-06-28 project-review (Phase-0 harden inventory) and deferred — run `/harden-image-pipeline` to apply.

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
| Any file under `e2e/`, `src/**/__tests__/*.integration.test.ts`, or new test layers | `/test-coverage-analysis` |
| `docs/diagrams/*.puml` (C4 Context + Deployment, rendered to PNG via `make diagrams`) and any markdown with ` ```mermaid ` (the sequence diagram is inline in README.md) | `/architecture-diagrams` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
