# Web3 sample app

## Requirements

- [Node.js >= 22](https://nodejs.org/)
- [pnpm](https://pnpm.io/installation)
  ```bash
  npm install -g pnpm
  ```
- [kind >= 0.16.0](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) (for Kubernetes deployment)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) (for Kubernetes deployment)

## Tech Stack

- React 19, TypeScript, [Vite 8](https://github.com/vitejs/vite)
- [ethers.js v6](https://github.com/ethers-io/ethers.js)
- [MUI v7](https://mui.com/) - Material UI components
- [TailwindCSS v4](https://github.com/tailwindlabs/tailwindcss) - CSS framework
- [Rematch](https://rematchjs.org/) - Redux state management
- i18n via i18next

## Help

```bash
make help
```

```text
Usage: make COMMAND
Commands :
help             - List available tasks
deps             - Install prerequisite tools (act, pnpm, etc.)
clean            - Cleanup
install          - Install NodeJS dependencies
build            - Build
lint             - Run prettier check
format           - Run prettier format
upgrade          - Upgrade dependencies
run              - Run
image-build      - Build a Docker image
image-build-prod - Build a PROD Docker image
image-run        - Run a Docker image
image-stop       - Stop a Docker image
ci-run           - Run GitHub workflow locally using act
check-version    - Ensure VERSION variable is set
kind-deploy      - Deploy to a local KinD cluster
kind-undeploy    - Undeploy from a local KinD cluster
kind-redeploy    - Redeploy to a local KinD cluster
```

## Usage

```bash
make run
```

## CI/CD

The GitHub Actions workflow runs on every push and PR:
- **build** job: installs dependencies and builds the project (`make install && make build`)
- **docker-image** job: builds and pushes a Docker image to GHCR (only on tag push)

To run the CI workflow locally:

```bash
make ci-run
```

This uses [act](https://github.com/nektos/act) to execute the GitHub Actions workflow. The `deps` target will install `act` automatically if not present.

## Kubernetes deployment

### Deploy using docker image from public repository

#### Deploy workload

```bash
kubectl apply -f ./k8s --namespace=web3 --validate=false
```

#### Get workload's IP

```bash
service_ip=$(kubectl get services web3-sample-app -n web3 -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
xdg-open "http://${service_ip}:8080" > /dev/null 2>&1
```

#### Delete workload

```bash
kubectl delete -f ./k8s --namespace=web3
```

### Deploy to local Kind cluster

```bash
make kind-deploy
```

### Undeploy from local Kind cluster

```bash
make kind-undeploy
```

## Release

- Update field [Version](./src/components/Layout.tsx#L25)

  ```text
  const Version = "vX.Y.Z"
  ```

- Run `release` target
  ```bash
  make release
  ```

Valid eth address to test:

```
0xeB2629a2734e272Bcc07BDA959863f316F4bD4Cf
```
