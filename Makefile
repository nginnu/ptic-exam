ENV ?= prod
export ENV

.PHONY: help check-tools install-cluster delete-cluster

help:
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

check-tools: ## Report tools that are missing from this machine
	@scripts/check-tools.sh

install-cluster: ## Create a cluster: make install-cluster ENV=prod
	@scripts/install-cluster.sh

delete-cluster: ## Delete a cluster: make delete-cluster ENV=prod
	@kind delete cluster --name ptic-$(ENV)-cluster
