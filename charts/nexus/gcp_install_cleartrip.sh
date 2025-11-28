#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to check if kubectl is installed
check_kubectl() {
  if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
  fi
}

# Function to check if helm is installed
check_helm() {
  if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed or not in PATH"
    exit 1
  fi
}

# Function to check if current context is the required GKE cluster
check_gcp_context() {
  current_context=$(kubectl config current-context)
  required_context="gke_codekarma-auth_us-east1_cleartrip-cluster"
  
  if [ "$current_context" != "$required_context" ]; then
    echo "Error: Current kubectl context is '$current_context', not '$required_context'"
    echo "Please switch to the GCP GKE context with: kubectl config use-context $required_context"
    exit 1
  else
    echo "✅ Current kubectl context is $required_context"
  fi
}

# Function to create namespace if it doesn't exist
create_namespace() {
  if kubectl get namespace codekarma &> /dev/null; then
    echo "✅ Namespace 'codekarma' already exists"
  else
    echo "Creating namespace 'codekarma'..."
    kubectl create namespace codekarma
    echo "✅ Namespace 'codekarma' created successfully"
  fi
}

# Function to check and create required storage class
setup_storage() {
  echo "🔧 Setting up required storage resources..."
  
  # Check if storage class exists
  if kubectl get storageclass gcp-storageclass-sdd &> /dev/null; then
    echo "✅ Storage class 'gcp-storageclass-sdd' already exists"
  else
    echo "Creating storage class 'gcp-storageclass-sdd'..."
    kubectl apply -f db/postgres/storage/gcp-storageclass-pvc-sdd.yaml
    echo "✅ Storage class created successfully"
  fi
  
  echo "✅ Storage setup completed successfully"
}

# Function to install Prometheus
install_prometheus() {
  echo "Installing Prometheus on GCP GKE for Cleartrip..."
  
  # Ensure storage is set up first
  setup_storage
  
  # Add prometheus-community repo if not already added
  if ! helm repo list | grep -q "prometheus-community"; then
    echo "Adding prometheus-community helm repo..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
  fi
  
  # Check if Prometheus is already installed
  if helm list -n codekarma | grep -q "ckp"; then
    echo "✅ Prometheus is already installed"
  else
    # Install Prometheus with GCP Cleartrip-specific values
    echo "Installing Prometheus using Helm with GCP Cleartrip configuration..."
    helm install ckp prometheus-community/kube-prometheus-stack -f ./prometheus/values-gcp-cleartrip.yaml -n codekarma --timeout 10m0s
    
    echo "✅ Prometheus installed successfully on GCP for Cleartrip"
  fi
}

# Function to setup RBAC permissions
setup_rbac() {
  echo "🔧 Setting up RBAC permissions for secret management..."
  
  # Try to get current user from gcloud
  current_user=$(gcloud config get-value account 2>/dev/null || echo "")
  
  if [ -n "$current_user" ]; then
    echo "Using GCP account: $current_user"
    # Update the RBAC file with the current user
    sed -i.bak "s/103167129461246237511/$current_user/g" db/postgres/rbac.yaml
  else
    echo "⚠️  Could not determine current user. You may need to run: gcloud auth login"
    echo "Continuing with default user ID..."
  fi
  
  # Apply RBAC permissions
  echo "Applying RBAC permissions..."
  kubectl apply -f db/postgres/rbac.yaml
  
  echo "✅ RBAC permissions set up successfully"
}

# Function to install Nexus DB (PostgreSQL)
install_nexus_db() {
  echo "Installing Nexus DB (PostgreSQL) on GCP GKE for Cleartrip..."
  
  # Ensure storage is set up first
  setup_storage
  
  # Setup RBAC permissions
  setup_rbac
  
  # Check if Nexus DB is already installed
  if helm list -n codekarma | grep -q "ck-postgres"; then
    echo "✅ Nexus DB (PostgreSQL) is already installed"
  else
    # Install PostgreSQL with GCP Cleartrip-specific values
    echo "Installing PostgreSQL using Helm with GCP Cleartrip configuration..."
    helm install ck-postgres ./db/postgres -f db/postgres/values-gcp-cleartrip.yaml -n codekarma
    
    echo "✅ Nexus DB (PostgreSQL) installed successfully on GCP for Cleartrip"
  fi
}

# Function to build and deploy Nexus application for GCP Cleartrip
build_and_deploy_nexus() {
  echo "Building and deploying Nexus application for GCP Cleartrip..."
  cd ../
  
  # Check if Makefile exists and has the required target
  if [ -f "Makefile" ]; then
    if grep -q "deploy-gcp-cleartrip" Makefile; then
      echo "Using Makefile target: deploy-gcp-cleartrip"
      make deploy-gcp-cleartrip
    else
      echo "Makefile target 'deploy-gcp-cleartrip' not found, using manual deployment..."
      # Manual deployment using Helm
      helm install ck-nexus ./charts/ck-nexus-charts -f ./charts/ck-nexus-charts/values-gcp-cleartrip.yaml -n codekarma
    fi
  else
    echo "Makefile not found, using manual deployment..."
    # Manual deployment using Helm
    helm install ck-nexus ./charts/ck-nexus-charts -f ./charts/ck-nexus-charts/values-gcp-cleartrip.yaml -n codekarma
  fi
  
  cd charts
  echo "✅ Nexus application deployed successfully for GCP Cleartrip"
}

# Function to wait for pods to be ready
wait_for_pods() {
  echo "Waiting for all pods to be ready..."
  
  echo "Waiting for PostgreSQL pod..."
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n codekarma --timeout=300s || true
  
  echo "Waiting for Prometheus pod..."
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n codekarma --timeout=300s || true
  
  echo "Waiting for Nexus application pod..."
  kubectl wait --for=condition=ready pod -l app=ck-nexus-app -n codekarma --timeout=300s || true
  
  echo "✅ All pods are ready"
}

# Function to display status
display_status() {
  echo ""
  echo "🎉 GCP GKE Cleartrip deployment completed successfully!"
  echo ""
  echo "📊 Deployment Status:"
  echo "Namespace: codekarma"
  echo "Cluster: gke_codekarma-auth_us-east1_cleartrip-cluster"
  echo "Environment: GCP Cleartrip"
  echo ""
  echo "🔍 To check pod status:"
  echo "kubectl get pods -n codekarma"
  echo ""
  echo "🔍 To check services:"
  echo "kubectl get services -n codekarma"
  echo ""
  echo "📝 To view logs:"
  echo "kubectl logs -l app=ck-nexus-app -n codekarma -f"
  echo ""
  echo "🌐 To access the application:"
  echo "kubectl port-forward svc/ck-nexus-app 8081:8081 -n codekarma"
  echo ""
  echo "📊 To access Prometheus:"
  echo "kubectl port-forward svc/ck-prometheus 9090:9090 -n codekarma"
}

# Function to display the main menu
main_menu() {
  while true; do
    clear
    echo "=========================================="
    echo "  CodeKarma GCP GKE Cleartrip Setup"
    echo "=========================================="
    echo ""
    echo "Target Cluster: gke_codekarma-auth_us-east1_cleartrip-cluster"
    echo "Environment: GCP Cleartrip"
    echo ""
    echo "Please select an option:"
    echo "1. Install Prometheus only"
    echo "2. Install PostgreSQL only"
    echo "3. Deploy Nexus application only"
    echo "4. Setup RBAC permissions only"
    echo "5. Install all components (Prometheus + PostgreSQL + Nexus)"
    echo "6. Check deployment status"
    echo "7. Exit"
    echo ""
    read -p "Enter your choice (1-7): " choice
    
    case $choice in
      1)
        echo ""
        echo "Installing Prometheus..."
        check_kubectl
        check_helm
        check_gcp_context
        create_namespace
        install_prometheus
        echo ""
        echo "✅ Prometheus installation completed!"
        echo ""
        read -p "Press Enter to continue..."
        ;;
      2)
        echo ""
        echo "Installing PostgreSQL..."
        check_kubectl
        check_helm
        check_gcp_context
        create_namespace
        install_nexus_db
        echo ""
        echo "✅ PostgreSQL installation completed!"
        echo ""
        read -p "Press Enter to continue..."
        ;;
      3)
        echo ""
        echo "Deploying Nexus application..."
        check_kubectl
        check_helm
        check_gcp_context
        create_namespace
        build_and_deploy_nexus
        echo ""
        echo "✅ Nexus application deployment completed!"
        echo ""
        read -p "Press Enter to continue..."
        ;;
      4)
        echo ""
        echo "Setting up RBAC permissions..."
        check_kubectl
        check_gcp_context
        create_namespace
        setup_rbac
        echo ""
        echo "✅ RBAC permissions setup completed!"
        echo ""
        read -p "Press Enter to continue..."
        ;;
      5)
        echo ""
        echo "Installing all components..."
        check_kubectl
        check_helm
        check_gcp_context
        create_namespace
        setup_storage
        setup_rbac
        install_prometheus
        install_nexus_db
        build_and_deploy_nexus
        wait_for_pods
        display_status
        echo ""
        read -p "Press Enter to continue..."
        ;;
      6)
        echo ""
        echo "Checking deployment status..."
        echo ""
        echo "📊 Pod Status:"
        kubectl get pods -n codekarma
        echo ""
        echo "📊 Service Status:"
        kubectl get services -n codekarma
        echo ""
        echo "📊 Helm Releases:"
        helm list -n codekarma
        echo ""
        read -p "Press Enter to continue..."
        ;;
      7)
        echo ""
        echo "Exiting..."
        exit 0
        ;;
      *)
        echo ""
        echo "❌ Invalid choice. Please enter a number between 1-7."
        echo ""
        read -p "Press Enter to continue..."
        ;;
    esac
  done
}

# Function for non-interactive full installation (for automation)
install_all_non_interactive() {
  echo "Starting CodeKarma GCP GKE Cleartrip setup (Non-Interactive Mode)..."
  echo "Target Cluster: gke_codekarma-auth_us-east1_cleartrip-cluster"
  echo "Environment: GCP Cleartrip"
  
  # Check prerequisites
  check_kubectl
  check_helm
  check_gcp_context
  
  # Create namespace
  create_namespace
  
  # Set up storage first
  setup_storage
  
  # Setup RBAC permissions
  setup_rbac
  
  # Install all components
  install_prometheus
  install_nexus_db
  build_and_deploy_nexus
  
  # Wait for pods to be ready
  wait_for_pods
  
  # Display final status
  display_status
  
  echo "CodeKarma GCP GKE Cleartrip setup completed successfully!"
}

# Function to show help
show_help() {
  echo "CodeKarma GCP GKE Cleartrip Installation Script"
  echo ""
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --non-interactive, -ni    Run in non-interactive mode (for automation)"
  echo "  --help, -h                Show this help message"
  echo ""
  echo "Interactive Mode:"
  echo "  Run the script without any arguments to get an interactive menu"
  echo ""
  echo "Non-Interactive Mode:"
  echo "  $0 --non-interactive"
  echo ""
  echo "Prerequisites:"
  echo "  - kubectl must be installed and configured"
  echo "  - helm must be installed"
  echo "  - kubectl context must be set to: gke_codekarma-auth_us-east1_cleartrip-cluster"
  echo ""
  echo "Components:"
  echo "  - Prometheus (using values-gcp-cleartrip.yaml)"
  echo "  - PostgreSQL (using values-gcp-cleartrip.yaml)"
  echo "  - Nexus Application (using values-gcp-cleartrip.yaml)"
  echo ""
  echo "All components are configured for n2d node type with proper node affinity."
}

# Check command line arguments
case "${1:-}" in
  --non-interactive|-ni)
    install_all_non_interactive
    ;;
  --help|-h)
    show_help
    ;;
  "")
    # Run the interactive menu
    main_menu
    ;;
  *)
    echo "Unknown option: $1"
    echo "Use --help for usage information"
    exit 1
    ;;
esac
