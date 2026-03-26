.DEFAULT_GOAL := help

APP_NAME    := web3-sample-app
CURRENTTAG  := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
ACT_VERSION := 0.2.86
NVM_DIR     := $(HOME)/.nvm

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-16s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install prerequisite tools (nvm, node, pnpm, act, git, kubectl, kind, yq)
deps:
	@command -v git >/dev/null 2>&1 || { \
		echo "Error: git is not installed. Please install git: https://git-scm.com/downloads"; \
		exit 1; \
	}
	@if [ ! -d "$(NVM_DIR)" ]; then \
		echo "Installing nvm..."; \
		curl -sSfL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash; \
	fi
	@bash -c 'source $(NVM_DIR)/nvm.sh && \
		if ! command -v node >/dev/null 2>&1 || [ "$$(node -v | cut -d. -f1 | tr -d v)" -lt 22 ]; then \
			echo "Installing Node.js LTS via nvm..."; \
			nvm install --lts; \
			nvm use --lts; \
		fi'
	@command -v pnpm >/dev/null 2>&1 || { \
		echo "Installing pnpm..."; \
		npm install -g pnpm; \
	}
	@command -v act >/dev/null 2>&1 || { \
		echo "Installing act $(ACT_VERSION)..."; \
		mkdir -p $$HOME/.local/bin; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash -s -- -b $$HOME/.local/bin v$(ACT_VERSION); \
	}
	@command -v kubectl >/dev/null 2>&1 || { \
		echo "Installing kubectl..."; \
		mkdir -p $$HOME/.local/bin; \
		curl -sSfL "https://dl.k8s.io/release/$$(curl -sSfL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o $$HOME/.local/bin/kubectl; \
		chmod +x $$HOME/.local/bin/kubectl; \
	}
	@command -v kind >/dev/null 2>&1 || { \
		echo "Installing kind..."; \
		mkdir -p $$HOME/.local/bin; \
		KIND_VERSION=$$(curl -sSfL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep '"tag_name"' | cut -d'"' -f4); \
		curl -sSfL "https://github.com/kubernetes-sigs/kind/releases/download/$${KIND_VERSION}/kind-linux-amd64" -o $$HOME/.local/bin/kind; \
		chmod +x $$HOME/.local/bin/kind; \
	}
	@command -v yq >/dev/null 2>&1 || { \
		echo "Installing yq..."; \
		mkdir -p $$HOME/.local/bin; \
		YQ_VERSION=$$(curl -sSfL https://api.github.com/repos/mikefarah/yq/releases/latest | grep '"tag_name"' | cut -d'"' -f4); \
		curl -sSfL "https://github.com/mikefarah/yq/releases/download/$${YQ_VERSION}/yq_linux_amd64" -o $$HOME/.local/bin/yq; \
		chmod +x $$HOME/.local/bin/yq; \
	}
	@echo "All dependencies are available."

#clean: @ Cleanup
clean:
	@rm -rf node_modules/ dist/

#install: @ Install NodeJS dependencies
install: node_modules

node_modules: package.json pnpm-lock.yaml
	pnpm install
	@touch node_modules

#ci-install: @ Install NodeJS dependencies (CI, frozen lockfile)
ci-install:
	pnpm install --frozen-lockfile

#build: @ Build
build: install
	pnpm build

#lint: @ Run prettier check
lint:
	pnpm prettier:diff

#format: @ Run prettier format
format:
	pnpm prettier

#check: @ Run lint and build
check: lint build

#upgrade: @ Upgrade dependencies
upgrade:
	pnpm upgrade

#run: @ Start dev server on port 8080
run: install
	@VITE_RPCENDPOINT=https://rpc.ankr.com/eth pnpm dev

#image-build: @ Build a Docker image
image-build:
	docker buildx build --load -t $(APP_NAME):$(CURRENTTAG) .

#image-build-prod: @ Build a PROD Docker image
image-build-prod:
	docker buildx build --load -t $(APP_NAME):$(CURRENTTAG) -f Dockerfile.prod .

#image-run: @ Run a Docker image
image-run: image-stop
	@docker run --rm -p 8080:8080 --name web3 $(APP_NAME):$(CURRENTTAG)

#image-stop: @ Stop a Docker image
image-stop:
	@docker stop web3 || true

#ci-run: @ Run GitHub workflow locally using act
ci-run: deps
	act -j build --container-architecture linux/amd64

#release: @ Create and push a new tag
release:
	@bash -c 'read -p "New tag (current: $(CURRENTTAG)): " newtag && \
		echo -n "Create and push $$newtag? [y/N] " && read ans && [ "$${ans:-N}" = y ] && \
		echo $$newtag > ./version.txt && \
		git add -A && \
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
	git push --delete origin $(TAG)
	git tag --delete $(TAG)
	@echo "Deleted tag $(TAG)"

#kind-deploy: @ Deploy to a local KinD cluster
kind-deploy: image-build
	@kind load docker-image $(APP_NAME):$(CURRENTTAG) -n kind && \
	kubectl apply -f ./k8s/ns.yaml && \
	kubectl apply -f ./k8s/cm.yaml --namespace=web3 && \
	yq eval '.spec.template.spec.containers[0].image = "$(APP_NAME):$(CURRENTTAG)"' ./k8s/deployment.yaml | kubectl apply --namespace=web3 -f - && \
	kubectl apply -f ./k8s/service.yaml --namespace=web3

#kind-undeploy: @ Undeploy from a local KinD cluster
kind-undeploy:
	@kubectl delete -f ./k8s/deployment.yaml --namespace=web3 --ignore-not-found=true && \
	kubectl delete -f ./k8s/cm.yaml --namespace=web3 --ignore-not-found=true && \
	kubectl delete -f ./k8s/ns.yaml --ignore-not-found=true

#kind-redeploy: @ Redeploy to a local KinD cluster
kind-redeploy:
	@kubectl delete -f ./k8s/deployment.yaml --namespace=web3 --ignore-not-found=true && \
	kubectl apply -f ./k8s/cm.yaml --namespace=web3 && \
	yq eval '.spec.template.spec.containers[0].image = "$(APP_NAME):$(CURRENTTAG)"' ./k8s/deployment.yaml | kubectl apply --namespace=web3 -f -

.PHONY: help deps clean install ci-install build lint format check upgrade run \
	image-build image-build-prod image-run image-stop ci-run release delete-tag \
	kind-deploy kind-undeploy kind-redeploy
