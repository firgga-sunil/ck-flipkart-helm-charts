# GCP Gateway API for CodeKarma

This Helm chart deploys a GCP Gateway API (replacing the traditional Ingress) with SSL termination and routes traffic to the nginx ingress controller.

## Architecture

```
Internet (HTTPS) → GCP Gateway → HTTPRoute → nginx Service (HTTP) → Backend Services
```

**Key Point:** Gateway API replaces the Ingress layer and routes to your existing nginx setup. nginx continues to handle final routing to backend services.

## Features

- **Gateway API**: Modern Kubernetes standard for ingress traffic management
- **SSL Termination**: GCP-managed SSL certificates via cert-manager
- **Multiple Domains**: Supports multiple subdomains with automatic SSL provisioning
- **HTTP to HTTPS Redirect**: Native Gateway API redirect filter
- **Security**: TLS 1.2+ enforcement via GCPGatewayPolicy
- **gRPC Support**: Native gRPC traffic handling for OpenTelemetry metrics
- **Static IP**: Support for GCP reserved static IP addresses
- **Force Upgrades**: Automatic upgrade of existing gateways on deployment

## Resources Created

| Resource | Purpose | API Version |
|----------|---------|-------------|
| **Gateway** | Creates GCP Load Balancer, terminates SSL | `gateway.networking.k8s.io/v1` |
| **HTTPRoute** | Routes traffic from Gateway to nginx service | `gateway.networking.k8s.io/v1` |
| **GCPGatewayPolicy** | Applies SSL policy and global access settings | `networking.gke.io/v1` |

## Configuration

### Required Values

```yaml
name: "ck-gateway-gcp"
namespace: "codekarma"

# Gateway configuration
gateway:
  gatewayName: "ck-gateway-gcp"
  gatewayNamespace: "codekarma"
  gatewayClassName: "gke-l7-rilb"  # GCP Gateway class
  namedAddress: "codekarma-lb"      # GCP reserved IP name

# SSL Certificate (cert-manager certificate ID)
certificateId: "www-codekarma-fkcloud-in-1"

# SSL Policy for GCP Gateway Policy
sslPolicy: "ssl-policy-code-karma-min-tls-version-1-2"

# Domains for routing
domains:
  - "codekarma.fkcloud.in"

# Backend service (nginx)
backend:
  serviceName: "ck-ingress-nginx"
  servicePort: 80

# GCP Gateway Policy configuration
gatewayPolicy:
  allowGlobalAccess: true
```

### Environment-Specific Values

- `values-gcp-flipkart.yaml` - Flipkart environment configuration

## Prerequisites

1. **GKE Cluster** with:
   - Gateway API enabled (check with `make check-crds`)
   - Gateway class `gke-l7-rilb` available
   - cert-manager installed (for SSL certificates)

2. **nginx ingress controller** deployed

3. **Backend services** running

4. **GCP Reserved Static IP** (if using static IP):
   ```bash
   gcloud compute addresses create codekarma-lb --global
   ```
   **Important**: The static IP must be created with `purpose=SHARED_LOADBALANCER_VIP` for Gateway API.

5. **cert-manager Certificate** created and ready

## Deployment

### Using Makefile (Recommended)

```bash
# Deploy to Flipkart
make deploy-gcp-flipkart

# Check deployment status
make check-all-gcp-flipkart

# Get external IP
make get-ip-gcp-flipkart
```

### Using Helm Directly

```bash
# Deploy to Flipkart
helm upgrade --install ck-gcp-gateway . \
  --namespace codekarma \
  --values values-gcp-flipkart.yaml \
  --force \
  --wait \
  --timeout 15m
```

**Note**: The `--force` flag ensures that existing gateways are upgraded automatically.

## Makefile Commands

### Generic Commands (Accept GATEWAY_NAME parameter)

```bash
# Generic check gateway status
make check-gateway GATEWAY_NAME=ck-gateway-gcp-flipkart

# Generic comprehensive check
make check-all GATEWAY_NAME=ck-gateway-gcp-flipkart

# Generic get IP
make get-ip GATEWAY_NAME=ck-gateway-gcp-flipkart
```

### Environment-Specific Commands

```bash
# Flipkart
make deploy-gcp-flipkart
make check-gateway-gcp-flipkart
make check-all-gcp-flipkart
make get-ip-gcp-flipkart
make template-gcp-flipkart
```

### Common Commands

```bash
# Check prerequisites
make check-crds          # Verify Gateway API CRDs are installed
make check-namespace     # Verify namespace exists
make check-nginx         # Verify nginx service exists

# Template (dry-run)
make template            # Template with default values
make template-gcp-flipkart

# Status and debugging
make status              # Helm release status
make list                # List all releases
make get-values          # Get current values

# Cleanup
make uninstall           # Uninstall the release
make clean               # Alias for uninstall
```

## Verify Deployment

```bash
# Check Gateway status
kubectl get gateway -n codekarma

# Check HTTPRoute status
kubectl get httproute -n codekarma

# Check GCP Gateway Policy
kubectl get gcpgatewaypolicy -n codekarma

# Comprehensive check (recommended)
make check-all-gcp-flipkart
```

## DNS Configuration

After deployment, update your DNS records to point to the GCP Gateway external IP:

```bash
# Get the external IP
make get-ip-gcp-flipkart
# or
kubectl get gateway ck-gateway-gcp-flipkart -n codekarma -o jsonpath='{.status.addresses[0].value}'
```

Configure DNS records:
- **Flipkart**: `codekarma.fkcloud.in` → Gateway IP

## Traffic Flow

**Complete Request Flow: `https://codekarma.fkcloud.in/api/nexus`**

1. **Internet → GCP Gateway**
   - HTTPS request arrives at GCP Load Balancer (created by Gateway resource)
   - Gateway terminates SSL/TLS using cert-manager certificate
   - Converts HTTPS to HTTP

2. **Gateway → HTTPRoute**
   - HTTPRoute matches hostname (`codekarma.fkcloud.in`) and path (`/api/nexus`)
   - Routes to backend service: `ck-ingress-nginx:80`

3. **HTTPRoute → nginx Service**
   - nginx service receives HTTP request (SSL already terminated)
   - This is your existing `ck-ingress-nginx` service

4. **nginx → Backend Services**
   - nginx uses its ConfigMap rules to route `/api/nexus` to nexus backend
   - nginx routes other paths to other backends

5. **Backend → Response**
   - Backend processes request and returns response
   - Response flows back through nginx → Gateway → Internet

## HTTPRoute Configuration

The chart creates two HTTPRoute resources:

1. **HTTPRoute for HTTPS (port 443)**
   - Routes all HTTPS traffic after SSL termination
   - Handles ACME challenges, gRPC metrics, and general traffic
   - Routes to nginx service

2. **HTTPRoute for HTTP (port 80)**
   - Routes ACME challenge requests to nginx (for Let's Encrypt validation)
   - Redirects all other HTTP traffic to HTTPS using native Gateway API `RequestRedirect` filter

## Troubleshooting

### Common Issues

1. **Gateway Not Programmed**
   ```bash
   make check-all-gcp-flipkart
   # Check the diagnostic summary for specific errors
   ```

   **Address Purpose Mismatch**:
   - Error: `want address purpose=SHARED_LOADBALANCER_VIP, got GCE_ENDPOINT`
   - Fix: Recreate the static IP with correct purpose or use a different named address
   - Contact GCP admin to recreate the address

   **RequestRedirect Port Error**:
   - Error: `Port is not supported for "RequestRedirect" filter`
   - Fix: This should be fixed in the template. Redeploy after fixing.

2. **CRDs Not Installed**
   ```bash
   make check-crds
   # Follow the instructions to enable Gateway API
   ```

3. **SSL Certificate Not Working**
   - Verify cert-manager certificate exists: `kubectl get certificate -n codekarma`
   - Check certificate status: `kubectl describe certificate <name> -n codekarma`
   - Verify `certificateId` in values matches cert-manager certificate name

4. **HTTPRoute Not Routing**
   - Check HTTPRoute status: `kubectl describe httproute <name> -n codekarma`
   - Verify parentRef points to correct Gateway
   - Check backend service has endpoints: `kubectl get endpoints ck-ingress-nginx -n codekarma`

5. **Static IP Not Assigned**
   - Verify GCP reserved IP exists: `gcloud compute addresses list --global`
   - Check `namedAddress` matches the reserved IP name
   - Verify Gateway has correct address configuration

### Debug Commands

```bash
# Check Gateway events and conditions
make check-gateway-gcp-flipkart

# Check all resources with diagnostics
make check-all-gcp-flipkart

# Check Gateway details
kubectl describe gateway ck-gateway-gcp-flipkart -n codekarma

# Check HTTPRoute details
kubectl describe httproute -n codekarma

# Check GCP Gateway Policy
kubectl describe gcpgatewaypolicy -n codekarma

# Check nginx logs
kubectl logs -l app=ck-ingress-nginx -n codekarma

# Check backend service
kubectl get endpoints ck-ingress-nginx -n codekarma

# Check cert-manager certificates
kubectl get certificate -n codekarma
kubectl get certificaterequest -n codekarma
```

## Migration from gcp-alb (Ingress)

### Key Differences

| Component | Ingress (gcp-alb) | Gateway API (gcp-gateway) |
|-----------|-------------------|---------------------------|
| Ingress Resource | `networking.k8s.io/v1` Ingress | `gateway.networking.k8s.io/v1` Gateway + HTTPRoute |
| SSL Certificates | ManagedCertificate or pre-shared certs | cert-manager certificates (via certificateId) |
| Static IP | Annotation: `kubernetes.io/ingress.global-static-ip-name` | NamedAddress in Gateway spec |
| Policy | FrontendConfig annotations | GCPGatewayPolicy resource |
| Routing Rules | Ingress rules | HTTPRoute rules |
| HTTP Redirect | FrontendConfig | Native Gateway API RequestRedirect filter |

### Configuration Mapping

| gcp-alb (Ingress) | gcp-gateway (Gateway API) |
|-------------------|---------------------------|
| `staticIp` | `gateway.namedAddress` |
| `certificateName` | `certificateId` |
| `domains` | `domains` (same) |
| `backend.serviceName` | `backend.serviceName` (same) |
| Ingress annotations | GCPGatewayPolicy |

### Migration Steps

1. **Prepare Certificates**: Ensure cert-manager certificates are created
2. **Update Values Files**: Copy values from `gcp-alb/values-*.yaml` and adapt to Gateway API format
3. **Deploy Gateway**: Deploy alongside existing Ingress for testing
4. **Verify Deployment**: Use `make check-all-gcp-*` to verify
5. **Update DNS** (if IP changed): Update DNS records to point to Gateway IP
6. **Test Thoroughly**: Test all endpoints before removing Ingress
7. **Remove Old Ingress**: After validation, remove the old Ingress setup

## Security Considerations

- All traffic is encrypted with TLS 1.2+
- HTTPS redirect is enforced via Gateway API native redirect
- SSL policies are applied via GCPGatewayPolicy
- Global access can be controlled via GCPGatewayPolicy

## Additional Resources

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [GCP Gateway API Guide](https://cloud.google.com/kubernetes-engine/docs/how-to/gateway-api)
- [cert-manager Documentation](https://cert-manager.io/docs/)
