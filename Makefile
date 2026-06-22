.DEFAULT_GOAL := help
SHELL := /bin/bash

APP_NAME       := web3-sample-app
# Strip the `v` prefix from git tags so local builds match what
# `docker/metadata-action`'s `type=semver,pattern={{version}}` publishes
# (e.g. tag v0.0.18 -> image :0.0.18, never :v0.0.18). `dev` fallback
# stays unprefixed in shallow CI clones.
RAW_TAG        := $(shell git describe --tags --abbrev=0 2>/dev/null || echo dev)
CURRENTTAG     := $(RAW_TAG:v%=%)
LOCAL_BIN      := $(HOME)/.local/bin
MISE_DATA_DIR  := $(HOME)/.local/share/mise

# Make mise shims and ~/.local/bin visible to every recipe so freshly-installed
# tools resolve without per-recipe PATH gymnastics.
export PATH := $(MISE_DATA_DIR)/shims:$(LOCAL_BIN):$(PATH)

# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.15.0

# Bumped together with aqua:kubernetes-sigs/kind in .mise.toml — see KinD
# release notes for the matching node image. Not independently trackable.
KIND_NODE_IMAGE := v1.36.1

# renovate: datasource=github-releases depName=zaproxy/zaproxy extractVersion=^v(?<version>.*)$
ZAP_VERSION := 2.17.0

# renovate: datasource=docker depName=registry.k8s.io/cloud-provider-kind/cloud-controller-manager
CLOUD_PROVIDER_KIND_VERSION := v0.10.0

KIND_CLUSTER_NAME := $(APP_NAME)
K8S_NAMESPACE     := web3

# Operator-tunable runtime values (host/port/timeouts/poll counts). `?=` lets
# the environment, CI, or a `.env` override them without editing this file.
# Defaults mirror the values baked into k8s manifests + the Caddyfile.
APP_INTERNAL_PORT     ?= 8080
HEALTHCHECK_HOST      ?= localhost
ROLLOUT_TIMEOUT       ?= 180s
LB_WAIT_SECONDS       ?= 60
LB_POLL_INTERVAL      ?= 1
HTTP_READY_RETRIES    ?= 15
SMOKE_TIMEOUT_SECONDS ?= 30

# Pin every kubectl call to this project's KinD context so a sibling project
# running `kubectl config use-context` cannot silently steer recipes to the
# wrong cluster. See /makefile skill §"Multi-session kubectl context safety".
KUBECTL    := kubectl --context=kind-$(KIND_CLUSTER_NAME)
KUBECTL_NS := $(KUBECTL) --namespace=$(K8S_NAMESPACE)

# yq filter that injects the locally-built image tag into both the main
# container and the seed-html init container in deployment.yaml.
KIND_IMAGE_PATCH := \
	.spec.template.spec.containers[0].image = "$(APP_NAME):$(CURRENTTAG)" | \
	.spec.template.spec.initContainers[0].image = "$(APP_NAME):$(CURRENTTAG)"

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
	@rm -rf node_modules/ dist/ zap-output/ e2e/playwright-report/ e2e/test-results/

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
	@set -euo pipefail; \
	IMAGE="minlag/mermaid-cli:$(MERMAID_CLI_VERSION)"; \
	for attempt in 1 2 3; do \
		if docker pull "$$IMAGE" >/dev/null 2>&1; then break; fi; \
		echo "docker pull $$IMAGE failed (attempt $$attempt/3); retrying..."; \
		sleep $$((attempt * 5)); \
		[ "$$attempt" = 3 ] && { echo "ERROR: docker pull $$IMAGE failed after 3 attempts"; exit 1; }; \
	done; \
	for f in $$(grep -lF '```mermaid' README.md CLAUDE.md docs/*.md 2>/dev/null || true); do \
		echo "Checking Mermaid blocks in $$f..."; \
		docker run --rm -v "$(PWD):/data" "$$IMAGE" -i "/data/$$f" -o "/tmp/$$(basename $$f .md)-validated.md" >/dev/null || { \
			echo "ERROR: Mermaid validation failed for $$f"; exit 1; \
		}; \
	done
	@echo "Mermaid lint passed."

#check-node-alignment: @ Fail if the Node major drifts across .mise.toml, .node-version, and both Dockerfiles
check-node-alignment:
	@set -euo pipefail; \
	mise_major=$$(grep -E '^node\s*=' .mise.toml | sed -E 's/.*"([0-9]+).*/\1/'); \
	nv_major=$$(sed -E 's/^v?([0-9]+).*/\1/' .node-version); \
	df_major=$$(grep -oE 'node:[0-9]+' Dockerfile | head -1 | cut -d: -f2); \
	dfp_major=$$(grep -oE 'node:[0-9]+' Dockerfile.prod | head -1 | cut -d: -f2); \
	echo "Node majors -> .mise.toml=$$mise_major .node-version=$$nv_major Dockerfile=$$df_major Dockerfile.prod=$$dfp_major"; \
	if [ "$$mise_major" != "$$nv_major" ] || [ "$$mise_major" != "$$df_major" ] || [ "$$mise_major" != "$$dfp_major" ]; then \
		echo "ERROR: Node major version drift detected. Align .mise.toml, .node-version, Dockerfile, and Dockerfile.prod."; \
		exit 1; \
	fi; \
	echo "Node major aligned across all pins ($$mise_major)."

#static-check: @ Composite quality gate: node-alignment + lint + vulncheck + trivy-fs + trivy-config + secrets + mermaid-lint + deps-prune-check
static-check: check-node-alignment lint vulncheck trivy-fs trivy-config secrets mermaid-lint deps-prune-check

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

#integration-test: @ Run integration tests (real RPC; uses VITE_RPCENDPOINT from .env)
integration-test: install
	@pnpm exec vitest run -c vitest.integration.config.ts

#deps-playwright: @ Install Playwright Chromium browser for browser e2e
deps-playwright: install
	@pnpm dlx playwright install chromium

#e2e: @ Deploy to KinD (LoadBalancer via cloud-provider-kind) and run curl-based e2e suite
e2e: kind-create kind-deploy
	@$(KUBECTL_NS) rollout status deployment/$(APP_NAME) --timeout=$(ROLLOUT_TIMEOUT)
	@bash -c 'set -e; \
		echo "Waiting for LoadBalancer IP..."; \
		for i in $$(seq 1 $(LB_WAIT_SECONDS)); do \
			LB_IP=$$($(KUBECTL_NS) get svc $(APP_NAME) -o jsonpath="{.status.loadBalancer.ingress[0].ip}"); \
			[ -n "$$LB_IP" ] && break; \
			sleep $(LB_POLL_INTERVAL); \
		done; \
		[ -z "$$LB_IP" ] && { echo "ERROR: no LoadBalancer IP after $(LB_WAIT_SECONDS)s"; exit 1; }; \
		echo "LB IP: $$LB_IP"; \
		for i in $$(seq 1 $(HTTP_READY_RETRIES)); do \
			curl -sf "http://$$LB_IP:$(APP_INTERNAL_PORT)/internal/isalive" >/dev/null 2>&1 && break; \
			sleep $(LB_POLL_INTERVAL); \
		done; \
		BASE="http://$$LB_IP:$(APP_INTERNAL_PORT)" ./e2e/e2e-test.sh'

#e2e-browser: @ Run Playwright browser e2e against deployed SPA via LoadBalancer IP
e2e-browser: kind-create kind-deploy deps-playwright
	@$(KUBECTL_NS) rollout status deployment/$(APP_NAME) --timeout=$(ROLLOUT_TIMEOUT)
	@bash -c 'set -e; \
		for i in $$(seq 1 $(LB_WAIT_SECONDS)); do \
			LB_IP=$$($(KUBECTL_NS) get svc $(APP_NAME) -o jsonpath="{.status.loadBalancer.ingress[0].ip}"); \
			[ -n "$$LB_IP" ] && break; \
			sleep $(LB_POLL_INTERVAL); \
		done; \
		[ -z "$$LB_IP" ] && { echo "ERROR: no LoadBalancer IP after $(LB_WAIT_SECONDS)s"; exit 1; }; \
		for i in $$(seq 1 $(HTTP_READY_RETRIES)); do \
			curl -sf "http://$$LB_IP:$(APP_INTERNAL_PORT)/internal/isalive" >/dev/null 2>&1 && break; \
			sleep $(LB_POLL_INTERVAL); \
		done; \
		E2E_BASE_URL="http://$$LB_IP:$(APP_INTERNAL_PORT)" pnpm exec playwright test -c e2e/playwright.config.ts'

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
	@docker run --rm -p $(APP_INTERNAL_PORT):$(APP_INTERNAL_PORT) --name $(APP_NAME) $(APP_NAME):$(CURRENTTAG)

#image-stop: @ Stop the running container
image-stop:
	@docker stop $(APP_NAME) || true

#container-structure-test: @ Validate prod image structure (USER, entrypoint, labels, files, caddy version)
container-structure-test: deps image-build-prod
	@container-structure-test test --image $(APP_NAME):$(CURRENTTAG) --config container-structure-test.yaml

#docker-smoke-test: @ Build prod image, run it on 8080, probe /internal/isalive (mirrors CI Gate 3)
docker-smoke-test: image-build-prod
	@docker rm -f $(APP_NAME)-smoke 2>/dev/null || true
	@docker run -d --name=$(APP_NAME)-smoke -p $(APP_INTERNAL_PORT):$(APP_INTERNAL_PORT) $(APP_NAME):$(CURRENTTAG) >/dev/null
	@echo "Waiting for Caddy /internal/isalive ..."
	@end=$$(( $$(date +%s) + $(SMOKE_TIMEOUT_SECONDS) )); ok=1; \
	while [ $$(date +%s) -lt $$end ]; do \
		if curl -fsS http://$(HEALTHCHECK_HOST):$(APP_INTERNAL_PORT)/internal/isalive >/dev/null 2>&1; then ok=0; break; fi; \
		sleep $(LB_POLL_INTERVAL); \
	done; \
	if [ $$ok -ne 0 ]; then \
		echo "FAIL: smoke test never reached /internal/isalive"; \
		docker logs $(APP_NAME)-smoke; \
		docker rm -f $(APP_NAME)-smoke >/dev/null; \
		exit 1; \
	fi; \
	echo "PASS: $(APP_NAME) container booted Caddy successfully"

#dast-scan: @ Run OWASP ZAP baseline against an already-running smoke container on :8080 (CI gate)
dast-scan:
	@mkdir -p zap-output && chmod 777 zap-output
	@docker run --rm --network host \
		-v "$(PWD)/zap-output:/zap/wrk:rw" \
		ghcr.io/zaproxy/zaproxy:$(ZAP_VERSION) \
		zap-baseline.py \
			-t http://$(HEALTHCHECK_HOST):$(APP_INTERNAL_PORT) \
			-I \
			-r zap-report.html \
			-J zap-report.json \
			-w zap-report.md \
		|| EXIT=$$?; \
		exit $${EXIT:-0}
	@echo "DAST report: $(PWD)/zap-output/zap-report.html"

#dast: @ Local DAST: docker-smoke-test then ZAP baseline; cleans up the container
dast: docker-smoke-test
	@trap 'docker rm -f $(APP_NAME)-smoke 2>/dev/null || true' EXIT INT TERM; \
	$(MAKE) dast-scan

#ci-run-tag: @ Run the workflow under act with a synthetic tag-push event (exercises docker + dast)
ci-run-tag: deps-act
	@docker container prune -f 2>/dev/null || true
	@TAG="$$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)"; \
	printf '{"ref":"refs/tags/%s","repository":{"default_branch":"main","name":"$(APP_NAME)"}}' "$$TAG" > /tmp/act-tag-event.json; \
	echo "Using synthetic tag event for $$TAG"
	@PORT=$$(shuf -i 40000-59999 -n 1); \
	ARTIFACT_DIR=$$(mktemp -d -t act-artifacts.XXXXXX); \
	echo "Using act port=$$PORT artifacts=$$ARTIFACT_DIR"; \
	act push \
		--eventpath /tmp/act-tag-event.json \
		--container-architecture linux/amd64 \
		--pull=false \
		--var ACT=true \
		--artifact-server-port $$PORT \
		--artifact-server-path $$ARTIFACT_DIR || true
	@echo "Note: cosign signing will fail under act (no OIDC) — expected."

#ci: @ Run full CI pipeline (install + static-check + test + integration-test + build)
ci: install static-check test integration-test build

#ci-run: @ Run GitHub workflow locally using act (random port, ephemeral artifact dir, e2e skipped via vars.ACT)
ci-run: deps-act
	@docker container prune -f 2>/dev/null || true
	@EVENT_FILE=$$(mktemp /tmp/act-push-event.XXXXXX.json); \
	printf '{"ref":"refs/heads/main","repository":{"default_branch":"main","name":"$(APP_NAME)"}}' > "$$EVENT_FILE"; \
	PORT=$$(shuf -i 40000-59999 -n 1); \
	ARTIFACT_DIR=$$(mktemp -d -t act-artifacts.XXXXXX); \
	echo "Using act port=$$PORT artifacts=$$ARTIFACT_DIR event=$$EVENT_FILE"; \
	act push \
		--eventpath "$$EVENT_FILE" \
		--container-architecture linux/amd64 \
		--pull=false \
		--var ACT=true \
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

#kind-up: @ Bring the full stack up — cluster + cloud-provider-kind + image + manifests (compose-up alias)
kind-up: kind-deploy
	@$(KUBECTL_NS) wait --for=condition=available --timeout=$(ROLLOUT_TIMEOUT) deployment/$(APP_NAME) >/dev/null
	@bash -c 'for i in $$(seq 1 $(LB_WAIT_SECONDS)); do \
		LB_IP=$$($(KUBECTL_NS) get svc $(APP_NAME) -o jsonpath="{.status.loadBalancer.ingress[0].ip}"); \
		[ -n "$$LB_IP" ] && break; \
		sleep $(LB_POLL_INTERVAL); \
	done; \
	[ -z "$$LB_IP" ] && { echo "ERROR: no LoadBalancer IP after $(LB_WAIT_SECONDS)s"; exit 1; }; \
	echo "======================================"; \
	echo "Stack is up — open http://$$LB_IP:$(APP_INTERNAL_PORT)"; \
	echo "======================================"'

#kind-down: @ Tear down the full stack — workload + cluster + cloud-provider-kind (compose-down alias)
kind-down: kind-destroy
	@echo "Stack is down."

#kind-create: @ Create a local KinD cluster (idempotent; granular — prefer `make kind-up`)
kind-create: deps-k8s
	@kind get clusters 2>/dev/null | grep -q "^$(KIND_CLUSTER_NAME)$$" || \
		kind create cluster \
			--name $(KIND_CLUSTER_NAME) \
			--image kindest/node:$(KIND_NODE_IMAGE)

#kind-cloud-provider-start: @ Start cloud-provider-kind in background (provides LoadBalancer IPs to kind)
kind-cloud-provider-start: deps-k8s
	@IMAGE="registry.k8s.io/cloud-provider-kind/cloud-controller-manager:$(CLOUD_PROVIDER_KIND_VERSION)"; \
	if [ -n "$$(docker ps -aq --filter name=^cloud-provider-kind$$)" ]; then \
		docker start cloud-provider-kind >/dev/null 2>&1 || true; \
	else \
		echo "Starting cloud-provider-kind container..."; \
		docker run -d --name cloud-provider-kind --restart unless-stopped \
			--network kind \
			-v /var/run/docker.sock:/var/run/docker.sock \
			"$$IMAGE" >/dev/null; \
	fi; \
	if [ -z "$$(docker ps -q --filter name=^cloud-provider-kind$$)" ]; then \
		echo "ERROR: cloud-provider-kind container failed to start"; \
		docker logs cloud-provider-kind 2>&1 | tail -20 || true; \
		exit 1; \
	fi; \
	echo "cloud-provider-kind running"

#kind-cloud-provider-stop: @ Stop cloud-provider-kind container (and any kindccm-* sidecars)
kind-cloud-provider-stop:
	@docker rm -f cloud-provider-kind >/dev/null 2>&1 || true
	@ORPHANS=$$(docker ps -aq --filter name=kindccm- 2>/dev/null); \
	if [ -n "$$ORPHANS" ]; then \
		echo "Removing kindccm-* orphan sidecars..."; \
		docker rm -f $$ORPHANS >/dev/null 2>&1 || true; \
	fi

#kind-destroy: @ Delete the local KinD cluster + stop cloud-provider-kind + prune kindccm-* orphans
kind-destroy: kind-cloud-provider-stop
	@command -v kind >/dev/null 2>&1 && kind delete cluster --name $(KIND_CLUSTER_NAME) 2>/dev/null || true

#kind-deploy: @ Deploy production image to a local KinD cluster (LoadBalancer via cloud-provider-kind)
kind-deploy: deps-k8s kind-create image-build-prod kind-cloud-provider-start
	@kind load docker-image $(APP_NAME):$(CURRENTTAG) -n $(KIND_CLUSTER_NAME) && \
	$(KUBECTL) apply -f ./k8s/ns.yaml && \
	$(KUBECTL_NS) apply -f ./k8s/cm.yaml && \
	yq eval '$(KIND_IMAGE_PATCH)' ./k8s/deployment.yaml | $(KUBECTL_NS) apply -f - && \
	$(KUBECTL_NS) apply -f ./k8s/service.yaml

#kind-undeploy: @ Undeploy from a local KinD cluster
kind-undeploy: deps-k8s
	@$(KUBECTL_NS) delete -f ./k8s/deployment.yaml --ignore-not-found=true && \
	$(KUBECTL_NS) delete -f ./k8s/cm.yaml --ignore-not-found=true && \
	$(KUBECTL) delete -f ./k8s/ns.yaml --ignore-not-found=true

#kind-redeploy: @ Redeploy production image to a local KinD cluster (idempotent — recreates ns+cm+svc if missing)
kind-redeploy: deps-k8s kind-create image-build-prod kind-cloud-provider-start
	@kind load docker-image $(APP_NAME):$(CURRENTTAG) -n $(KIND_CLUSTER_NAME) && \
	$(KUBECTL) apply -f ./k8s/ns.yaml && \
	$(KUBECTL_NS) apply -f ./k8s/cm.yaml && \
	$(KUBECTL_NS) delete -f ./k8s/deployment.yaml --ignore-not-found=true && \
	yq eval '$(KIND_IMAGE_PATCH)' ./k8s/deployment.yaml | $(KUBECTL_NS) apply -f - && \
	$(KUBECTL_NS) apply -f ./k8s/service.yaml

#deps-prune: @ Check for unused npm dependencies (depcheck, advisory)
deps-prune: install
	@echo "=== Dependency Pruning ==="
	@echo "--- Node: checking for unused packages ---"
	@pnpm dlx depcheck --ignores="$(DEPCHECK_IGNORES)" 2>/dev/null || true
	@echo "=== Pruning complete ==="

#deps-prune-check: @ Verify no prunable dependencies (CI gate)
deps-prune-check: install
	@pnpm dlx depcheck --ignores="$(DEPCHECK_IGNORES)" 2>/dev/null; \
	if [ $$? -ne 0 ]; then \
		echo "ERROR: Unused dependencies found. Run 'make deps-prune' to identify them."; \
		exit 1; \
	fi

#renovate-validate: @ Validate Renovate configuration (renovate provided by mise via npm:renovate)
renovate-validate: deps
	@renovate --platform=local

#cleanup-runs: @ Delete workflow runs older than 7 days (keeps at least 5)
cleanup-runs:
	@gh run list --limit 100 --json databaseId,createdAt,status \
		--jq '[.[] | select(.createdAt < (now - 7*24*3600 | strftime("%Y-%m-%dT%H:%M:%SZ")))] | sort_by(.createdAt) | reverse | .[5:] | .[].databaseId' \
	| while read -r run_id; do \
		echo "Deleting run $$run_id"; \
		gh run delete "$$run_id" || true; \
	done

#cleanup-caches: @ Delete GitHub Actions caches from merged or deleted branches
cleanup-caches:
	@gh cache list --limit 100 --json id,ref \
		--jq '.[] | select(.ref | startswith("refs/pull/") or contains("/merge")) | .id' \
	| while read -r cache_id; do \
		echo "Deleting cache $$cache_id"; \
		gh cache delete "$$cache_id" || true; \
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

.PHONY: help deps deps-act deps-hadolint deps-k8s deps-trivy deps-secrets deps-playwright clean install build lint vulncheck \
	trivy-fs trivy-config secrets mermaid-lint check-node-alignment static-check format check upgrade \
	test test-watch test-coverage integration-test e2e e2e-browser run \
	image-build image-build-prod image-run image-stop docker-smoke-test container-structure-test dast dast-scan \
	ci ci-run ci-run-tag release tag-delete \
	kind-up kind-down kind-create kind-destroy kind-cloud-provider-start kind-cloud-provider-stop \
	kind-deploy kind-undeploy kind-redeploy deps-prune deps-prune-check renovate-validate \
	cleanup-runs cleanup-caches cleanup-images
