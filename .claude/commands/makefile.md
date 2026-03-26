# Makefile Authoring & Maintenance

Write, extend, and maintain Makefiles following the owner's established conventions across 30+ projects spanning Go, Node/TypeScript, Java/Gradle, C#/.NET, and Python.

## When to Activate

- Creating a new Makefile for a project
- Adding or modifying Makefile targets
- Fixing broken Makefile targets
- Reviewing Makefile structure and conventions
- Setting up CI pipeline targets
- Adding Docker, Kubernetes, or release targets

## Structure Template

Every Makefile MUST follow this skeleton:

```makefile
.DEFAULT_GOAL := help

APP_NAME       := my-app
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

# === Tool Versions (pinned) ===
# Pin ALL tool versions as constants at the top. Never use @latest in deps.
TOOL_VERSION   := 1.2.3

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-16s\033[0m - %s\n", $$1, $$2}'

# ... targets ...

.PHONY: help deps clean build test lint run ...
```

## Mandatory Conventions

### 1. Help System (REQUIRED on every target)

Every target MUST have a comment in this exact format:
```makefile
#target-name: @ Short description
```
The `help` target auto-generates documentation by grepping these comments. No comment = invisible target.

### 2. Command Suppression

Use `@` prefix on ALL recipe lines to suppress echoing:
```makefile
# CORRECT
build:
	@go build -o server .

# WRONG -- noisy output
build:
	go build -o server .
```

Exception: Long commands where seeing the command helps debugging (e.g., `docker buildx build` with many flags).

### 3. Pinned Tool Versions

Pin ALL tool versions at the top of the Makefile as constants:
```makefile
GOLANGCI_VERSION := 2.11.1
GOSEC_VERSION    := 2.24.0
NVM_VERSION      := 0.40.4
PNPM_VERSION     := 10.33.0
```

NEVER use `@latest` in `deps` targets. Every install must be reproducible.

### 4. Idempotent Dependency Installation

Use `command -v` guard pattern for every tool:
```makefile
deps:
	@command -v tool >/dev/null 2>&1 || { echo "Installing tool..."; install-command; }
```

The `deps` target must be safe to run repeatedly with no side effects.

### 5. Target Independence

Individual targets (`test`, `lint`, `run`) are **self-contained** and do NOT cascade through deep dependency chains. Only `build` should depend on `deps`. The `ci` target orchestrates the full pipeline as a **linear sequence**:
```makefile
# CORRECT -- ci orchestrates, targets are independent
build: deps
	@$(BUILD_CMD)

test:
	@$(TEST_CMD)

ci: deps build lint test coverage-check
	@echo "CI passed."

# WRONG -- deep cascading chains
test: lint
lint: build
build: deps
```

### 6. .PHONY Declaration

Always declare ALL targets as `.PHONY` at the bottom of the Makefile in a single block:
```makefile
.PHONY: help deps clean build test lint run ci release \
	docker-build docker-run docker-push
```

## Standard Targets

Every project should have these targets (language-specific implementation varies):

| Target | Purpose | Dependencies |
|--------|---------|-------------|
| `help` | List all targets | none |
| `deps` | Install tools (idempotent) | none |
| `clean` | Remove artifacts | none |
| `build` | Compile/package | `deps` |
| `test` | Run tests | none |
| `lint` | Code quality checks | none |
| `run` | Start locally | `build` or `install` |
| `ci` | Full local CI pipeline | orchestrates others |
| `release` | Tag and push release | validation targets |

### Optional Targets

| Target | Purpose | When to include |
|--------|---------|----------------|
| `install` | Install language deps (pnpm, go mod) | Node, Python projects |
| `format` | Auto-fix formatting | When formatter available |
| `check` | lint + build combined | Shorthand for pre-commit |
| `update` / `upgrade` | Update dependencies | Always |
| `coverage` | Generate coverage report | When tests exist |
| `coverage-check` | Verify threshold (80%+) | CI pipelines |
| `static-check` | lint + sec + vulncheck combined | Go projects |
| `sec` | Security scanner | Go (gosec), Java (OWASP) |
| `vulncheck` | Vulnerability scan | Go (govulncheck) |
| `secrets` | Scan for leaked secrets | All (gitleaks) |
| `e2e` | End-to-end tests | When E2E tests exist |

## Docker Targets

Consistent naming across all projects:

```makefile
DOCKER_IMAGE    := $(APP_NAME)
DOCKER_REGISTRY ?= ghcr.io
DOCKER_REPO     ?= owner/$(DOCKER_IMAGE)
DOCKER_TAG      ?= $(CURRENTTAG)

#image-build: @ Build Docker image
image-build:
	docker buildx build --load -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

#image-build-prod: @ Build production Docker image
image-build-prod:
	docker buildx build --load -t $(DOCKER_IMAGE):$(DOCKER_TAG) -f Dockerfile.prod .

#image-run: @ Run Docker container
image-run: image-stop
	@docker run --rm -p 8080:8080 --name $(APP_NAME) $(DOCKER_IMAGE):$(DOCKER_TAG)

#image-stop: @ Stop Docker container
image-stop:
	@docker stop $(APP_NAME) || true

#image-push: @ Push Docker image to registry
image-push: image-build
	docker push $(DOCKER_REGISTRY)/$(DOCKER_REPO):$(DOCKER_TAG)
```

For Docker-dependent targets, add a guard:
```makefile
require-docker:
	@command -v docker >/dev/null 2>&1 || { echo "Error: Docker required."; exit 1; }

image-build: require-docker
	...
```

## Release Target

Interactive tag creation with validation:

```makefile
#release: @ Create and push a new tag
release:
	@bash -c 'read -p "New tag (current: $(CURRENTTAG)): " newtag && \
		echo "$$newtag" | grep -qE "^v[0-9]+\.[0-9]+\.[0-9]+$$" || { echo "Error: Tag must match vN.N.N"; exit 1; } && \
		echo -n "Create and push $$newtag? [y/N] " && read ans && [ "$${ans:-N}" = y ] && \
		echo $$newtag > ./version.txt && \
		git add -A && \
		git commit -a -s -m "Cut $$newtag release" && \
		git tag $$newtag && \
		git push origin $$newtag && \
		git push && \
		echo "Done."'
```

Key conventions:
- Prompt for tag with current tag shown
- Validate semver format `vN.N.N`
- Confirm before executing
- Update version file, commit, tag, push

## Kubernetes Targets

When KinD/kubectl are needed:

```makefile
#kind-deploy: @ Deploy to local KinD cluster
kind-deploy: image-build
	@kind load docker-image $(APP_NAME):$(CURRENTTAG) -n kind && \
	kubectl apply -f ./k8s/ns.yaml && \
	kubectl apply -f ./k8s/ --namespace=$(APP_NAME)

#kind-undeploy: @ Remove from KinD cluster
kind-undeploy:
	@kubectl delete -f ./k8s/ --namespace=$(APP_NAME) --ignore-not-found=true
```

## CI Pipeline Target

The `ci` target mirrors what GitHub Actions runs, as a linear sequence:

```makefile
# Go project
ci: static-check build test fuzz
	@echo "Local CI pipeline passed."

# Node/TypeScript project
ci: lint build
	@echo "Local CI pipeline passed."

# Java/Gradle project
ci: deps
	@echo "=== Step 1/4: Build ===" && $(GRADLE) clean build
	@echo "=== Step 2/4: Lint ===" && $(GRADLE) checkstyleMain
	@echo "=== Step 3/4: Test ===" && $(GRADLE) test
	@echo "=== Step 4/4: Coverage ===" && $(GRADLE) jacocoTestCoverageVerification
	@echo "=== CI Complete ==="
```

## Language-Specific Patterns

### Go
```makefile
GOFLAGS ?= -mod=mod
GOOS    ?= linux
GOARCH  ?= amd64

build: deps
	@export GOFLAGS=$(GOFLAGS); export CGO_ENABLED=0; go build -a -o server .

test:
	@export GOFLAGS=$(GOFLAGS); go test -v ./...

update:
	@export GOFLAGS=$(GOFLAGS); go get -u; go mod tidy
```

### Node/TypeScript (pnpm)
```makefile
install: node_modules

node_modules: package.json pnpm-lock.yaml
	pnpm install
	@touch node_modules

ci-install:
	pnpm install --frozen-lockfile

build: install
	pnpm build

lint:
	pnpm prettier:diff
```

### Java/Gradle
```makefile
GRADLE     := ./gradlew
NO_CACHE   := --no-configuration-cache
SDKMAN     := $${SDKMAN_DIR:-$$HOME/.sdkman}/bin/sdkman-init.sh

build: deps
	@$(GRADLE) build

test:
	@$(GRADLE) test
```

## Platform Detection

When cross-platform support is needed:

```makefile
OPEN_CMD := $(if $(filter Darwin,$(shell uname -s)),open,xdg-open)

# Usage
coverage-open:
	@$(OPEN_CMD) ./build/reports/coverage/index.html
```

## Checklist: New Makefile

- [ ] `.DEFAULT_GOAL := help` set
- [ ] Every target has `#name: @ description` comment
- [ ] All recipe lines prefixed with `@`
- [ ] Tool versions pinned as constants at top
- [ ] `deps` target is idempotent with `command -v` guards
- [ ] `.PHONY` declaration includes all targets
- [ ] `help`, `deps`, `clean`, `build`, `test`, `lint`, `run`, `ci` targets present
- [ ] `release` target validates semver and confirms before push
- [ ] Docker targets follow `image-build`/`image-run`/`image-stop` naming
- [ ] No `@latest` in any install command
