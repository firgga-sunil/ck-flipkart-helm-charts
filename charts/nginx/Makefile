# NGINX Ingress Makefile
# Makefile for deploying NGINX ingress proxy to different environments

# Variables
CHART_NAME := ck-ingress-nginx
RELEASE_NAME := ck-ingress-nginx
NAMESPACE := codekarma

# Internal target for Helm upgrade (not meant to be called directly)
.PHONY: _helm-upgrade
_helm-upgrade:
	@echo "Deploying NGINX ingress with values file: $(VALUES_FILE)"
	helm upgrade --install $(RELEASE_NAME) . \
		--namespace $(NAMESPACE) \
		--values $(VALUES_FILE) \
		--wait \
		--timeout 10m \
		--force \
		$(HELM_ARGS)
	@echo "✓ NGINX ingress deployed successfully"

# Default target
.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'Examples:'
	@echo '  make deploy-gcp-ckqa              # Deploy to GCP CKQA'
	@echo '  make deploy-gcp-demo              # Deploy to GCP demo'
	@echo '  make deploy-gcp-flipkart          # Deploy to GCP Flipkart'
	@echo '  make deploy-aws-prod              # Deploy to AWS production'
	@echo '  make deploy-aws-ckqa              # Deploy to AWS CKQA'
	@echo '  make deploy VALUES_FILE=values-custom.yaml  # Deploy with custom values'
	@echo '  make deploy VALUES_FILE=values-gcp.yaml HELM_ARGS="--set replicaCount=3"  # Deploy with custom values and args'
	@echo '  make restart-pods                 # Force restart pods'

# Check if kubectl context is set to GCP
.PHONY: check-gcp-context
check-gcp-ckqa-context: ## Verify GCP context is set correctly
	@echo "Checking kubectl context..."
	@kubectl config current-context | grep -q "gke_codekarma-auth_us-east1_ck-fk-pg" || (echo "Error: kubectl context is not set to GCP cluster. Expected: gke_codekarma-auth_us-east1_ck-fk-pg" && exit 1)
	@echo "✓ GCP context verified: gke_codekarma-auth_us-east1_ck-fk-pg"

# Deploy to GCP CKQA environment
.PHONY: deploy-gcp-ckqa
deploy-gcp-ckqa: check-gcp-ckqa-context ## Deploy NGINX ingress to GCP CKQA cluster
	@$(MAKE) _helm-upgrade VALUES_FILE=values-gcp-ckqa.yaml

.PHONY: check-gcp-demo
check-gcp-demo: ## Verify GCP demo cluster context is set correctly
	@echo "Checking kubectl context..."
	@kubectl config current-context | grep -q "gke_resounding-node-471205-f9_us-east1_demo-cluster" || (echo "Error: kubectl context is not set to GCP cluster. Expected: gke_resounding-node-471205-f9_us-east1_demo-cluster" && exit 1)
	@echo "✓ GCP context verified: gke_resounding-node-471205-f9_us-east1_demo-cluster"

# Deploy to GCP demo environment
.PHONY: deploy-gcp-demo
deploy-gcp-demo: check-gcp-demo ## Deploy NGINX ingress to GCP demo cluster
	@$(MAKE) _helm-upgrade VALUES_FILE=values-gcp-demo.yaml	

.PHONY: check-gcp-flipkart
check-gcp-flipkart: ## Verify GCP Flipkart cluster context is set correctly
	@echo "Checking kubectl context..."
	@kubectl config current-context | grep -q "gke_fk-code-karma_asia-south1_gke-code-karma-prod-1" || (echo "Error: kubectl context is not set to GCP cluster. Expected: gke_fk-code-karma_asia-south1_gke-code-karma-prod-1" && exit 1)
	@echo "✓ GCP context verified: gke_fk-code-karma_asia-south1_gke-code-karma-prod-1"

# Deploy to GCP Flipkart environment
.PHONY: deploy-gcp-flipkart
deploy-gcp-flipkart: check-gcp-flipkart ## Deploy NGINX ingress to GCP Flipkart cluster
	@$(MAKE) _helm-upgrade VALUES_FILE=values-gcp-flipkart.yaml

# Check if kubectl context is set to AWS
.PHONY: check-aws-prod-context
check-aws-prod-context: ## Verify AWS production context is set correctly
	@echo "Checking kubectl context..."
	@kubectl config current-context | grep -q "arn:aws:eks:ap-south-1:484907483585:cluster/ck-aws-prod" || (echo "Error: kubectl context is not set to AWS prod cluster. Expected context must of aws-prod" && exit 1)
	@echo "✓ AWS context verified"

# Deploy to AWS production environment
.PHONY: deploy-aws-prod
deploy-aws-prod: check-aws-prod-context ## Deploy NGINX ingress to AWS production cluster
	@$(MAKE) _helm-upgrade VALUES_FILE=values-aws-prod.yaml

# Check if kubectl context is set to AWS CKQA
.PHONY: check-aws-ckqa-context
check-aws-ckqa-context: ## Verify AWS CKQA context is set correctly
	@echo "Checking kubectl context..."
	@kubectl config current-context | grep -q "arn:aws:eks:us-east-2:484907483585:cluster/ck-qa" || (echo "Error: kubectl context is not set to AWS ckqa cluster. Expected context must be of aws-ckqa" && exit 1)
	@echo "✓ AWS CKQA context verified"

# Deploy to AWS CKQA environment
.PHONY: deploy-aws-ckqa
deploy-aws-ckqa: check-aws-ckqa-context ## Deploy NGINX ingress to AWS CKQA cluster
	@$(MAKE) _helm-upgrade VALUES_FILE=values-aws-ckqa.yaml

# Deploy to local environment
.PHONY: deploy-local
deploy-local: ## Deploy NGINX ingress to local environment
	@$(MAKE) _helm-upgrade VALUES_FILE=values.yaml

# Generic deploy target (usage: make deploy VALUES_FILE=values-custom.yaml)
.PHONY: deploy
deploy: ## Deploy NGINX ingress with custom values file (usage: make deploy VALUES_FILE=values-custom.yaml)
ifndef VALUES_FILE
	@echo "Error: VALUES_FILE is required. Usage: make deploy VALUES_FILE=values-custom.yaml"
	@exit 1
endif
	@$(MAKE) _helm-upgrade VALUES_FILE=$(VALUES_FILE)

# Uninstall release
.PHONY: uninstall
uninstall: ## Uninstall NGINX ingress release
	@echo "Uninstalling NGINX ingress..."
	helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE)
	@echo "✓ NGINX ingress uninstalled successfully"

# Check status
.PHONY: status
status: ## Check the status of the NGINX ingress deployment
	@echo "Checking NGINX ingress status..."
	helm status $(RELEASE_NAME) --namespace $(NAMESPACE) || echo "Release not found"

# List releases
.PHONY: list
list: ## List all releases in the namespace
	@echo "Listing releases in namespace $(NAMESPACE):"
	helm list --namespace $(NAMESPACE)

# Get values
.PHONY: get-values
get-values: ## Get the current values for the release
	@echo "Getting current values for $(RELEASE_NAME):"
	helm get values $(RELEASE_NAME) --namespace $(NAMESPACE) || echo "Release not found"

# Lint chart
.PHONY: lint
lint: ## Lint the Helm chart
	@echo "Linting Helm chart..."
	helm lint .

# Template chart
.PHONY: template
template: ## Template the Helm chart with GCP values
	@echo "Templating Helm chart with GCP values..."
	helm template $(RELEASE_NAME) . --values values-gcp-ckqa.yaml

# Template chart with AWS values
.PHONY: template-aws
template-aws: ## Template the Helm chart with AWS production values
	@echo "Templating Helm chart with AWS production values..."
	helm template $(RELEASE_NAME) . --values values-aws-prod.yaml

# Clean up
.PHONY: clean
clean: uninstall ## Clean up by uninstalling the release