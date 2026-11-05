SHELL := /bin/bash

.PHONY: help fmt lint init bootstrap-state tf-prod plan plan-prod deploy-prod \
        check-nodes-prod health-check-prod dump-logs-prod

SANDBOX_DOMAIN := sandbox.islandora.ca
REQUIRED_NODE_IDS ?= 20 50

export SANDBOX_DOMAIN
export PROD_DOMAIN := $(SANDBOX_DOMAIN)
export REQUIRED_NODE_IDS
export TF_VAR_sandbox_domain := $(SANDBOX_DOMAIN)
export TF_VAR_droplet_size ?= s-4vcpu-8gb-amd

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%s\033[0m\t%s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort | column -t -s $$'\t'

fmt: ## Format Terraform files
	terraform fmt -recursive

lint: ## Check Terraform formatting and shell scripts
	terraform fmt -check -recursive
	TF_DATA_DIR=.terraform-lint terraform init -backend=false
	TF_DATA_DIR=.terraform-lint terraform validate
	terraform -chdir=bootstrap init
	terraform -chdir=bootstrap validate
	find . -name '*.sh' -print0 | xargs -0 shellcheck
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s ci -p 'test_*.py'

init: ## Initialize Terraform with the configured remote backend
	terraform init -upgrade

bootstrap-state: ## Create the Terraform state Space with the no-backend bootstrap root
	SPACES_ACCESS_KEY_ID="$$AWS_ACCESS_KEY_ID" SPACES_SECRET_ACCESS_KEY="$$AWS_SECRET_ACCESS_KEY" terraform -chdir=bootstrap init -upgrade
	SPACES_ACCESS_KEY_ID="$$AWS_ACCESS_KEY_ID" SPACES_SECRET_ACCESS_KEY="$$AWS_SECRET_ACCESS_KEY" terraform -chdir=bootstrap apply -auto-approve

tf-prod: ## Run Terraform for sandbox/prod. Usage: make tf-prod ACTION=plan|apply
	@ci/deploy-local.sh prod "$${ACTION:-plan}"

plan-prod: ## Plan the sandbox workspace
	$(MAKE) tf-prod ACTION=plan

plan: plan-prod ## Plan the sandbox workspace

deploy-prod: ## Apply and validate sandbox
	$(MAKE) tf-prod ACTION=apply

check-nodes-prod: ## Validate required Drupal nodes on sandbox/prod
	ci/check-nodes.sh "https://$(SANDBOX_DOMAIN)"

health-check-prod: ## Wait for sandbox/prod to become healthy
	ci/health-check.sh "https://$(SANDBOX_DOMAIN)"

dump-logs-prod: ## Dump logs from the sandbox/prod host
	ci/dump-logs.sh "$(SANDBOX_DOMAIN)"
