# Helm Values Files

This directory contains Helm values files for different deployment environments.

## Files Structure

- `values.yaml` - Base configuration for local Kind cluster deployments
- `values-aws-demo.yaml` - Configuration for AWS demo environment deployments  
- `values-aws-dev.yaml` - Configuration for AWS development environment deployments
- `values-aws-prod.yaml` - Configuration for AWS production environment deployments

## Usage

These files are automatically selected by the Makefile based on the deployment target:

```bash
# Uses helm/values.yaml
make build-and-deploy-kind-demo

# Uses helm/values-aws-demo.yaml  
make build-and-deploy-aws-demo

# Uses helm/values-aws-ckqa.yaml
make build-and-deploy-aws-dev

# Uses helm/values-aws-prod.yaml
make build-and-deploy-aws-prod
```

## Configuration Differences

Each values file contains environment-specific settings such as:

- **Resource Limits**: CPU and memory allocations appropriate for the environment
- **Service Configuration**: LoadBalancer vs NodePort settings
- **Ingress Settings**: Domain names and SSL configurations
- **Feature Flags**: Environment-specific feature toggles
- **Scaling Settings**: Replica counts and autoscaling parameters

## Modifying Values

When making changes:

1. Edit the appropriate values file for your target environment
2. Test locally first using `helm/values.yaml`
3. Deploy using the corresponding Make target
4. Verify the deployment was successful

## Best Practices

- Keep local values minimal and focused on development needs
- Use AWS values files for production-like configurations
- Document any environment-specific changes in commit messages
- Test configuration changes in demo environment before development 