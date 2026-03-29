[![CI](https://github.com/AndriyKalashnykov/web3-sample-app/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/web3-sample-app/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/web3-sample-app.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/web3-sample-app/)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/web3-sample-app)

# Web3 Sample App

Web3 frontend built with React 19, TypeScript, Vite 8, and ethers.js v6 that queries ETH and DAI balances from the Ethereum blockchain. Uses MUI v7, Tailwind CSS v4, and Rematch for state management.

## Quick Start

```bash
make deps       # install all prerequisite tools
make install    # install Node.js dependencies
make run        # start dev server on http://localhost:8080
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [Git](https://git-scm.com/) | latest | Version control |
| [Docker](https://www.docker.com/) | latest | Container builds and local K8s |
| [curl](https://curl.se/) | latest | Tool installation |

Install all other dependencies automatically:

```bash
make deps
```

This installs (if missing): [nvm](https://github.com/nvm-sh/nvm), Node.js LTS, [pnpm](https://pnpm.io/), [act](https://github.com/nektos/act), [kubectl](https://kubernetes.io/docs/tasks/tools/), [KinD](https://kind.sigs.k8s.io/), [yq](https://github.com/mikefarah/yq). Tools install to `~/.local/bin` (no sudo required).

Node.js version is managed via `.node-version` (`lts/*`).

## Available Make Targets

Run `make help` to see all available targets.

### Build & Run

| Target | Description |
|--------|-------------|
| `make build` | Build (tsc + vite) |
| `make run` | Start dev server on port 8080 |
| `make install` | Install Node.js dependencies |
| `make clean` | Cleanup node_modules and dist |
| `make upgrade` | Upgrade dependencies |

### Code Quality

| Target | Description |
|--------|-------------|
| `make lint` | Run prettier check and Dockerfile linting |
| `make format` | Run prettier format |
| `make check` | Run lint and build |
| `make test` | Run tests |
| `make test.watch` | Run tests in watch mode |
| `make test.coverage` | Run tests with coverage report |

### CI

| Target | Description |
|--------|-------------|
| `make ci` | Full CI pipeline: install, lint, test, build |
| `make ci-install` | Install Node.js dependencies (CI, frozen lockfile) |
| `make ci-run` | Run GitHub Actions workflow locally via [act](https://github.com/nektos/act) |

### Docker

| Target | Description |
|--------|-------------|
| `make image-build` | Build a Docker image |
| `make image-build-prod` | Build a production Docker image |
| `make image-run` | Run a Docker image |
| `make image-stop` | Stop a Docker image |

### Kubernetes

| Target | Description |
|--------|-------------|
| `make kind-deploy` | Deploy to a local KinD cluster |
| `make kind-undeploy` | Undeploy from a local KinD cluster |
| `make kind-redeploy` | Redeploy to a local KinD cluster |

### Utilities

| Target | Description |
|--------|-------------|
| `make deps` | Install prerequisite tools (nvm, node, pnpm, act, git, kubectl, kind, yq) |
| `make deps-hadolint` | Install hadolint for Dockerfile linting |
| `make release` | Create and push a new tag |
| `make delete-tag TAG=v0.0.1` | Delete a tag locally and remotely |
| `make renovate-validate` | Validate Renovate configuration |

`make install` skips `pnpm install` when `node_modules` is already up-to-date with `package.json` and `pnpm-lock.yaml`.

Tool versions are pinned as constants at the top of the Makefile for reproducibility.

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, and pull requests.

| Job | Triggers | Steps |
|-----|----------|-------|
| **build** | push, PR, tags | Lint, Test, Build |
| **docker-image** | tag push only | Multi-arch image build + push to GHCR |

All actions are pinned to commit SHAs for supply chain safety. CI uses `pnpm install --frozen-lockfile` for reproducible builds.

### Cleanup Workflows

| Workflow | Schedule | Purpose |
|----------|----------|---------|
| `cleanup-images.yml` | Weekly (Sunday 3 AM UTC) | Delete old untagged GHCR images, keep 5 most recent |
| `cleanup-runs.yml` | Weekly (Sunday midnight UTC) | Delete workflow runs older than 7 days, keep at least 5 |

### Run CI Locally

```bash
make ci-run
```

Uses [act](https://github.com/nektos/act) to run the GitHub Actions workflow locally. The `deps` target installs `act` if not present.

### Dependency Management

[Renovate](https://docs.renovatebot.com/) manages dependency updates with platform automerge enabled. Non-major updates automerge after CI passes. Major updates wait 3 days for stability.

## Kubernetes Deployment

### From public GHCR image

```bash
# deploy
kubectl apply -f ./k8s --namespace=web3 --validate=false

# get external IP
service_ip=$(kubectl get services web3-sample-app -n web3 -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
xdg-open "http://${service_ip}:8080"

# delete
kubectl delete -f ./k8s --namespace=web3
```

### Local Kind cluster

```bash
make kind-deploy     # build image + deploy
make kind-undeploy   # remove workload
make kind-redeploy   # update running deployment
```

## Release

1. Update the version constant in [`src/components/Layout.tsx`](./src/components/Layout.tsx#L25):
   ```ts
   const Version = 'vX.Y.Z'
   ```

2. Create and push the tag:
   ```bash
   make release
   ```
   This validates the semver format (`vN.N.N`), commits the tag, pushes it, and triggers the Docker image build.

3. To delete a tag:
   ```bash
   make delete-tag TAG=v0.0.1
   ```

## Testing

Vitest with React Testing Library and jsdom. Run tests with:

```bash
make test            # run tests once
make test.watch      # run tests in watch mode
make test.coverage   # run tests with coverage report
```

Valid Ethereum address for manual testing:

```
0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf
```
