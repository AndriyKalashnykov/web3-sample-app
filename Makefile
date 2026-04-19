.DEFAULT_GOAL := help

APP_NAME       := web3-sample-app
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
LOCAL_BIN      := $(HOME)/.local/bin
MISE_DATA_DIR  := $(HOME)/.local/share/mise

# Make mise shims and ~/.local/bin visible to every recipe so freshly-installed
# tools resolve without per-recipe PATH gymnastics.
export PATH := $(MISE_DATA_DIR)/shims:$(LOCAL_BIN):$(PATH)

# renovate: datasource=npm depName=renovate
RENOVATE_VERSION := 43.110.14

# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.4.2

# Tools tracked via .mise.toml (single source of truth, Renovate-managed):
#   node, pnpm, act, hadolint, kubectl, kind, yq, trivy, gitleaks

# Shared depcheck ignore list (single source of truth for deps-prune targets).
DEPCHECK_IGNORES := @types/*,@tailwindcss/*,postcss,tailwindcss,@vitest/coverage-v8

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-20s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install all prerequisite tools via mise (node, pnpm, act, hadolint, kubectl, kind, yq, trivy, gitleaks)
deps:
	@command -v git >/dev/null 2>&1 || { \
		echo "Error: git is not installed. Please install git: https://git-scm.com/downloads"; \
		exit 1; \
	}
	@command -v mise >/dev/null 2>&1 || { \
		echo "Installing mise (no root required, installs to ~/.local/bin)..."; \
		curl -fsSL https://mise.run | sh; \
	}
	@mise install --yes
	@echo "All dependencies are available."

# Granular deps-* targets are aliases — mise installs everything from .mise.toml
# in a single pass, so individual installers are unnecessary. Aliases are kept
# for backwards compatibility with existing recipe wiring and CI references.

#deps-act: @ (alias for deps) Install act for local CI
deps-act: deps

#deps-hadolint: @ (alias for deps) Install hadolint for Dockerfile linting
deps-hadolint: deps

#deps-k8s: @ (alias for deps) Install kubectl, kind, yq
deps-k8s: deps

#deps-trivy: @ (alias for deps) Install Trivy for filesystem and config scans
deps-trivy: deps

#deps-secrets: @ (alias for deps) Install gitleaks for secret scanning
deps-secrets: deps

#clean: @ Cleanup build artifacts
clean:
	@rm -rf node_modules/ dist/

#install: @ Install NodeJS dependencies (pnpm install; uses --frozen-lockfile when CI=true)
install: deps node_modules

node_modules: package.json pnpm-lock.yaml
	@if [ -n "$$CI" ]; then \
		pnpm install --frozen-lockfile; \
	else \
		pnpm install; \
	fi
	@touch node_modules

#build: @ Build production bundle (tsc + vite)
build: install
	@pnpm build

#lint: @ Run prettier check and Dockerfile linting (hadolint)
lint: install deps-hadolint
	@pnpm prettier:diff
	@hadolint Dockerfile
	@hadolint Dockerfile.prod

#vulncheck: @ Check for vulnerable npm dependencies (pnpm audit)
vulncheck: install
	@pnpm audit --audit-level=moderate

#trivy-fs: @ Trivy filesystem scan (vulns, secrets, misconfigs)
trivy-fs: deps-trivy
	@trivy fs --scanners vuln,secret,misconfig --severity CRITICAL,HIGH --exit-code 1 --skip-dirs node_modules,dist .

#trivy-config: @ Trivy IaC scan against k8s manifests and Dockerfiles
trivy-config: deps-trivy
	@trivy config --severity CRITICAL,HIGH --exit-code 1 k8s/
	@trivy config --severity CRITICAL,HIGH --exit-code 1 Dockerfile
	@trivy config --severity CRITICAL,HIGH --exit-code 1 Dockerfile.prod

#secrets: @ Scan repository git history for committed secrets (gitleaks)
secrets: deps-secrets
	@gitleaks detect --no-banner --redact --source .

#mermaid-lint: @ Validate Mermaid blocks in markdown files via official CLI
mermaid-lint:
	@for f in $$(grep -lF '```mermaid' README.md CLAUDE.md docs/*.md 2>/dev/null || true); do \
		echo "Checking Mermaid blocks in $$f..."; \
		docker run --rm -v "$(PWD):/data" minlag/mermaid-cli:$(MERMAID_CLI_VERSION) -i "/data/$$f" -o "/tmp/$$(basename $$f .md)-validated.md" >/dev/null 2>&1 || { \
			echo "ERROR: Mermaid validation failed for $$f"; exit 1; \
		}; \
	done
	@echo "Mermaid lint passed."

#static-check: @ Composite quality gate: lint + vulncheck + trivy-fs + trivy-config + secrets + mermaid-lint + deps-prune-check
static-check: lint vulncheck trivy-fs trivy-config secrets mermaid-lint deps-prune-check

#format: @ Run prettier format
format: install
	@pnpm prettier

#check: @ Run static-check + test + build (full local pipeline)
check: static-check test build

#upgrade: @ Upgrade pnpm dependencies
upgrade: install
	@pnpm upgrade

#test: @ Run unit tests (vitest, fast — excludes *.integration.test.*)
test: install
	@pnpm test

#test-watch: @ Run tests in watch mode
test-watch: install
	@pnpm test:watch

#test-coverage: @ Run tests with coverage report
test-coverage: install
	@pnpm test:coverage

#run: @ Start dev server on port 8080
run: install
	@pnpm dev

#image-build: @ Build a dev Docker image
image-build:
	@docker buildx build --load -t $(APP_NAME):$(CURRENTTAG) .

#image-build-prod: @ Build a production Docker image (Dockerfile.prod)
image-build-prod:
	@docker buildx build --load -t $(APP_NAME):$(CURRENTTAG) -f Dockerfile.prod .

#image-run: @ Run the locally-built image on port 8080
image-run: image-stop
	@docker run --rm -p 8080:8080 --name web3 $(APP_NAME):$(CURRENTTAG)

#image-stop: @ Stop the running container
image-stop:
	@docker stop web3 || true

#ci: @ Run full CI pipeline (install + static-check + test + build)
ci: install static-check test build

#ci-run: @ Run GitHub workflow locally using act (random port, ephemeral artifact dir)
ci-run: deps-act
	@docker container prune -f 2>/dev/null || true
	@PORT=$$(shuf -i 40000-59999 -n 1); \
	ARTIFACT_DIR=$$(mktemp -d -t act-artifacts.XXXXXX); \
	echo "Using act port=$$PORT artifacts=$$ARTIFACT_DIR"; \
	act push --container-architecture linux/amd64 \
		--artifact-server-port $$PORT \
		--artifact-server-path $$ARTIFACT_DIR

#release: @ Create and push a new tag (prompts for vN.N.N)
release:
	@bash -c 'read -p "New tag (current: $(CURRENTTAG)): " newtag && \
		echo "$$newtag" | grep -qE "^v[0-9]+\.[0-9]+\.[0-9]+$$" || { echo "Error: Tag must match vN.N.N"; exit 1; } && \
		echo -n "Create and push $$newtag? [y/N] " && read ans && [ "$${ans:-N}" = y ] && \
		echo $$newtag > ./version.txt && \
		git add version.txt && \
		git commit -a -s -m "Cut $$newtag release" && \
		git tag $$newtag && \
		git push origin $$newtag && \
		git push && \
		echo "Done."'

#tag-delete: @ Delete a tag locally and remotely (usage: make tag-delete TAG=v0.0.1)
tag-delete:
ifndef TAG
	$(error TAG is undefined. Usage: make tag-delete TAG=v0.0.1)
endif
	@git push --delete origin $(TAG)
	@git tag --delete $(TAG)
	@echo "Deleted tag $(TAG)"

#kind-deploy: @ Deploy to a local KinD cluster
kind-deploy: deps-k8s image-build
	@kind load docker-image $(APP_NAME):$(CURRENTTAG) -n kind && \
	kubectl apply -f ./k8s/ns.yaml && \
	kubectl apply -f ./k8s/cm.yaml --namespace=web3 && \
	yq eval '.spec.template.spec.containers[0].image = "$(APP_NAME):$(CURRENTTAG)"' ./k8s/deployment.yaml | kubectl apply --namespace=web3 -f - && \
	kubectl apply -f ./k8s/service.yaml --namespace=web3

#kind-undeploy: @ Undeploy from a local KinD cluster
kind-undeploy: deps-k8s
	@kubectl delete -f ./k8s/deployment.yaml --namespace=web3 --ignore-not-found=true && \
	kubectl delete -f ./k8s/cm.yaml --namespace=web3 --ignore-not-found=true && \
	kubectl delete -f ./k8s/ns.yaml --ignore-not-found=true

#kind-redeploy: @ Redeploy to a local KinD cluster
kind-redeploy: deps-k8s image-build
	@kubectl delete -f ./k8s/deployment.yaml --namespace=web3 --ignore-not-found=true && \
	kubectl apply -f ./k8s/cm.yaml --namespace=web3 && \
	yq eval '.spec.template.spec.containers[0].image = "$(APP_NAME):$(CURRENTTAG)"' ./k8s/deployment.yaml | kubectl apply --namespace=web3 -f -

#deps-prune: @ Check for unused npm dependencies (depcheck, advisory)
deps-prune: install
	@echo "=== Dependency Pruning ==="
	@echo "--- Node: checking for unused packages ---"
	@npx --yes depcheck --ignores="$(DEPCHECK_IGNORES)" 2>/dev/null || true
	@echo "=== Pruning complete ==="

#deps-prune-check: @ Verify no prunable dependencies (CI gate)
deps-prune-check: install
	@npx --yes depcheck --ignores="$(DEPCHECK_IGNORES)" 2>/dev/null; \
	if [ $$? -ne 0 ]; then \
		echo "ERROR: Unused dependencies found. Run 'make deps-prune' to identify them."; \
		exit 1; \
	fi

#renovate-validate: @ Validate Renovate configuration
renovate-validate: deps
	@npx --yes renovate@$(RENOVATE_VERSION) --platform=local

#cleanup-runs: @ Delete workflow runs older than 7 days (keeps at least 5)
cleanup-runs:
	@gh run list --limit 100 --json databaseId,createdAt,status \
		--jq '[.[] | select(.createdAt < (now - 7*24*3600 | strftime("%Y-%m-%dT%H:%M:%SZ")))] | sort_by(.createdAt) | reverse | .[5:] | .[].databaseId' \
	| while read -r run_id; do \
		echo "Deleting run $$run_id"; \
		gh run delete "$$run_id" || true; \
	done

#cleanup-images: @ Delete untagged GHCR images (keeps 5 most recent)
cleanup-images:
	@PACKAGE="$(APP_NAME)"; \
	OWNER=$$(echo "$${OWNER:-$$(gh api user --jq .login)}" | tr '[:upper:]' '[:lower:]'); \
	KEEP=5; \
	echo "Fetching untagged versions of $$PACKAGE owned by $$OWNER..."; \
	gh api --paginate "/users/$$OWNER/packages/container/$$PACKAGE/versions" \
		--jq '.[] | select(.metadata.container.tags | length == 0) | {id, created_at}' \
	| jq -s --argjson keep $$KEEP 'sort_by(.created_at) | reverse | .[$$keep:] | .[].id' \
	| while read -r version_id; do \
		echo "Deleting version $$version_id"; \
		gh api --method DELETE "/users/$$OWNER/packages/container/$$PACKAGE/versions/$$version_id" || true; \
	done

.PHONY: help deps deps-act deps-hadolint deps-k8s deps-trivy deps-secrets clean install build lint vulncheck \
	trivy-fs trivy-config secrets mermaid-lint static-check format check upgrade \
	test test-watch test-coverage run \
	image-build image-build-prod image-run image-stop ci ci-run release tag-delete \
	kind-deploy kind-undeploy kind-redeploy deps-prune deps-prune-check renovate-validate \
	cleanup-runs cleanup-images
