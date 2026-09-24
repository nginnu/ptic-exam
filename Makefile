ENV ?= prod
export ENV

.PHONY: help check-tools install-cluster delete-cluster install-argocd build validate validate-manifests validate-cluster validate-gitops validate-storage validate-database validate-backup validate-apps validate-routes validate-ingress

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

validate-ingress: ## Validate mesh security, metrics and access logs
	@scripts/validate.sh ingress

validate-storage: ## Validate the object store with a round trip
	@scripts/validate.sh storage

validate-database: ## Validate postgres and its replica
	@scripts/validate.sh database

validate-backup: ## Validate postgres backups reach the object store
	@scripts/validate.sh backup

validate-manifests: ## Validate that every overlay builds
	@scripts/validate.sh manifests

validate-apps: ## Validate the api and the web page
	@scripts/validate.sh apps

validate-routes: ## Validate the routes through the gateway
	@scripts/validate.sh routes
