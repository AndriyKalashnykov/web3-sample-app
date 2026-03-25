.DEFAULT_GOAL := help

CURRENTTAG:=$(shell git describe --tags --abbrev=0)
NEWTAG ?= $(shell bash -c 'read -p "Please provide a new tag (currnet tag - ${CURRENTTAG}): " newtag; echo $$newtag')

ACT_VERSION := 0.2.74

#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-16s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install prerequisite tools (act, pnpm, etc.)
deps:
	@command -v act >/dev/null 2>&1 || { \
		echo "Installing act $(ACT_VERSION)..."; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- -b /usr/local/bin v$(ACT_VERSION); \
	}
	@command -v pnpm >/dev/null 2>&1 || { \
		echo "Installing pnpm..."; \
		npm install -g pnpm; \
	}
	@command -v node >/dev/null 2>&1 || { \
		echo "Error: node is not installed. Please install Node.js >= 22"; \
		exit 1; \
	}
	@echo "All dependencies are available."

#clean: @ Cleanup
clean:
	@rm -rf node_modules/ dist/

#install: @ Install NodeJS dependencies
install:
	pnpm install

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

#upgrade: @ Upgrade dependencies
upgrade:
	pnpm upgrade

#run: @ Run
run: install
	@export VITE_RPCENDPOINT=https://rpc.ankr.com/eth && npm run dev

#image-build: @ Build a Docker image
image-build: install
	docker buildx build --load -t web3-sample-app:$(CURRENTTAG) .

#image-build-prod: @ Build a PROD Docker image
image-build-prod: install
	docker buildx build --load -t web3-sample-app:$(CURRENTTAG) -f Dockerfile.prod .

#image-run: @ Run a Docker image
image-run: image-stop
	@docker run --rm -p 8080:8080 --name web3 web3-sample-app:$(CURRENTTAG)

#image-stop: @ Stop a Docker image
image-stop:
	@docker stop web3 || true

#ci-run: @ Run GitHub workflow locally using act
ci-run: deps
	act -j build --container-architecture linux/amd64

#check-version: @ Ensure VERSION variable is set
check-version:
ifndef VERSION
	$(error VERSION is undefined)
endif
	@echo -n ""

release: ## create and push a new tag
	$(eval NT=$(NEWTAG))
	@echo -n "Are you sure to create and push ${NT} tag? [y/N] " && read ans && [ $${ans:-N} = y ]
	@echo ${NT} > ./version.txt
	@git add -A
	@git commit -a -s -m "Cut ${NT} release"
	@git tag ${NT}
	@git push origin ${NT}
	@git push
	@echo "Done."

#kind-deploy: @ Deploy to a local KinD cluster
kind-deploy: image-build
	@kind load docker-image web3-sample-app:$(VERSION) -n kind && \
	cat ./k8s/ns.yaml | kubectl apply -f - && \
	cat ./k8s/cm.yaml | kubectl apply --namespace=web3 -f - && \
	yq eval '.spec.template.spec.containers[0].image = "web3-sample-app:$(VERSION)"' ./k8s/deployment.yaml | kubectl apply --namespace=web3 -f - && \
	cat ./k8s/service.yaml | kubectl apply --namespace=web3 -f -

#kind-undeploy: @ Undeploy from a local KinD cluster
kind-undeploy:
	@kubectl delete -f ./k8s/deployment.yaml --namespace=web3 --ignore-not-found=true && \
	kubectl delete -f ./k8s/cm.yaml --namespace=web3 --ignore-not-found=true && \
	kubectl delete -f ./k8s/ns.yaml --ignore-not-found=true

#kind-redeploy: @ Redeploy to a local KinD cluster
kind-redeploy:
	@kubectl delete -f ./k8s/deployment.yaml --namespace=web3 --ignore-not-found=true && \
	kubectl apply -f ./k8s/cm.yaml --namespace=web3 && \
	yq eval '.spec.template.spec.containers[0].image = "web3-sample-app:$(VERSION)"' ./k8s/deployment.yaml | kubectl apply --namespace=web3 -f -

# ssh into pod
# kubectl exec --stdin --tty -n web3 web3-sample-app-569598dd94-qvg4m -- /bin/sh

# pod logs
# kubectl logs -n web3 web3-sample-app-569598dd94-qvg4m

dt: ## delete tag
	rm -f version.txt
	git push --delete origin v0.0.1
	git tag --delete v0.0.1
