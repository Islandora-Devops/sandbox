SHELL := /bin/bash

.PHONY: help fmt lint init bootstrap-state tf-test tf-prod plan plan-test plan-prod \
        review-pr promote-sandbox deploy-test deploy-prod \
        cleanup-test destroy-test delete-test-workspace snapshot-test review-json-test \
        check-nodes-test check-nodes-prod health-check-test health-check-prod \
        dump-logs-test dump-logs-prod

TEST_DOMAIN := test.islandora.ca
SANDBOX_DOMAIN := sandbox.islandora.ca
REQUIRED_NODE_IDS ?= 20 50

export TEST_DOMAIN
export SANDBOX_DOMAIN
export PROD_DOMAIN := $(SANDBOX_DOMAIN)
export REQUIRED_NODE_IDS
export TF_VAR_test_domain := $(TEST_DOMAIN)
export TF_VAR_sandbox_domain := $(SANDBOX_DOMAIN)
export TF_VAR_droplet_size := s-4vcpu-8gb-amd
export DIGITALOCEAN_CANDIDATE_REGIONS ?= tor1 nyc3 sfo3
export TF_VAR_ssh_keys := ["ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC92mfUd/zMuzWqAod/xuqrE2to4ae1cRiknK81uMHfVHpXoxx2xM7PkmMsO9ShQtWsu0V0q4A9kozzv22HVDL51iVapESrM4q2KWiDHnE45U8RH/DDRX5NdW3+GvNQk2ITyHR4CVpvwYXCYfI4bha4R4jF7oc7pDmLcgcYN+9OSptUnWUbxqiWqfuwWSmux9N1HHiVDTt/2W8qgszAzwXI64ooK5pkU7KSXQ9A/w4Ra/xmZioCKAB4MZh5HIwNoVgZ8OCXLBL66cQTJEQnmkCc3rVeHikBhvUxCnKWGmdjcBG/XGxqHIQ1HVn7GSlclJ8hGISZZcBaB4RVFCUK4i8tvKbM1dHNyNnZGAWJUCMQDH8Dkx8wnOAWdq4ed1cd16Jt3y4cEcHEUSXmZmViYMNHbqqL+yaj3nhCDIwa7CzoVLZ4Vj8xOvn/X2JMaLPhJFY//5Y6Dep01Nm+4d0Xf4gYo3H6Hmo/jBeXO/VRPHKbbZIMlA04mrlClosgUqkm+cE=","ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHZds7DX1z9IN0T7H/yXZrUIlOHiPzqK9oWN8brKh06e jjc223@Mac"]

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%s\033[0m\t%s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort | column -t -s $$'\t'

fmt: ## Format Terraform files
	terraform fmt -recursive

lint: ## Check Terraform formatting and shell scripts
	terraform fmt -check -recursive
	terraform init -backend=false
	terraform validate
	terraform -chdir=bootstrap init
	terraform -chdir=bootstrap validate
	find . -name '*.sh' -print0 | xargs -0 shellcheck

init: ## Initialize Terraform with the configured remote backend
	terraform init -upgrade

bootstrap-state: ## Create the Terraform state Space with the no-backend bootstrap root
	SPACES_ACCESS_KEY_ID="$$AWS_ACCESS_KEY_ID" SPACES_SECRET_ACCESS_KEY="$$AWS_SECRET_ACCESS_KEY" terraform -chdir=bootstrap init -upgrade
	SPACES_ACCESS_KEY_ID="$$AWS_ACCESS_KEY_ID" SPACES_SECRET_ACCESS_KEY="$$AWS_SECRET_ACCESS_KEY" terraform -chdir=bootstrap apply -auto-approve

tf-test: ## Run Terraform for test. Usage: make tf-test ACTION=plan|apply|cleanup|destroy
	@ci/deploy-local.sh test "$${ACTION:-plan}"

tf-prod: ## Run Terraform for sandbox/prod. Usage: make tf-prod ACTION=plan|apply|destroy
	@ci/deploy-local.sh prod "$${ACTION:-plan}"

plan-test: ## Plan the test workspace
	$(MAKE) tf-test ACTION=plan

plan-prod: ## Plan the sandbox/prod workspace
	$(MAKE) tf-prod ACTION=plan

plan: plan-test plan-prod ## Plan both test and sandbox/prod workspaces

review-pr: ## Compatibility target: apply and validate test
	$(MAKE) tf-test ACTION=apply

promote-sandbox: ## Apply test, apply sandbox/prod, then clean up test compute
	$(MAKE) tf-test ACTION=apply
	$(MAKE) tf-prod ACTION=apply
	$(MAKE) tf-test ACTION=cleanup

deploy-test: ## Apply and validate test
	$(MAKE) tf-test ACTION=apply

deploy-prod: ## Apply and validate sandbox/prod
	$(MAKE) tf-prod ACTION=apply

cleanup-test: ## Destroy only ephemeral test compute; keep test DNS and reserved IP
	$(MAKE) tf-test ACTION=cleanup

destroy-test: ## Destroy the entire test workspace, including DNS and reserved IP
	$(MAKE) tf-test ACTION=destroy

delete-test-workspace: ## Delete the test Terraform workspace
	ci/delete-workspace.sh test

snapshot-test: ## Capture a screenshot of test.islandora.ca
	ci/screenshot.sh "https://$(TEST_DOMAIN)" artifacts/test-islandora-ca.png

review-json-test: ## Fetch JSON-LD from the test review node
	ci/fetch-json.sh "https://$(TEST_DOMAIN)/node/20?_format=jsonld" artifacts/test-node-20.json

check-nodes-test: ## Validate required Drupal nodes on test
	ci/check-nodes.sh "https://$(TEST_DOMAIN)"

check-nodes-prod: ## Validate required Drupal nodes on sandbox/prod
	ci/check-nodes.sh "https://$(SANDBOX_DOMAIN)"

health-check-test: ## Wait for test to become healthy
	ci/health-check.sh "https://$(TEST_DOMAIN)"

health-check-prod: ## Wait for sandbox/prod to become healthy
	ci/health-check.sh "https://$(SANDBOX_DOMAIN)"

dump-logs-test: ## Dump logs from the test host
	ci/dump-logs.sh "$(TEST_DOMAIN)"

dump-logs-prod: ## Dump logs from the sandbox/prod host
	ci/dump-logs.sh "$(SANDBOX_DOMAIN)"
