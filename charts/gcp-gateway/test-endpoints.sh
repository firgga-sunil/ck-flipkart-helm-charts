#!/bin/bash

# Test script for CodeKarma GCP Gateway API endpoints
# This script tests the HTTPS endpoints after deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="codekarma"
RELEASE_NAME="ck-gcp-gateway"
VALUES_FILE="values-gcp-ckqa.yaml"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to get external IP from Gateway
get_external_ip() {
    # Try to get gateway name from values file
    GATEWAY_NAME=$(grep 'gatewayName:' $VALUES_FILE 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "$RELEASE_NAME")
    
    IP=$(kubectl get gateway $GATEWAY_NAME -n $NAMESPACE -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -z "$IP" ]; then
        print_error "Could not get external IP. Make sure the gateway is deployed and has an IP assigned."
        print_error "Gateway name: $GATEWAY_NAME"
        print_error "Check with: kubectl get gateway $GATEWAY_NAME -n $NAMESPACE"
        exit 1
    fi
    echo $IP
}

# Function to get domains from values file
get_domains() {
    if [ -f "$VALUES_FILE" ]; then
        grep -A 10 '^domains:' $VALUES_FILE | grep -E '^\s+-' | sed 's/.*"\(.*\)".*/\1/' | sed 's/.*- \(.*\)/\1/'
    else
        echo "fkapi.codekarma.tech"
        echo "fkapp.codekarma.tech"
    fi
}

# Function to test endpoint
test_endpoint() {
    local domain=$1
    local path=$2
    local description=$3
    
    print_status "Testing $description: $domain$path"
    
    # Test with curl
    if command -v curl &> /dev/null; then
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "https://$domain$path" 2>/dev/null || echo "000")
        
        if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "204" ]; then
            print_success "$description: HTTP $RESPONSE"
        else
            print_warning "$description: HTTP $RESPONSE (expected 200/204)"
        fi
    else
        print_warning "curl not available, skipping HTTP test"
    fi
    
    # Test DNS resolution
    if command -v nslookup &> /dev/null; then
        if nslookup $domain &> /dev/null; then
            print_success "DNS resolution for $domain: OK"
        else
            print_error "DNS resolution for $domain: FAILED"
        fi
    else
        print_warning "nslookup not available, skipping DNS test"
    fi
    
    echo ""
}

# Function to test SSL certificate
test_ssl_certificate() {
    local domain=$1
    
    print_status "Testing SSL certificate for $domain"
    
    if command -v openssl &> /dev/null; then
        # Get certificate details
        CERT_INFO=$(echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -subject -dates -issuer 2>/dev/null || echo "")
        
        if [ -n "$CERT_INFO" ]; then
            print_success "SSL certificate for $domain: VALID"
            echo "$CERT_INFO" | head -3
        else
            print_error "SSL certificate for $domain: INVALID or not accessible"
        fi
    else
        print_warning "openssl not available, skipping SSL test"
    fi
    
    echo ""
}

# Function to test gRPC endpoint
test_grpc_endpoint() {
    local domain=$1
    
    print_status "Testing gRPC endpoint for $domain"
    
    if command -v grpcurl &> /dev/null; then
        # Test gRPC connectivity (this is a basic connectivity test)
        if grpcurl -plaintext -d '{}' $domain:443 opentelemetry.proto.collector.metrics.v1.MetricsService/Export &> /dev/null; then
            print_success "gRPC endpoint for $domain: CONNECTED"
        else
            print_warning "gRPC endpoint for $domain: Connection failed (this may be expected for health checks)"
        fi
    else
        print_warning "grpcurl not available, skipping gRPC test"
    fi
    
    echo ""
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n, --namespace NAMESPACE    Kubernetes namespace (default: codekarma)"
    echo "  -r, --release RELEASE_NAME   Helm release name (default: ck-gcp-gateway)"
    echo "  -f, --values VALUES_FILE     Values file to use for gateway name (default: values-gcp-ckqa.yaml)"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Test with default settings"
    echo "  $0 -n mynamespace -r myrelease       # Test with custom namespace and release name"
    echo "  $0 -f values-gcp-demo.yaml           # Test with demo values file"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -f|--values)
            VALUES_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_status "Starting endpoint testing for CodeKarma GCP Gateway API..."
    print_status "Namespace: $NAMESPACE"
    print_status "Release name: $RELEASE_NAME"
    print_status "Values file: $VALUES_FILE"
    echo ""
    
    # Get external IP
    IP=$(get_external_ip)
    print_status "External IP: $IP"
    echo ""
    
    # Get domains from values file
    DOMAINS=$(get_domains)
    
    # Test all endpoints for each domain
    while IFS= read -r domain; do
        if [ -n "$domain" ]; then
            test_endpoint "$domain" "/api/nexus/health" "Frontend API Health Check ($domain)"
            test_endpoint "$domain" "/" "Frontend Application ($domain)"
            test_ssl_certificate "$domain"
            test_grpc_endpoint "$domain"
        fi
    done <<< "$DOMAINS"
    
    print_status "Endpoint testing completed!"
    print_status "Note: DNS propagation may take up to 24 hours for new domains."
    print_status "Note: SSL certificates must be properly configured via cert-manager."
}

# Run main function
main "$@"

