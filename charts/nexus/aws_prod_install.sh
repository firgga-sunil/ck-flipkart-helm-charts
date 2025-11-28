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

# Function to check if current context is aws-prod
check_context() {
  current_context=$(kubectl config current-context)
  if [ "$current_context" != "arn:aws:eks:ap-south-1:484907483585:cluster/ck-aws-prod" ]; then
    echo "Error: Current kubectl context is '$current_context', not of 'aws-prod'"
    echo "Please switch to the aws-prod context with: kubectl config use-context {aws-prod-context}}"
    exit 1
  else
    echo "✅ Current kubectl context is of aws-prod"
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
  if kubectl get storageclass auto-ebs-sc &> /dev/null; then
    echo "✅ Storage class 'auto-ebs-sc' already exists"
  else
    echo "Creating storage class 'auto-ebs-sc'..."
    kubectl apply -f db/postgres/storage/auto-ebs-sc.yaml
    echo "✅ Storage class created successfully"
  fi
  
  echo "✅ Storage setup completed successfully"
}

# Function to install Prometheus
install_prometheus() {
  echo "Installing Prometheus..."
  
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
    # Install Prometheus
    echo "Installing Prometheus using Helm..."
    helm install ckp prometheus-community/kube-prometheus-stack -f ./prometheus/values-aws.yaml -n codekarma
    
    echo "✅ Prometheus installed successfully"
  fi
}


# Function to install Nexus DB (PostgreSQL)
install_nexus_db() {
  echo "Installing Nexus DB (PostgreSQL)..."
  
  # Ensure storage is set up first
  setup_storage
  
  # Check if Nexus DB is already installed
  if helm list -n codekarma | grep -q "ck-postgres"; then
    echo "✅ Nexus DB (PostgreSQL) is already installed"
  else
    # Install PostgreSQL
    echo "Installing PostgreSQL using Helm..."
    helm install ck-postgres ./db/postgres -f db/postgres/values-aws-prod.yaml -n codekarma
    
    # Navigate back to the original directory
    cd "$CURRENT_DIR"
    
    echo "✅ Nexus DB (PostgreSQL) installed successfully"
  fi
}

# Function to build and deploy Nexus application for AWS
build_and_deploy_nexus() {
  cd ../
  make deploy-prod
  cd charts
}

# Main execution
echo "Starting CodeKarma AWS Nexus and dependencies setup..."

# Check prerequisites
check_kubectl
check_helm
check_context

# Create namespace
create_namespace

# Set up storage first
setup_storage

# Install monitoring components
install_prometheus

# Install Nexus DB
install_nexus_db

# Build and deploy Nexus application
build_and_deploy_nexus

echo "Nexus AWS setup completed successfully!"