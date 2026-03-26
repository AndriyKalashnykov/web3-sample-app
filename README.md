# Web3 Sample App

Web3 frontend that queries ETH and DAI balances from the Ethereum blockchain.

## Requirements

All prerequisites can be installed automatically:

```bash
make deps
```

This installs (if missing): [nvm](https://github.com/nvm-sh/nvm), Node.js LTS, [pnpm](https://pnpm.io/), [act](https://github.com/nektos/act), [kubectl](https://kubernetes.io/docs/tasks/tools/), [kind](https://kind.sigs.k8s.io/), [yq](https://github.com/mikefarah/yq). Requires [git](https://git-scm.com/) and [Docker](https://docs.docker.com/get-docker/) to be pre-installed.

Node.js version is managed via `.node-version` (`lts/*`). Tools install to `~/.local/bin` (no sudo required).

## Tech Stack

- [React 19](https://react.dev/) + [TypeScript 6.x](https://www.typescriptlang.org/)
- [Vite 8](https://vite.dev/) - build tool (oxc minifier)
- [ethers.js v6](https://docs.ethers.org/v6/) - Ethereum library
- [MUI v7](https://mui.com/) - Material UI components
- [Tailwind CSS v4](https://tailwindcss.com/) - utility-first CSS
- [Rematch](https://rematchjs.org/) - Redux state management
- [i18next](https://www.i18next.com/) - internationalization

## Quick Start

```bash
make deps       # install all prerequisite tools
make install    # install Node.js dependencies
make run        # start dev server on http://localhost:8080
```

## Available Make Targets

```text
help             - List available tasks
deps             - Install prerequisite tools (nvm, node, pnpm, act, git, kubectl, kind, yq)
clean            - Cleanup
install          - Install NodeJS dependencies
ci-install       - Install NodeJS dependencies (CI, frozen lockfile)
build            - Build
lint             - Run prettier check
format           - Run prettier format
check            - Run lint and build
upgrade          - Upgrade dependencies
run              - Start dev server on port 8080
image-build      - Build a Docker image
image-build-prod - Build a PROD Docker image
image-run        - Run a Docker image
image-stop       - Stop a Docker image
ci-run           - Run GitHub workflow locally using act
release          - Create and push a new tag
delete-tag       - Delete a tag locally and remotely (usage: make delete-tag TAG=v0.0.1)
kind-deploy      - Deploy to a local KinD cluster
kind-undeploy    - Undeploy from a local KinD cluster
kind-redeploy    - Redeploy to a local KinD cluster
```

`make install` skips `pnpm install` when `node_modules` is already up-to-date with `package.json` and `pnpm-lock.yaml`.

Tool versions are pinned as constants at the top of the Makefile for reproducibility.

## CI/CD

GitHub Actions workflows:

### `ci.yml` - Build & Docker

Triggers: push to `main`, tags `v*`, pull requests, manual dispatch.

| Job | Runs on | What it does |
|-----|---------|--------------|
| **build** | every trigger | `ci-install` -> `lint` -> `build` |
| **docker-image** | tag push only | builds multi-arch image, pushes to GHCR |

All actions are pinned to commit SHAs for supply chain safety. CI uses `pnpm install --frozen-lockfile` to ensure reproducible builds.

### `cleanup-images.yml` - GHCR Cleanup

Runs weekly (Sunday 3 AM UTC) to delete old untagged container images, keeping the 5 most recent versions.

### `cleanup-runs.yml` - Workflow Run Cleanup

Runs weekly (Sunday midnight UTC) to delete workflow runs older than 7 days, keeping at least 5 runs.

### Run CI locally

```bash
make ci-run
```

Uses [act](https://github.com/nektos/act) to run the GitHub Actions workflow locally. The `deps` target installs `act` if not present.

### Dependency Management

[Renovate](https://docs.renovatebot.com/) manages dependency updates:
- Non-major updates automerge after CI passes
- Major updates require manual review (labeled `breaking`)
- TypeScript pinned to `~6.x` (major updates require manual review)

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

Valid Ethereum address for manual testing:

```
0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf
```
