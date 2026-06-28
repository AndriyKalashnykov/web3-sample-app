[![CI](https://github.com/AndriyKalashnykov/web3-sample-app/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/web3-sample-app/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/web3-sample-app.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/web3-sample-app/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/web3-sample-app)

# Ethereum Balance Viewer — React SPA

Reference **React 19 SPA** that reads **ETH and DAI ERC-20 balances** from Ethereum mainnet entirely in the browser via **viem 2** (no backend) — runtime-configured through a non-root **Caddy 2** container (Pattern-C `/config.js` injection) and deployable to Kubernetes.

Ships a **four-layer test pyramid** (Vitest unit/component + real-RPC integration, KinD curl e2e, Playwright Chromium e2e) and a **supply-chain-hardened GitHub Actions pipeline**: Trivy fs/config/image scans, gitleaks, OWASP ZAP **DAST**, container-structure-test + SPDX SBOM, **cosign keyless OIDC signing** — all tools **mise**-pinned and updates driven by **Renovate**.

<p align="center"><img src="docs/diagrams/out/c4-context.png" alt="System Context — Web3 Sample App (C4: End User → React SPA → Ethereum JSON-RPC + DAI contract)" width="900"></p>

| Component | Technology |
|-----------|------------|
| Language | TypeScript 6.x (`moduleResolution: "bundler"`) |
| Framework | React 19, react-router-dom 7 |
| Build tool | Vite 8 (oxc minifier, Rolldown manual chunks) |
| UI | MUI v9, Tailwind CSS v4 (`@tailwindcss/postcss`) |
| State | Redux Toolkit 2 (`createSlice`, typed hooks) |
| Web3 | viem 2 (`createPublicClient`, `http`, `readContract`, `parseAbi`) |
| i18n | i18next + react-i18next (English bundled) |
| Testing | Vitest 4, React Testing Library, jsdom, Playwright (Chromium) |
| Container | Builder: `node:24.17.0-alpine`; runtime: `caddy:2.11.4-alpine` (port 8080, runs as UID 1000; `cap_net_bind_service` stripped from the binary so it execs cleanly under `securityContext.capabilities.drop:[ALL]`) |
| Orchestration | Kubernetes (manifests under `k8s/`); local KinD via Makefile |
| CI/CD | GitHub Actions, Renovate (PR automerge on green CI) |
| Code quality | Prettier, hadolint, Trivy (fs+config), gitleaks |
| Tool versioning | mise (single source of truth in `.mise.toml`) |

## Quick Start

```bash
make deps       # install mise + all pinned tools (node, pnpm, hadolint, kubectl, kind, yq, trivy, gitleaks, act, container-structure-test)
make install    # pnpm install
make build      # tsc + vite build
make test       # run unit tests
make run        # start dev server, then open http://localhost:8080
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [Git](https://git-scm.com/) | latest | Version control + history (used by `gitleaks`) |
| [Docker](https://www.docker.com/) | latest | Container builds, KinD runtime, Mermaid lint |
| [curl](https://curl.se/) | latest | Bootstraps `mise` in `make deps` |
| [mise](https://mise.jdx.dev/) | latest | Manages every other tool (auto-installed by `make deps`) |

`make deps` installs [mise](https://mise.jdx.dev/) into `~/.local/bin` (no sudo) and then runs `mise install` against the pinned `.mise.toml` to provision: Node.js, pnpm, hadolint, kubectl, kind, yq, Trivy, gitleaks, act, container-structure-test. (The Renovate CLI used by `make renovate-validate` is pinned separately as a Makefile constant and fetched on demand via `mise exec`, not installed here — this keeps `make deps` from reinstalling its large dependency tree on every run.)

> The `image-*`, `docker-smoke-test`, `dast`, and `cleanup-*` targets shell out to host-provided tools that mise does not manage — `docker` (and, for the GHCR cleanup targets, [`gh`](https://cli.github.com/) + `jq`). Install those separately if you run those targets locally.

## Architecture

The SPA is a single React app served from a static Caddy 2 image. All blockchain calls happen in the browser against an external JSON-RPC endpoint configured at deploy time. There is no backend.

### Entry flow

1. `src/main.tsx` mounts `<App>` wrapped in MUI `ThemeProvider` + Redux `Provider`.
2. `src/App.tsx` renders the `Header`/`Footer` layout with `BrowserRouter`. Routes are defined in `src/router/index.ts` and lazy-loaded with `React.lazy` + `<Suspense>`.
3. The Ethereum service (`src/service/ether/ether.ts`) constructs a viem `PublicClient` against `VITE_RPCENDPOINT` (mainnet, `http` transport) and exposes `getETHBalance(address)` → `{block, balance}` and `getDAIBalance(address)` → `{block, name, symbol, balance, balanceFormatted}`. The DAI ERC-20 contract is hardcoded to its canonical mainnet address `0x6B17…1d0F` (no ENS lookup).
4. State lives in `src/store/` — Redux Toolkit slices (`counterSlice`, `commonSlice`) accessed through typed hooks (`useAppDispatch`, `useAppSelector`).

### Runtime env-var injection (Pattern C)

`Dockerfile.prod` is environment-agnostic — `public/config.js` carries `window.__CONFIG__ = { VITE_RPCENDPOINT: "${VITE_RPCENDPOINT}", VITE_BASE_URL: "${VITE_BASE_URL}" }` with literal placeholders. Vite copies it to `dist/config.js`; the build renames it to `dist/config.js.template`. At container startup, `start-caddy.sh` runs `envsubst` against that single template (restricted to `$VITE_RPCENDPOINT $VITE_BASE_URL`) and writes the result to `/srv/config.js`. `index.html` loads it via `<script src="/config.js"></script>`. The SPA reads `window.__CONFIG__` via `src/config.ts`, which falls through to `import.meta.env` when the placeholders are still literal (i.e. `pnpm dev`). **External file, not inline**: the Caddyfile sets CSP `script-src 'self'`, which forbids inline scripts without a per-deploy nonce/hash; `/config.js` under `/` is allowed by `'self'` without weakening CSP. The `handle /config.js` block sets `Cache-Control: no-store` so deploys pick up new values immediately. The K8s `ConfigMap` in `k8s/cm.yaml` provides the runtime values in cluster — see [`src/config.ts`](src/config.ts), [`public/config.js`](public/config.js), and [`start-caddy.sh`](start-caddy.sh).

### Path alias

`@/` maps to `src/` — configured in both `tsconfig.json` (`paths`) and `vite.config.ts` (`resolve.alias`).

### Balance-query sequence

```mermaid
sequenceDiagram
  autonumber
  actor User
  participant SPA as React SPA<br/>(AccountForm)
  participant Ether as Ether service<br/>(ether.ts)
  participant Client as viem.PublicClient<br/>(mainnet, http transport)
  participant RPC as Ethereum JSON-RPC<br/>(VITE_RPCENDPOINT)
  participant DAI as DAI ERC-20<br/>(0x6B17…1d0F)

  User->>SPA: enter address, click "Get Balance"
  SPA->>Ether: getETHBalance(address)
  Ether->>Client: createPublicClient({chain: mainnet, transport: http(...)})
  Ether->>Client: Promise.all([getBlockNumber(), getBalance({address})])
  Client->>RPC: eth_blockNumber + eth_getBalance
  RPC-->>Client: { block, balance (wei) }
  Client-->>Ether: { block, balance }
  Ether-->>SPA: { block, balance }
  SPA-->>User: render balance (formatEther) + block number

  Note over SPA,DAI: DAI flow adds 3 contract reads (name + symbol + balanceOf) in parallel
  SPA->>Ether: getDAIBalance(address)
  Ether->>Client: Promise.all([getBlockNumber(), readContract×3])
  Client->>DAI: name() + symbol() + balanceOf(address)
  DAI-->>Client: ('Dai Stablecoin', 'DAI', balance uint256)
  Client-->>Ether: { block, name, symbol, balance, balanceFormatted }
  Ether-->>SPA: { block, name, symbol, balance, balanceFormatted }
  SPA-->>User: render DAI balance
```

Source: [`src/service/ether/ether.ts`](src/service/ether/ether.ts) and [`src/components/AccountForm.tsx`](src/components/AccountForm.tsx).

### Deployment topology (KinD)

<img src="docs/diagrams/out/c4-deployment.png" alt="Deployment — KinD + cloud-provider-kind LoadBalancer: End User → envoy → Service → Caddy pod (ConfigMap envFrom) → Ethereum JSON-RPC" width="820">

The `seed-html` init container copies the baked SPA bundle (`assets/`, `index.html`, and `config.js.template`) from the read-only image filesystem into a writable `emptyDir` mounted at `/srv`. The main container's `start-caddy.sh` then runs `envsubst` against `config.js.template` only (variables restricted to `$VITE_RPCENDPOINT $VITE_BASE_URL`) and writes the result to `/srv/config.js`. The SPA reads the substituted values via `window.__CONFIG__` at boot. The `assets/` JS bundles AND `index.html` are byte-identical across environments, so consumers can verify by digest and Trivy/Cosign signatures stay consistent. This is what makes "build once, configure at deploy time" work despite `readOnlyRootFilesystem: true` on the main container — and the initContainer image MUST stay in lockstep with the main container image (both are patched to the same tag by `kind-deploy` via `KIND_IMAGE_PATCH`).

> The C4 Context (top) and Deployment diagrams are rendered from [`docs/diagrams/c4-context.puml`](docs/diagrams/c4-context.puml) and [`docs/diagrams/c4-deployment.puml`](docs/diagrams/c4-deployment.puml) (C4-PlantUML). Edit the `.puml` source and regenerate with `make diagrams`; `make diagrams-check` (part of `static-check`) fails CI if the committed PNGs drift from source.

## Testing

Four test layers, each with its own Makefile target, config, and CI job:

| Layer | Target | Files | Where it runs | What it covers |
|-------|--------|-------|---------------|----------------|
| Unit + Component | `make test` | `src/store/models/__tests__/`, `src/service/ether/__tests__/ether.test.ts`, `src/components/__tests__/` | jsdom (vitest, in-process) | Pure functions, Redux slices, mocked ether service, components rendered via `renderWithProviders` |
| Integration | `make integration-test` | `src/service/ether/__tests__/ether.integration.test.ts` | node (vitest, real network) | Ether service against the real `VITE_RPCENDPOINT` (block fetch, ETH/DAI balance, malformed-input negatives) |
| E2E — HTTP | `make e2e` | `e2e/e2e-test.sh` | KinD + cloud-provider-kind LoadBalancer | Caddy routes (`/internal/isalive`, `/internal/isready`, `/publicnode` → 307, SPA fallback, missing asset 404); security headers (CSP/X-Frame-Options/etc.) on `/`, `/assets/*`, `/internal/*`, `/config.js` + its JS `Content-Type`; verifies `start-caddy.sh` substituted `VITE_RPCENDPOINT` into served `/config.js` |
| E2E — Browser | `make e2e-browser` | `e2e/playwright.config.ts`, `e2e/account-form.spec.ts` | KinD + cloud-provider-kind + Playwright Chromium | AccountForm renders; real ETH + DAI RPC roundtrips update the block counter AND render a well-formed numeric balance; an `@axe-core/playwright` scan asserts no critical/serious WCAG2A/AA a11y violations — gated in CI as the only layer that catches CSP violations and runtime SPA errors |

```bash
make test               # unit + component (~1s)
make test-watch         # watch mode
make test-coverage      # coverage report
make integration-test   # real-RPC integration (~5s, needs outbound HTTPS)
make e2e                # full HTTP suite against deployed Caddy (~30s)
make e2e-browser        # Playwright browser e2e (~45s)
```

A valid Ethereum address for manual UI testing:

```text
0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf
```

## Build & Package

```bash
make build               # production bundle to ./dist
make image-build         # dev image (Node alpine + pnpm dev server)
make image-build-prod    # production image (Caddy 2 on 8080)
```

The production Dockerfile is three-stage: `node:24.17.0-alpine` builder → `caddy:2.11.4-builder-alpine` (runs `xcaddy build v2.11.4` with `GOTOOLCHAIN=go1.26.4` to rebuild Caddy's stdlib past the Go MIME-header DoS CVE-2026-42504 — the vanilla `caddy:2.11.4-alpine` binary ships Go 1.26.3 and is still flagged by Trivy; Caddy 2.11.4 already pins go-jose v3.0.5 so the earlier `--replace` workaround is retired) → `caddy:2.11.4-alpine` runtime, with the rebuilt binary copied over the bundled one. Both Dockerfiles use `pnpm install --frozen-lockfile`, pin base images by SHA256 digest, and copy lockfiles before source for layer caching. The final image runs as non-root (UID 1000); the build adds `gettext` (for `envsubst`) and strips `cap_net_bind_service` from `/usr/bin/caddy` so the binary execs cleanly under `securityContext.capabilities.drop:[ALL]` in K8s.

## Deployment

### Local KinD cluster

Two-command bring up / tear down (compose-style):

```bash
make kind-up      # cluster + cloud-provider-kind + image + manifests; prints the LB URL when ready
make kind-down    # full teardown (cluster + cloud-provider-kind)
```

`make kind-up` is the canonical entry point — it chains `kind-create` → `kind-cloud-provider-start` → `image-build-prod` → `kind-deploy` → wait for the LoadBalancer IP, then prints `Stack is up — open http://<LB_IP>:8080`. The LoadBalancer IP comes from `cloud-provider-kind` (a sigs.k8s.io project that runs envoy proxies on the kind Docker network). No MetalLB / NodePort gymnastics required.

Granular targets (for debugging flows):

```bash
make kind-create                  # create cluster only (idempotent)
make kind-cloud-provider-start    # start cloud-provider-kind daemon
make kind-cloud-provider-stop     # stop cloud-provider-kind daemon
make kind-deploy                  # build prod image, load, apply manifests
make kind-redeploy                # rebuild + recreate deployment
make kind-undeploy                # remove workload only (cluster stays)
make kind-destroy                 # delete cluster + stop cloud-provider-kind
```

Manual access after `make kind-up`:

```bash
LB_IP=$(kubectl -n web3 get svc web3-sample-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl "http://${LB_IP}:8080/internal/isalive"
xdg-open "http://${LB_IP}:8080"
```

`make e2e` does the LB-IP lookup automatically.

### From the public GHCR image

```bash
kubectl apply -f ./k8s --namespace=web3 --validate=false

service_ip=$(kubectl get services web3-sample-app -n web3 \
  -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
xdg-open "http://${service_ip}:8080"

kubectl delete -f ./k8s --namespace=web3
```

The K8s ConfigMap (`k8s/cm.yaml`) provides `VITE_RPCENDPOINT` to the running pod; `start-caddy.sh` substitutes it into `/config.js` at container startup (Pattern C — see [Runtime env-var injection](#runtime-env-var-injection-pattern-c)).

## Available Make Targets

Run `make help` to see the full list. Grouped by purpose:

### Build & Run

| Target | Description |
|--------|-------------|
| `make build` | Build production bundle (tsc + vite) |
| `make run` | Start dev server on port 8080 |
| `make install` | Install NodeJS dependencies (uses `--frozen-lockfile` when `CI=true`) |
| `make clean` | Cleanup `node_modules/` and `dist/` |
| `make upgrade` | Upgrade pnpm dependencies |

### Test Targets

| Target | Description |
|--------|-------------|
| `make test` | Run unit + component tests (vitest, fast) |
| `make test-watch` | Run tests in watch mode |
| `make test-coverage` | Run tests with coverage report |
| `make integration-test` | Run integration tests (real RPC via `VITE_RPCENDPOINT`) |
| `make e2e` | Deploy to KinD + run curl-based e2e suite |
| `make e2e-browser` | Run Playwright Chromium browser e2e against deployed SPA |
| `make deps-playwright` | Install Playwright Chromium browser |

### Code Quality

| Target | Description |
|--------|-------------|
| `make lint` | Prettier check + hadolint on both Dockerfiles |
| `make format` | Prettier `--write` |
| `make vulncheck` | `pnpm audit --audit-level=moderate` |
| `make trivy-fs` | Trivy filesystem scan (vulns + secrets + misconfigs) |
| `make trivy-config` | Trivy IaC scan (k8s manifests + Dockerfiles) |
| `make secrets` | gitleaks scan over git history |
| `make mermaid-lint` | Validate Mermaid blocks via `minlag/mermaid-cli` |
| `make deps-prune` | Advisory: list unused npm dependencies |
| `make deps-prune-check` | CI gate: fail if unused dependencies exist |
| `make static-check` | Composite: check-node-alignment + lint + vulncheck + trivy-fs + trivy-config + secrets + mermaid-lint + deps-prune-check |
| `make check` | static-check + test + build (full local pipeline) |

### Docker

| Target | Description |
|--------|-------------|
| `make image-build` | Build dev Docker image |
| `make image-build-prod` | Build production Docker image (`Dockerfile.prod`) |
| `make image-run` | Run image on port 8080 |
| `make image-stop` | Stop the running container |
| `make container-structure-test` | Build prod image + assert its structure (USER, entrypoint, OCI labels, runtime files, caddy version) — CI Gate 2.5 mirror |
| `make docker-smoke-test` | Build prod image + boot + curl `/internal/isalive` (CI Gate 3 mirror) |
| `make dast` | Local DAST: smoke-test + ZAP baseline against `:8080`; cleans up |
| `make dast-scan` | Run ZAP baseline against an already-running smoke container |

### Kubernetes

| Target | Description |
|--------|-------------|
| `make kind-up` | Compose-style bring-up: cluster + cloud-provider-kind + image + manifests + wait + print LB URL |
| `make kind-down` | Compose-style teardown: workload + cluster + cloud-provider-kind |
| `make kind-create` | (granular) Create a local KinD cluster (idempotent) |
| `make kind-destroy` | (granular) Delete the local KinD cluster + stop cloud-provider-kind |
| `make kind-cloud-provider-start` | (granular) Start `cloud-provider-kind` in background |
| `make kind-cloud-provider-stop` | (granular) Stop `cloud-provider-kind` background process |
| `make kind-deploy` | (granular) Build prod image + create cluster + start cloud-provider-kind + apply manifests |
| `make kind-undeploy` | (granular) Remove workload (cluster + cloud-provider-kind stay) |
| `make kind-redeploy` | (granular) Same as kind-deploy but recreates the deployment |

### CI

| Target | Description |
|--------|-------------|
| `make ci` | Full pipeline: install + static-check + test + integration-test + build |
| `make ci-run` | Run the GitHub Actions workflow locally via [act](https://github.com/nektos/act) (e2e + dast skipped via `vars.ACT`) |
| `make ci-run-tag` | Run the workflow under act with a synthetic tag-push event (exercises the `docker` job + `dast`; cosign expected to fail under act, no OIDC) |

### Utilities

| Target | Description |
|--------|-------------|
| `make help` | List available tasks |
| `make deps` | Install mise + all pinned tools |
| `make deps-act` / `deps-hadolint` / `deps-k8s` / `deps-trivy` / `deps-secrets` | Aliases for `deps` (kept for explicit-intent recipes) |
| `make release` | Create and push a new tag (`vN.N.N`) |
| `make tag-delete TAG=v0.0.1` | Delete a tag locally and remotely |
| `make renovate-validate` | Validate Renovate configuration |
| `make cleanup-runs` | Delete workflow runs older than 7 days (keeps the newest 5 per workflow; never deletes open-PR runs) |
| `make cleanup-caches` | Delete GitHub Actions caches from merged or deleted branches |
| `make cleanup-images` | Delete untagged GHCR images (keeps 5 most recent) |

## CI/CD

GitHub Actions runs on every push to `main`, every tag `v*`, every pull request, and on manual dispatch. All actions are pinned to commit SHAs.

| Job | Triggers | Steps |
|-----|----------|-------|
| **changes** | every event | `dorny/paths-filter` detects whether the diff includes code (anything outside docs/images). Doc-only PRs short-circuit downstream jobs while still reporting `ci-pass` (Rulesets-safe) |
| **static-check** | after changes (code paths only) | `make install` + `make static-check` (check-node-alignment, lint, vulncheck, trivy-fs, trivy-config, secrets, mermaid-lint, deps-prune-check) |
| **mermaid-lint** | docs-only changes (off `changes`) | `make mermaid-lint` validates the README/CLAUDE Mermaid blocks. Code changes run mermaid-lint inside `static-check` instead, so this job fires only when a doc-only edit skips `static-check` |
| **test** | after static-check | `make test` (unit + component) |
| **integration-test** | after static-check | `make integration-test` (real-RPC integration suite) |
| **build** | after static-check | `make build`; uploads `dist/` artifact |
| **e2e** | after build + test (skipped under act) | KinD + cloud-provider-kind LoadBalancer + curl assertions + Playwright browser e2e — `make e2e` and `make e2e-browser` |
| **dast** | tag pushes only (after build + test; skipped under act) | OWASP ZAP baseline scan against booted container at release; ZAP image cached |
| **docker** | tag pushes only (after static-check + build + test) | Builds + Trivy image scan + container-structure-test + SPDX SBOM + smoke test + `linux/amd64` build + push to GHCR + cosign keyless signing + SBOM attestation — all gated to release tags (`v*`). No image is built on ordinary commits |
| **ci-pass** | always (after all above) | Aggregator gate; fails if any upstream job failed or was cancelled |

#### Required Secrets and Variables

| Name | Type | Used by | Purpose |
|------|------|---------|---------|
| `vars.ACT` | Variable | `e2e`, `dast` | Set automatically by `act` (via `make ci-run --var ACT=true`); skips KinD-based and DAST jobs locally because docker-in-docker inside act is unreliable |
| `vars.VITE_RPCENDPOINT` | Variable (optional) | `integration-test` | Overrides the Ethereum JSON-RPC endpoint the real-RPC integration suite queries. Defaults to `https://ethereum-rpc.publicnode.com` |
| `vars.APP_INTERNAL_PORT` | Variable (optional) | `docker`, `dast` | Overrides the port the smoke/DAST container is published on. Defaults to `8080` |
| `vars.HEALTHCHECK_HOST` | Variable (optional) | `docker`, `dast` | Overrides the host the smoke/DAST probe targets. Defaults to `localhost` |
| `secrets.GITHUB_TOKEN` | Secret (auto) | `docker`, cleanup workflows | Provided by GitHub Actions; used to push to GHCR and call the API |

### Release image hardening

On a release tag (`v*`), the `docker` job runs the following gates in order **before** the image is pushed to GHCR. Any failure blocks the publish. (On ordinary commits this job is skipped — no image is built.)

| # | Gate | Catches | Tool |
|---|------|---------|------|
| 1 | Build single-arch image (`load: true`, linux/amd64) | Build regressions on the runner architecture | `docker/build-push-action` |
| 2 | **Trivy image scan** (CRITICAL/HIGH blocking) | CVEs in base image, OS packages, build layers, secrets, misconfigs | `aquasecurity/trivy-action` |
| 2.5 | **Container structure test** | Drift in the non-root USER, entrypoint, OCI labels, runtime files, or the CVE-patched caddy version | `container-structure-test` (`container-structure-test.yaml`) |
| 2.7 | **SPDX SBOM** (artifact + cosign attestation on tag) | No machine-readable bill of materials for the image | `aquasecurity/trivy-action` (`format: spdx-json`) + `cosign attest` |
| 3 | **Smoke test** | Caddy fails to boot or `/internal/isalive` doesn't respond | `docker run` + `curl` |
| 4 | Build + push (`linux/amd64`) | Publishes the image with `cache-from: type=gha` (~95% cache hit from Gate 1) | `docker/build-push-action` |
| 5 | **Cosign keyless OIDC signing** | Sigstore signature on the manifest digest (Rekor transparency log) | `sigstore/cosign-installer` + `cosign sign --yes <tag>@<digest>` |

The `dast` job (also tag-push only) adds:

| Gate | Catches | Tool |
|------|---------|------|
| **OWASP ZAP baseline** | Missing security headers, misconfigs, info leaks (`-I` = WARN-only; FAIL blocks; report uploaded) | `make dast-scan` |

`provenance: false` and `sbom: false` keep the OCI image index free of `unknown/unknown` attestation entries so the GHCR Packages "OS / Arch" tab renders. The SBOM is instead published as a separate `sbom-spdx` workflow artifact and a cosign SPDX attestation on the manifest digest — so a machine-readable bill of materials is available without the GHCR UI regression.

Verify a published image's signature:

```bash
cosign verify ghcr.io/andriykalashnykov/web3-sample-app:<tag> \
  --certificate-identity-regexp 'https://github\.com/AndriyKalashnykov/web3-sample-app/\.github/workflows/ci\.yml@refs/tags/v.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Tool versions for CI come from `.mise.toml` via [`jdx/mise-action`](https://github.com/jdx/mise-action) — no version drift between local and CI.

### Cleanup workflows

| Workflow | Schedule | Purpose |
|----------|----------|---------|
| `cleanup-images.yml` | Weekly (Sunday 03:00 UTC) | Delete untagged GHCR images, keep 5 most recent (calls `make cleanup-images`) |
| `cleanup-runs.yml` | Weekly (Sunday 00:00 UTC) | Delete workflow runs older than 7 days (`make cleanup-runs`) + caches from merged branches (`make cleanup-caches`) |

### Run CI locally

```bash
make ci-run
```

Uses [act](https://github.com/nektos/act) with a randomized artifact-server port and an ephemeral artifact directory to avoid colliding with concurrent invocations.

### Dependency management

[Renovate](https://docs.renovatebot.com/) manages dependency updates with PR automerge. Updates merge automatically once the required `ci-pass` check is green — platform automerge is intentionally **off** (`platformAutomerge: false`), so Renovate merges via its own run after re-confirming the check rather than racing GitHub's native auto-merge before the check registers. Major updates wait 3 days for stability. Tool versions in `.mise.toml` are tracked by Renovate's `mise` manager (and the `# renovate:` inline annotations on aqua: pins).

## Release

1. Update the version constant in [`src/components/Layout.tsx`](./src/components/Layout.tsx) (search for `const Version =`) so the in-app About page displays the new tag.
2. Run `make release` and respond to the prompts:
   ```bash
   make release
   ```
   The target validates the semver format (`vN.N.N`), writes `version.txt`, commits both files, tags the commit, and pushes both the tag and the branch. The `docker` CI job then builds and publishes the `linux/amd64` image to GHCR.
3. To delete a tag (locally and on the remote):
   ```bash
   make tag-delete TAG=v0.0.1
   ```

## Contributing

Contributions are welcome. Open an issue to discuss a change, or send a pull request — CI (`make ci`) must pass before merge.

## License

Released under the [MIT License](./LICENSE).
