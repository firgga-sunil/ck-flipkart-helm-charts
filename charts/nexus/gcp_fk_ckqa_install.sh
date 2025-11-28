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
  required_context="gke_codekarma-auth_us-east1_ck-fk-pg"
  
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

# Function to install Prometheus
install_prometheus() {
  echo "Installing Prometheus on GCP GKE..."
  
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
    # Install Prometheus with GCP-specific values
    echo "Installing Prometheus using Helm with GCP configuration..."
    helm install ckp prometheus-community/kube-prometheus-stack -f ./prometheus/values-gcp-fk-ckqa.yaml -n codekarma --timeout 10m0s
    
    echo "✅ Prometheus installed successfully on GCP"
  fi
}

# Function to install Nexus DB (PostgreSQL)
install_nexus_db() {
  echo "Installing Nexus DB (PostgreSQL) on GCP GKE..."
  
  # Check if Nexus DB is already installed
  if helm list -n codekarma | grep -q "ck-postgres"; then
    echo "✅ Nexus DB (PostgreSQL) is already installed"
  else
    # Install PostgreSQL with GCP-specific values
    echo "Installing PostgreSQL using Helm with GCP configuration..."
    helm install ck-postgres ./db/postgres -f db/postgres/values-gcp-fk-ckqa.yaml -n codekarma
    
    echo "✅ Nexus DB (PostgreSQL) installed successfully on GCP"
  fi
}

# Function to build and deploy Nexus application for GCP
build_and_deploy_nexus() {
  echo "Building and deploying Nexus application to GCP GKE..."
  
  # Get current directory for navigation
  CURRENT_DIR=$(pwd)
  
  # Navigate to the parent directory
  cd ../
  
  # For GCP, we'll push to container registry instead of loading into local cluster
  echo "Building and pushing docker image for GCP deployment..."
  
  # Check if we need to build first
  echo "Building the application..."
  ./gradlew clean build
  
  # Login to GitHub Container Registry
  echo "Logging into ghcr.io..."
  USERNAME=$(./gradlew -q getGprUser)
  TOKEN=$(./gradlew -q getGprToken)
  echo "$TOKEN" | docker login ghcr.io -u "$USERNAME" --password-stdin
  
  # Build and push docker image
  echo "Building and pushing docker image for GCP..."
  docker buildx build --platform linux/amd64,linux/arm64 \
    -t ghcr.io/$USERNAME/gcp/nexus-app:latest \
    --push .
  
  echo "✅ Docker image built and pushed successfully for GCP"
  
  # Navigate back to charts directory
  cd "$CURRENT_DIR"
  
  # Check if Nexus application is already installed
  if helm list -n codekarma | grep -q "ck-nexus"; then
    echo "Nexus application is already installed. Upgrading..."
    helm upgrade ck-nexus ./ck-nexus-charts -f ./ck-nexus-charts/values-gcp-fk-ckqa.yaml -n codekarma
  else
    # Install Nexus application
    echo "Installing Nexus application using Helm with GCP configuration..."
    helm install ck-nexus ./ck-nexus-charts -f ./ck-nexus-charts/values-gcp-fk-ckqa.yaml -n codekarma
  fi
  
  echo "✅ Nexus application deployed successfully to GCP"
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
  echo "🎉 GCP GKE deployment completed successfully!"
  echo ""
  echo "📊 Deployment Status:"
  echo "Namespace: codekarma"
  echo "Cluster: gke_codekarma-auth_us-east1_ck-fk-pg"
  echo ""
  echo "🔍 To check pod status:"
  echo "kubectl get pods -n codekarma"
  echo ""
  echo "🔍 To check services:"
  echo "kubectl get services -n codekarma"
  echo ""
  echo "📝 To view logs:"
  echo "kubectl logs -l app=ck-nexus-app -n codekarma -f"
}

# Function to display menu
display_menu() {
  echo ""
  echo "=============================================="
  echo "🚀 CodeKarma GCP GKE Installation Menu"
  echo "=============================================="
  echo "Cluster: gke_codekarma-auth_us-east1_ck-fk-pg"
  echo "Namespace: codekarma"
  echo ""
  echo "Select components to install:"
  echo ""
  echo "1) Install Prometheus"
  echo "2) Install PostgreSQL Database"
  echo "3) Install Nexus Application"
  echo "4) Install All Components (Prometheus + PostgreSQL + Nexus)"
  echo "5) Check Installation Status"
  echo "6) Exit"
  echo ""
  echo "=============================================="
}

# Function to check component status
check_installation_status() {
  echo ""
  echo "🔍 Checking installation status..."
  echo ""
  
  # Check namespace
  if kubectl get namespace codekarma &> /dev/null; then
    echo "✅ Namespace 'codekarma' exists"
  else
    echo "❌ Namespace 'codekarma' does not exist"
  fi
  
  # Check Prometheus
  if helm list -n codekarma | grep -q "ckp"; then
    echo "✅ Prometheus is installed"
    prometheus_status=$(kubectl get pods -n codekarma -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)
    if [ "$prometheus_status" -gt 0 ]; then
      echo "   📊 Prometheus pods: $prometheus_status running"
    fi
  else
    echo "❌ Prometheus is not installed"
  fi
  
  # Check PostgreSQL
  if helm list -n codekarma | grep -q "ck-postgres"; then
    echo "✅ PostgreSQL is installed"
    postgres_status=$(kubectl get pods -n codekarma -l app.kubernetes.io/name=postgresql --no-headers 2>/dev/null | wc -l)
    if [ "$postgres_status" -gt 0 ]; then
      echo "   🗄️  PostgreSQL pods: $postgres_status running"
    fi
  else
    echo "❌ PostgreSQL is not installed"
  fi
  
  # Check Nexus
  if helm list -n codekarma | grep -q "ck-nexus"; then
    echo "✅ Nexus Application is installed"
    nexus_status=$(kubectl get pods -n codekarma -l app=ck-nexus-app --no-headers 2>/dev/null | wc -l)
    if [ "$nexus_status" -gt 0 ]; then
      echo "   🎯 Nexus pods: $nexus_status running"
    fi
  else
    echo "❌ Nexus Application is not installed"
  fi
  
  echo ""
  echo "📝 All pods in codekarma namespace:"
  kubectl get pods -n codekarma 2>/dev/null || echo "   No pods found or namespace doesn't exist"
}

# Main execution with interactive menu
main_menu() {
  echo "Starting CodeKarma GCP GKE setup..."
  echo "Target Cluster: gke_codekarma-auth_us-east1_ck-fk-pg"
  
  # Check prerequisites
  check_kubectl
  check_helm
  check_gcp_context
  
  # Create namespace (always needed)
  create_namespace
  
  while true; do
    display_menu
    echo -n "Enter your choice (1-6): "
    read choice
    
    case $choice in
      1)
        echo ""
        echo "🔧 Installing Prometheus..."
        install_prometheus
        echo "✅ Prometheus installation completed!"
        echo ""
        read -p "Press Enter to continue..."
        ;;
      2)
        echo ""
        echo "🔧 Installing PostgreSQL Database..."
        install_nexus_db
        echo "✅ PostgreSQL installation completed!"
        echo ""
        read -p "Press Enter to continue..."
        ;;
      3)
        echo ""
        echo "🔧 Installing Nexus Application..."
        build_and_deploy_nexus
        echo "✅ Nexus Application installation completed!"
        echo ""
        read -p "Press Enter to continue..."
        ;;
      4)
        echo ""
        echo "🔧 Installing All Components (Prometheus + PostgreSQL + Nexus)..."
        echo ""
        install_prometheus
        echo ""
        install_nexus_db
        echo ""
        build_and_deploy_nexus
        echo ""
        wait_for_pods
        display_status
        echo ""
        read -p "Press Enter to continue..."
        ;;
      5)
        check_installation_status
        echo ""
        read -p "Press Enter to continue..."
        ;;
      6)
        echo ""
        echo "👋 Exiting CodeKarma GCP GKE Installation Menu"
        echo "Thank you for using CodeKarma!"
        exit 0
        ;;
      *)
        echo ""
        echo "❌ Invalid choice. Please enter a number between 1-6."
        echo ""
        read -p "Press Enter to continue..."
        ;;
    esac
  done
}

# Function for non-interactive full installation (for automation)
install_all_non_interactive() {
  echo "Starting CodeKarma GCP GKE setup (Non-Interactive Mode)..."
  echo "Target Cluster: gke_codekarma-auth_us-east1_ck-fk-pg"
  
  # Check prerequisites
  check_kubectl
  check_helm
  check_gcp_context
  
  # Create namespace
  create_namespace
  
  # Install all components
  install_prometheus
  install_nexus_db
  build_and_deploy_nexus
  
  # Wait for pods to be ready
  wait_for_pods
  
  # Display final status
  display_status
  
  echo "CodeKarma GCP GKE setup completed successfully!"
}

# Check if script is run with --non-interactive flag
if [ "$1" = "--non-interactive" ] || [ "$1" = "-ni" ]; then
  install_all_non_interactive
else
  # Run the interactive menu
  main_menu
fi
