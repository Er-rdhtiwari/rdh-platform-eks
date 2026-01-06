SHELL := /bin/bash
ENV ?= dev
AWS_REGION ?= ap-south-1
TF_DIR ?= terraform/env

# Auto-load .env if present so TF_VAR_* and AWS settings are available
ifneq (,$(wildcard .env))
include .env
export $(shell sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' .env)
endif

TF_VAR_node_instance_types ?= $(NODE_INSTANCE_TYPES)
TF_VAR_node_min_size ?= $(NODE_MIN_SIZE)
TF_VAR_node_desired_size ?= $(NODE_DESIRED_SIZE)
TF_VAR_node_max_size ?= $(NODE_MAX_SIZE)
TF_VAR_EXPORTS = \
  TF_VAR_node_instance_types='$(TF_VAR_node_instance_types)' \
  TF_VAR_node_min_size='$(TF_VAR_node_min_size)' \
  TF_VAR_node_desired_size='$(TF_VAR_node_desired_size)' \
  TF_VAR_node_max_size='$(TF_VAR_node_max_size)'

TF_DIR ?= terraform/env
BOOTSTRAP_DIR ?= terraform/bootstrap
BACKEND_FILE ?= backend.hcl
TFVARS_FILE ?= $(ENV).tfvars
PLAN_FILE ?= terraform.plan

.PHONY: bootstrap-init bootstrap-apply fmt validate tf-init plan apply destroy kubeconfig addons status

bootstrap-init:
	terraform -chdir=$(BOOTSTRAP_DIR) init

bootstrap-apply:
	terraform -chdir=$(BOOTSTRAP_DIR) apply -auto-approve

fmt:
	terraform -chdir=$(TF_DIR) fmt

validate: tf-init
	terraform -chdir=$(TF_DIR) validate

# Initializes env Terraform using backend.hcl generated per environment.
tf-init:
	@test -f $(TF_DIR)/$(BACKEND_FILE) || (echo "Missing $(TF_DIR)/$(BACKEND_FILE). Copy backend.hcl.example and set bucket/table/key." && exit 1)
	terraform -chdir=$(TF_DIR) init -backend-config=$(BACKEND_FILE)

plan: tf-init
	@test -f $(TF_DIR)/$(TFVARS_FILE) || (echo "Missing $(TF_DIR)/$(TFVARS_FILE). Copy terraform.tfvars.example to $(TF_DIR)/$(TFVARS_FILE)." && exit 1)
	$(TF_VAR_EXPORTS) terraform -chdir=$(TF_DIR) plan -var-file=$(TFVARS_FILE) -out=$(PLAN_FILE)

apply: tf-init
	@test -f $(TF_DIR)/$(TFVARS_FILE) || (echo "Missing $(TF_DIR)/$(TFVARS_FILE). Copy terraform.tfvars.example to $(TF_DIR)/$(TFVARS_FILE)." && exit 1)
	$(TF_VAR_EXPORTS) terraform -chdir=$(TF_DIR) apply $(if $(AUTO_APPROVE),-auto-approve,) -var-file=$(TFVARS_FILE)

# Destroys all env resources; requires explicit confirmation.
destroy: tf-init
	@test -f $(TF_DIR)/$(TFVARS_FILE) || (echo "Missing $(TF_DIR)/$(TFVARS_FILE). Copy terraform.tfvars.example to $(TF_DIR)/$(TFVARS_FILE)." && exit 1)
	$(TF_VAR_EXPORTS) terraform -chdir=$(TF_DIR) destroy $(if $(AUTO_APPROVE),-auto-approve,) -var-file=$(TFVARS_FILE)

kubeconfig:
	@CLUSTER_NAME=$(shell terraform -chdir=$(TF_DIR) output -raw cluster_name); \
	if [ -z "$$CLUSTER_NAME" ]; then echo "cluster_name output not found; ensure Terraform applied." && exit 1; fi; \
	echo "Updating kubeconfig for $$CLUSTER_NAME in $(AWS_REGION)"; \
	aws eks update-kubeconfig --region $(AWS_REGION) --name $$CLUSTER_NAME --alias $$CLUSTER_NAME

addons:
	@ACTION=$${ACTION:-install}; ./scripts/manage_addons.sh $$ACTION

status:
	./scripts/verify_cluster.sh
