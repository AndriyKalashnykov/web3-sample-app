.DEFAULT_GOAL := help

CURRENTTAG:=$(shell git describe --tags --abbrev=0)
NEWTAG ?= $(shell bash -c 'read -p "Please provide a new tag (currnet tag - ${CURRENTTAG}): " newtag; echo $$newtag')



#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-16s\033[0m - %s\n", $$1, $$2}'

#clean: @ Cleanup
clean:
	@rm -rf node_modules/ dist/

#install: @ Install NodeJS dependencies
install:
	pnpm install

#build: @ Build
build: install
	pnpm build

#upgrade: @ Upgrade dependencies
upgrade:
	pnpm upgrade

#run: @ Run
run: install
	@export VITE_RPCENDPOINT=https://rpc.ankr.com/eth && npm run dev

#image-build: @ Build a Docker image
image-build: install
	docker buildx build --load -t web3-sample-app:$(VERSION) .

#image-build-prod: @ Build a PROD Docker image
image-build-prod: install
	docker buildx build --load -t web3-sample-app:$(VERSION) -f Dockerfile.prod .

#image-run: @ Run a Docker image
image-run:
	@docker run --rm -p 8080:8080 --name web3 web3-sample-app:$(VERSION)
#-e VITE_RPCENDPOINT=https://rpc.ankr.com/eth

#image-stop: @ Stop a Docker image
image-stop:
	@docker stop web3 || true

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