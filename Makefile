.DEFAULT_GOAL := help

APP_NAME       := web3-sample-app
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
LOCAL_BIN      := $(HOME)/.local/bin
NVM_DIR        := $(HOME)/.nvm
NVM_VERSION    := 0.40.4
PNPM_VERSION   := 10.33.0
ACT_VERSION    := 0.2.87
HADOLINT_VERSION := 2.14.0
KUBECTL_VERSION := 1.35.3
KIND_VERSION   := 0.31.0
YQ_VERSION     := 4.52.5
RENOVATE_VERSION := 43.104.1

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-20s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install prerequisite tools (nvm, node, pnpm)
deps:
	@command -v git >/dev/null 2>&1 || { \
		echo "Error: git is not installed. Please install git: https://git-scm.com/downloads"; \
		exit 1; \
	}
	@if [ ! -d "$(NVM_DIR)" ]; then \
		echo "Installing nvm $(NVM_VERSION)..."; \
		curl -sSfL https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
	fi
	@bash -c 'source $(NVM_DIR)/nvm.sh && \
		if ! command -v node >/dev/null 2>&1 || [ "$$(node -v | cut -d. -f1 | tr -d v)" -lt 22 ]; then \
			echo "Installing Node.js via nvm..."; \
			nvm install; \
		fi'
	@command -v pnpm >/dev/null 2>&1 || { \
		echo "Installing pnpm $(PNPM_VERSION)..."; \
		npm install -g pnpm@$(PNPM_VERSION); \
	}
	@echo "All dependencies are available."

#deps-act: @ Install act for local CI
deps-act: deps
	@command -v act >/dev/null 2>&1 || { \
		echo "Installing act $(ACT_VERSION)..."; \
		mkdir -p $(LOCAL_BIN); \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash -s -- -b $(LOCAL_BIN) v$(ACT_VERSION); \
	}

#deps-hadolint: @ Install hadolint for Dockerfile linting
deps-hadolint:
	@command -v hadolint >/dev/null 2>&1 || { echo "Installing hadolint $(HADOLINT_VERSION)..."; \
		curl -sSfL -o /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-Linux-x86_64 && \
		mkdir -p $(LOCAL_BIN) && \
		install -m 755 /tmp/hadolint $(LOCAL_BIN)/hadolint && \
		rm -f /tmp/hadolint; \
	}

#deps-k8s: @ Install kubectl, kind, and yq
deps-k8s:
	@command -v kubectl >/dev/null 2>&1 || { \
		echo "Installing kubectl $(KUBECTL_VERSION)..."; \
		mkdir -p $(LOCAL_BIN); \
		curl -sSfL "https://dl.k8s.io/release/v$(KUBECTL_VERSION)/bin/linux/amd64/kubectl" -o $(LOCAL_BIN)/kubectl; \
		chmod +x $(LOCAL_BIN)/kubectl; \
	}
	@command -v kind >/dev/null 2>&1 || { \
		echo "Installing kind $(KIND_VERSION)..."; \
		mkdir -p $(LOCAL_BIN); \
		curl -sSfL "https://github.com/kubernetes-sigs/kind/releases/download/v$(KIND_VERSION)/kind-linux-amd64" -o $(LOCAL_BIN)/kind; \
		chmod +x $(LOCAL_BIN)/kind; \
	}
	@command -v yq >/dev/null 2>&1 || { \
		echo "Installing yq $(YQ_VERSION)..."; \
		mkdir -p $(LOCAL_BIN); \
		curl -sSfL "https://github.com/mikefarah/yq/releases/download/v$(YQ_VERSION)/yq_linux_amd64" -o $(LOCAL_BIN)/yq; \
		chmod +x $(LOCAL_BIN)/yq; \
	}

#clean: @ Cleanup
clean:
	@rm -rf node_modules/ dist/

#install: @ Install NodeJS dependencies
install: deps node_modules

node_modules: package.json pnpm-lock.yaml
	@pnpm install
	@touch node_modules

#ci-install: @ Install NodeJS dependencies (CI, frozen lockfile)
ci-install:
	@pnpm install --frozen-lockfile

#build: @ Build
build: install
	@pnpm build

#lint: @ Run prettier check and Dockerfile linting
lint: install deps-hadolint
	@pnpm prettier:diff
	@PATH="$(LOCAL_BIN):$$PATH" hadolint Dockerfile
	@PATH="$(LOCAL_BIN):$$PATH" hadolint Dockerfile.prod

#format: @ Run prettier format
format: install
	@pnpm prettier

#check: @ Run lint, test, and build
check: lint test build

#upgrade: @ Upgrade dependencies
upgrade: install
	@pnpm upgrade

#test: @ Run tests
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

#image-build: @ Build a Docker image
image-build:
	@docker buildx build --load -t $(APP_NAME):$(CURRENTTAG) .

#image-build-prod: @ Build a PROD Docker image
image-build-prod:
	@docker buildx build --load -t $(APP_NAME):$(CURRENTTAG) -f Dockerfile.prod .

#image-run: @ Run a Docker image
image-run: image-stop
	@docker run --rm -p 8080:8080 --name web3 $(APP_NAME):$(CURRENTTAG)

#image-stop: @ Stop a Docker image
image-stop:
	@docker stop web3 || true

#ci: @ Run full CI pipeline (install, lint, test, build)
ci: ci-install lint test build

#ci-run: @ Run GitHub workflow locally using act
ci-run: deps-act
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

#release: @ Create and push a new tag
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

#delete-tag: @ Delete a tag locally and remotely (usage: make delete-tag TAG=v0.0.1)
delete-tag:
ifndef TAG
	$(error TAG is undefined. Usage: make delete-tag TAG=v0.0.1)
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

#deps-prune: @ Check for unused npm dependencies
deps-prune: install
	@echo "=== Dependency Pruning ==="
	@echo "--- Node: checking for unused packages ---"
	@npx --yes depcheck --ignores="@types/*,@tailwindcss/*,postcss,tailwindcss" 2>/dev/null || true
	@echo "=== Pruning complete ==="

#deps-prune-check: @ Verify no prunable dependencies (CI gate)
deps-prune-check: install
	@npx --yes depcheck --ignores="@types/*,@tailwindcss/*,postcss,tailwindcss" 2>/dev/null; \
	if [ $$? -ne 0 ]; then \
		echo "ERROR: Unused dependencies found. Run 'make deps-prune' to identify them."; \
		exit 1; \
	fi

#renovate-validate: @ Validate Renovate configuration
renovate-validate:
	@npx --yes renovate@$(RENOVATE_VERSION) --platform=local

.PHONY: help deps deps-act deps-hadolint deps-k8s clean install ci-install build lint format check upgrade \
	test test-watch test-coverage run \
	image-build image-build-prod image-run image-stop ci ci-run release delete-tag \
	kind-deploy kind-undeploy kind-redeploy deps-prune deps-prune-check renovate-validate
