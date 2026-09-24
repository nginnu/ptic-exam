ENV ?= prod
export ENV

.PHONY: help check-tools install-cluster delete-cluster install-argocd build validate validate-cluster validate-gitops

help:
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

check-tools: ## Report tools that are missing from this machine
	@scripts/check-tools.sh

install-cluster: ## Create a cluster: make install-cluster ENV=prod
	@scripts/install-cluster.sh

delete-cluster: ## Delete a cluster: make delete-cluster ENV=prod
	@kind delete cluster --name ptic-$(ENV)-cluster

install-argocd: ## Install Argo CD and apply the root application
	@scripts/install-argocd.sh

build: ## Render every overlay; needs no cluster
	@scripts/build.sh

validate: ## Check that what is installed actually works
	@scripts/validate.sh

validate-cluster: ## Validate node counts, etcd and taints
	@scripts/validate.sh cluster

validate-gitops: ## Validate Argo CD and its applications
	@scripts/validate.sh gitops
