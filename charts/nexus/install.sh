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

# Function to check if current context is kind-kind
check_context() {
  current_context=$(kubectl config current-context)
  if [ "$current_context" != "kind-kind" ]; then
    echo "Error: Current kubectl context is '$current_context', not 'kind-kind'"
    echo "Please switch to the kind-kind context with: kubectl config use-context kind-kind"
    exit 1
  else
    echo "✅ Current kubectl context is kind-kind"
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
  echo "Installing Prometheus..."
  
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
    # Install Prometheus
    echo "Installing Prometheus using Helm..."
    helm install ckp prometheus-community/kube-prometheus-stack -f ./prometheus/values.yaml -n codekarma
    
    echo "✅ Prometheus installed successfully"
  fi
}


# Function to install Nexus DB (PostgreSQL)
install_nexus_db() {
  echo "Installing Nexus DB (PostgreSQL)..."
  
  # Check if Nexus DB is already installed
  if helm list -n codekarma | grep -q "ck-postgres"; then
    echo "✅ Nexus DB (PostgreSQL) is already installed"
  else
    # Install PostgreSQL
    echo "Installing PostgreSQL using Helm..."
    helm install ck-postgres ./db/postgres -f db/postgres/values.yaml -n codekarma
    
    # Navigate back to the original directory
    cd "$CURRENT_DIR"
    
    echo "✅ Nexus DB (PostgreSQL) installed successfully"
  fi
}

# Function to build and deploy Nexus application
build_and_deploy_nexus() {
  echo "Building and deploying Nexus application..."
  
  # Navigate to the parent directory of ck-karmacontrol
  cd ../
  
  # Build the Nexus application
  echo "Building docker image for Nexus application..."
  docker build -t nexus-app:latest .
  
  # Load the image into Kind cluster
  echo "Loading image into Kind cluster..."
  kind load docker-image nexus-app:latest --name=kind
  
  # Check if Nexus application is already installed
  if helm list -n codekarma | grep -q "ck-nexus"; then
    echo "Nexus application is already installed. Uninstalling to reinstall..."
    helm uninstall ck-nexus -n codekarma
  fi
  
  # Install Nexus application
  echo "Installing Nexus application using Helm..."
  helm install ck-nexus ./charts/ck-nexus-charts -f ./charts/ck-nexus-charts/values.yaml -n codekarma
  
  echo "✅ Nexus application built and deployed successfully"
}

# Main execution
echo "Starting CodeKarma local setup..."

# Check prerequisites
check_kubectl
check_helm
#check_context

# Create namespace
create_namespace

# Install monitoring components
install_prometheus
#install_pushgateway

# Install Nexus DB
install_nexus_db

# Build and deploy Nexus application
build_and_deploy_nexus

echo "CodeKarma local setup completed successfully!"



