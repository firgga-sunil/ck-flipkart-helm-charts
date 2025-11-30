# GCP Gateway API Makefile
# Makefile for deploying GCP Gateway API with SSL certificates

# Variables
CHART_NAME := ck-gcp-gateway
RELEASE_NAME := ck-gcp-gateway
NAMESPACE := codekarma

# Default target
.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Check if namespace exists, create if not
.PHONY: check-namespace
check-namespace: ## Check if codekarma namespace exists, create if not
	@echo "Checking namespace $(NAMESPACE)..."
	@kubectl get namespace $(NAMESPACE) >/dev/null 2>&1 || (echo "Creating namespace $(NAMESPACE)..." && kubectl create namespace $(NAMESPACE))
	@echo "✓ Namespace $(NAMESPACE) is ready"

# Check if nginx service exists
.PHONY: check-nginx
check-nginx: ## Check if nginx service exists in codekarma namespace
	@echo "Checking nginx service..."
	@kubectl get service ck-ingress-nginx -n $(NAMESPACE) >/dev/null 2>&1 || (echo "Error: nginx service 'ck-ingress-nginx' not found in namespace $(NAMESPACE). Please deploy nginx first: helm install ck-nginx ../nginx" && exit 1)
	@echo "✓ Nginx service found"

# Check if required CRDs are installed
.PHONY: check-crds
check-crds: ## Check if required CRDs (Gateway, HTTPRoute, GCPGatewayPolicy) are installed
	@echo "Checking required CRDs..."
	@MISSING_CRDS="" && \
	if ! kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then \
		MISSING_CRDS="$$MISSING_CRDS Gateway"; \
	fi && \
	if ! kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then \
		MISSING_CRDS="$$MISSING_CRDS HTTPRoute"; \
	fi && \
	if ! kubectl get crd gcpgatewaypolicies.networking.gke.io >/dev/null 2>&1; then \
		MISSING_CRDS="$$MISSING_CRDS GCPGatewayPolicy"; \
	fi && \
	if [ -n "$$MISSING_CRDS" ]; then \
		echo ""; \
		echo "❌ Error: Required CRDs are missing:$$MISSING_CRDS"; \
		echo ""; \
		echo "Gateway API needs to be enabled on your GKE cluster."; \
		echo ""; \
		echo "To enable Gateway API, you can:"; \
		echo "  1. Enable via GCP Console UI:"; \
		echo "     - Go to GKE → Your Cluster → Features"; \
		echo "     - Enable 'Gateway API' feature"; \
		echo ""; \
		echo "  2. Request project/cluster owners to enable it"; \
		echo ""; \
		echo "  3. Enable manually using gcloud (if you have permissions):"; \
		echo "     gcloud container clusters update <CLUSTER_NAME> --gateway-api=standard --region=<REGION> --project=<PROJECT>"; \
		echo ""; \
		exit 1; \
	else \
		echo "✓ All required CRDs are installed"; \
	fi

# Check if kubectl context is set to GCP flipkart
.PHONY: check-gcp-flipkart-context
check-gcp-flipkart-context: ## Verify GCP flipkart cluster context is set correctly
	@echo "Checking kubectl context..."
	@kubectl config current-context | grep -q "gke_fk-code-karma_asia-south1_gke-code-karma-prod-1" || (echo "Error: kubectl context is not set to GCP flipkart cluster. Expected: gke_fk-code-karma_asia-south1_gke-code-karma-prod-1" && exit 1)
	@echo "✓ GCP flipkart context verified: gke_fk-code-karma_asia-south1_gke-code-karma-prod-1"

# Deploy to GCP flipkart environment
.PHONY: deploy-gcp-flipkart
deploy-gcp-flipkart: check-gcp-flipkart-context check-crds check-namespace check-nginx ## Deploy GCP Gateway to GCP flipkart cluster
	@echo "Deploying GCP Gateway to GCP flipkart cluster..."
	@echo "Note: Using --force flag to ensure upgrade if gateway already exists..."
	helm upgrade --install $(RELEASE_NAME) . \
		--namespace $(NAMESPACE) \
		--values values-gcp-flipkart.yaml \
		--force \
		--wait \
		--timeout 15m
	@echo "✓ GCP Gateway deployed successfully to GCP flipkart"
	@echo "Waiting for external IP assignment..."
	@make get-ip-gcp-flipkart

# Uninstall release
.PHONY: uninstall
uninstall: ## Uninstall GCP Gateway release
	@echo "Uninstalling GCP Gateway..."
	helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE) || echo "Release not found or already uninstalled"
	@echo "✓ GCP Gateway uninstalled successfully"

# Check status
.PHONY: status
status: ## Check the status of the GCP Gateway deployment
	@echo "Checking GCP Gateway status..."
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
template: ## Template the Helm chart with default values
	@echo "Templating Helm chart with default values..."
	helm template $(RELEASE_NAME) . --values values.yaml

# Template chart - flipkart
.PHONY: template-gcp-flipkart
template-gcp-flipkart: ## Template the Helm chart with GCP flipkart values
	@echo "Templating Helm chart with GCP flipkart values..."
	helm template $(RELEASE_NAME) . --values values-gcp-flipkart.yaml

# Generic get load balancer IP (takes GATEWAY_NAME as parameter)
# Usage: make get-ip GATEWAY_NAME=ck-gateway-gcp-flipkart
.PHONY: get-ip
get-ip: ## Get the external IP address of the load balancer (requires GATEWAY_NAME parameter)
	@if [ -z "$(GATEWAY_NAME)" ]; then \
		echo "Error: GATEWAY_NAME parameter is required"; \
		echo "Usage: make get-ip GATEWAY_NAME=<gateway-name>"; \
		exit 1; \
	fi
	@echo "Getting external IP address for $(GATEWAY_NAME)..."
	@kubectl get gateway $(GATEWAY_NAME) -n $(NAMESPACE) -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "IP not yet assigned - gateway may still be provisioning"

# Get load balancer IP - flipkart
.PHONY: get-ip-gcp-flipkart
get-ip-gcp-flipkart: ## Get the external IP address of the load balancer for flipkart
	@$(MAKE) get-ip GATEWAY_NAME=ck-gateway-gcp-flipkart

# Generic check gateway status (takes GATEWAY_NAME as parameter)
# Usage: make check-gateway GATEWAY_NAME=ck-gateway-gcp-flipkart
.PHONY: check-gateway
check-gateway: ## Check the status of a gateway (requires GATEWAY_NAME parameter)
	@if [ -z "$(GATEWAY_NAME)" ]; then \
		echo "Error: GATEWAY_NAME parameter is required"; \
		echo "Usage: make check-gateway GATEWAY_NAME=<gateway-name>"; \
		exit 1; \
	fi
	@echo "Checking gateway status for $(GATEWAY_NAME)..."
	@echo "=== Gateway Resource ==="
	@kubectl get gateway $(GATEWAY_NAME) -n $(NAMESPACE) -o wide
	@echo ""
	@echo "=== Gateway Conditions ==="
	@kubectl get gateway $(GATEWAY_NAME) -n $(NAMESPACE) -o jsonpath='{range .status.conditions[*]}{.type}={.status} ({.reason}) - {.message}{"\n"}{end}' 2>/dev/null || echo "No conditions found"
	@echo ""
	@echo "=== Gateway Address ==="
	@kubectl get gateway $(GATEWAY_NAME) -n $(NAMESPACE) -o jsonpath='{.status.addresses[*].value}' 2>/dev/null && echo "" || echo "No address assigned yet"
	@echo ""
	@echo "=== Recent Events (last 5) ==="
	@kubectl get events -n $(NAMESPACE) --field-selector involvedObject.name=$(GATEWAY_NAME) --sort-by='.lastTimestamp' -o custom-columns=LAST-SEEN:.lastTimestamp,TYPE:.type,REASON:.reason,MESSAGE:.message 2>/dev/null | tail -6 || echo "No events found"

# Check gateway status - flipkart
.PHONY: check-gateway-gcp-flipkart
check-gateway-gcp-flipkart: ## Check the status of the gateway for flipkart
	@$(MAKE) check-gateway GATEWAY_NAME=ck-gateway-gcp-flipkart

# Check HTTPRoute status
.PHONY: check-httproute
check-httproute: ## Check the status of the HTTPRoute
	@echo "Checking HTTPRoute status..."
	@echo "=== HTTPRoute Resources ==="
	@kubectl get httproute -n $(NAMESPACE) -o wide
	@echo ""
	@echo "=== HTTPRoute Conditions ==="
	@for route in $$(kubectl get httproute -n $(NAMESPACE) -o jsonpath='{.items[*].metadata.name}'); do \
		echo "--- $$route ---"; \
		kubectl get httproute $$route -n $(NAMESPACE) -o jsonpath='{range .status.conditions[*]}{.type}={.status} ({.reason}) - {.message}{"\n"}{end}' 2>/dev/null || echo "No conditions found"; \
		echo ""; \
	done

# Check GCP Gateway Policy status
.PHONY: check-gateway-policy
check-gateway-policy: ## Check the status of the GCP Gateway Policy
	@echo "Checking GCP Gateway Policy status..."
	@kubectl get gcpgatewaypolicy -n $(NAMESPACE) -o wide

# Check SSL certificate status
.PHONY: check-ssl
check-ssl: ## Check the status of SSL certificates
	@echo "Checking SSL certificate status..."
	@echo "Note: SSL certificates are configured via cert-manager. Check cert-manager resources:"
	@kubectl get certificaterequest -n $(NAMESPACE)
	@kubectl get certificate -n $(NAMESPACE)

# Generic check all resources (takes GATEWAY_NAME as parameter)
# Usage: make check-all GATEWAY_NAME=ck-gateway-gcp-flipkart
.PHONY: check-all
check-all: ## Check all GCP Gateway resources (requires GATEWAY_NAME parameter)
	@if [ -z "$(GATEWAY_NAME)" ]; then \
		echo "Error: GATEWAY_NAME parameter is required"; \
		echo "Usage: make check-all GATEWAY_NAME=<gateway-name>"; \
		exit 1; \
	fi
	@echo "Checking all GCP Gateway resources for $(GATEWAY_NAME)..."
	@echo ""
	@$(MAKE) check-gateway GATEWAY_NAME=$(GATEWAY_NAME)
	@echo ""
	@echo "=== HTTPRoute ==="
	@$(MAKE) check-httproute
	@echo ""
	@echo "=== GCP Gateway Policy ==="
	@$(MAKE) check-gateway-policy
	@echo ""
	@echo "=== Diagnostic Summary ==="
	@echo "Checking for common issues..."
	@PROGRAMMED=$$(kubectl get gateway $(GATEWAY_NAME) -n $(NAMESPACE) -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null); \
	if [ "$$PROGRAMMED" != "True" ]; then \
		echo "⚠️  WARNING: Gateway is not Programmed. Check conditions above for details."; \
		REASON=$$(kubectl get gateway $(GATEWAY_NAME) -n $(NAMESPACE) -o jsonpath='{.status.conditions[?(@.type=="Programmed")].reason}' 2>/dev/null); \
		MSG=$$(kubectl get gateway $(GATEWAY_NAME) -n $(NAMESPACE) -o jsonpath='{.status.conditions[?(@.type=="Programmed")].message}' 2>/dev/null); \
		echo "   Reason: $$REASON"; \
		echo "   Message: $$MSG"; \
		if echo "$$MSG" | grep -q "address.*purpose"; then \
			echo ""; \
			echo "   💡 FIX: The static IP address needs to be recreated with purpose=SHARED_LOADBALANCER_VIP"; \
			echo "   Current address: $$(kubectl get gateway $(GATEWAY_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.addresses[0].value}' 2>/dev/null)"; \
			echo "   Contact GCP admin to recreate the address or use a different named address."; \
		fi; \
		if echo "$$MSG" | grep -q "RequestRedirect.*Port"; then \
			echo ""; \
			echo "   💡 FIX: Remove port from RequestRedirect filter in HTTPRoute"; \
			echo "   This should be fixed in the template. Redeploy after fixing."; \
		fi; \
	fi; \
	ADDR=$$(kubectl get gateway $(GATEWAY_NAME) -n $(NAMESPACE) -o jsonpath='{.status.addresses[0].value}' 2>/dev/null); \
	if [ -z "$$ADDR" ]; then \
		echo "⚠️  WARNING: No external IP assigned yet. Gateway may still be provisioning."; \
	else \
		echo "✓ External IP: $$ADDR"; \
	fi

# Check all resources - flipkart
.PHONY: check-all-gcp-flipkart
check-all-gcp-flipkart: ## Check all GCP Gateway resources for flipkart
	@$(MAKE) check-all GATEWAY_NAME=ck-gateway-gcp-flipkart

# Test endpoints
.PHONY: test
test: ## Test the deployed endpoints
	@echo "Testing endpoints..."
	@if [ -f test-endpoints.sh ]; then \
		./test-endpoints.sh; \
	else \
		echo "test-endpoints.sh not found. Please create it or use manual testing."; \
	fi

# Deploy and test - flipkart
.PHONY: deploy-test-gcp-flipkart
deploy-test-gcp-flipkart: deploy-gcp-flipkart test ## Deploy GCP Gateway to flipkart and test endpoints

# Show deployment info - flipkart
.PHONY: info-gcp-flipkart
info-gcp-flipkart: ## Show deployment information and next steps for flipkart
	@echo "=== GCP Gateway Deployment Information (Flipkart) ==="
	@echo "Release Name: $(RELEASE_NAME)"
	@echo "Namespace: $(NAMESPACE)"
	@echo ""
	@echo "=== Next Steps ==="
	@echo "1. Wait for external IP assignment: make get-ip-gcp-flipkart"
	@echo "2. Update DNS records to point to the external IP"
	@echo "3. Verify SSL certificate is properly configured via cert-manager"
	@echo "4. Test endpoints: make test"
	@echo ""
	@echo "=== DNS Records to Update ==="
	@echo "- codekarma.fkcloud.in → [External IP]"

# Clean up
.PHONY: clean
clean: uninstall ## Clean up by uninstalling the release
