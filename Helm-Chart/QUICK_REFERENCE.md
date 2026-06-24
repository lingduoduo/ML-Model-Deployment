# Helm Deployment Quick Reference

## Essential Commands

### Preparation
```bash
# Validate setup
./deploy/validate-deployment.sh

# Set required variables
export IMAGE_REPOSITORY=ghcr.io/user/model
export IMAGE_TAG=v1.0.0
```

### Deployment
```bash
# Deploy to staging (default)
./deploy/run-local-deploy.sh

# Deploy to production
export DEPLOY_ENVIRONMENT=production
./deploy/run-local-deploy.sh

# Deploy with canary (10% traffic to new version)
export DEPLOY_STRATEGY=canary
./deploy/run-local-deploy.sh

# Deploy with tracking
export GIT_COMMIT=$(git rev-parse HEAD)
export BUILD_NUMBER=${CI_BUILD_NUMBER}
./deploy/run-local-deploy.sh
```

### Monitoring
```bash
# Real-time dashboard
./deploy/monitor-deployment.sh

# Watch pods
kubectl get pods -n model-serving -w

# View logs
kubectl logs -n model-serving -l app.kubernetes.io/instance=model-release -f

# Check status
kubectl get deployments -n model-serving
```

### Rollback
```bash
# Interactive rollback helper
./deploy/rollback-deployment.sh

# Manual rollback to previous
helm rollback model-release -n model-serving

# Manual rollback to specific revision
helm rollback model-release 5 -n model-serving
```

---

## Environment Variables

```bash
# Required
IMAGE_REPOSITORY         # Docker registry + image name
IMAGE_TAG               # Image version tag

# Optional (with defaults)
DEPLOY_ENVIRONMENT=staging          # or 'production'
DEPLOY_STRATEGY=standard            # or 'canary'
RELEASE_NAME=model-release
KUBE_NAMESPACE=model-serving
TIMEOUT=5m
IMAGE_PULL_POLICY=IfNotPresent      # IfNotPresent, Always, Never
CONTAINER_PORT=8000
SERVICE_PORT=8000
LIVENESS_PATH=/health
READINESS_PATH=/health

# For tracking
GIT_COMMIT=$(git rev-parse HEAD)
BUILD_NUMBER=$CI_BUILD_NUMBER
```

---

## Health Check Paths

Default setup expects these endpoints:
- `/health` - Liveness probe (pod is alive)
- `/ready` - Readiness probe (ready for traffic)

### Customize
```bash
export LIVENESS_PATH=/healthz
export READINESS_PATH=/readiness
./deploy/run-local-deploy.sh
```

---

## Resource Guidelines

### Staging (Testing)
```yaml
requests: {cpu: 250m, memory: 512Mi}
limits: {cpu: 1, memory: 1Gi}
```

### Production (HA)
```yaml
requests: {cpu: 1, memory: 1Gi}
limits: {cpu: 2, memory: 2Gi}
```

Adjust based on:
- Model size (larger = more memory)
- Inference time (slower = more CPU)
- Peak traffic (higher = more replicas)

---

## Pod Startup Time Configuration

For models that take time to load:

```bash
# Default: 5 minutes startup allowed
startupProbe:
  failureThreshold: 30
  periodSeconds: 10

# For quick-starting services: 30 seconds
startupProbe:
  failureThreshold: 3
  periodSeconds: 10
```

---

## Troubleshooting Quick Fixes

### Pod won't start
```bash
# Check pod events
kubectl describe pod <pod-name> -n model-serving

# View logs
kubectl logs <pod-name> -n model-serving

# Increase startup timeout
# Edit values-*.yaml and increase startupProbe.failureThreshold
```

### Won't pull image
```bash
# For Minikube, load image locally
eval $(minikube docker-env)
docker build -t your-image:tag .
minikube image load your-image:tag

# Or use pull policy
export IMAGE_PULL_POLICY=Always
./deploy/run-local-deploy.sh
```

### Deployment stuck
```bash
# Check resource availability
kubectl top nodes
kubectl describe node <node-name>

# Check pod is scheduled
kubectl describe pod <pod-name> -n model-serving
```

### Health checks failing
```bash
# Port forward and test endpoints manually
kubectl port-forward <pod-name> 8080:8080 -n model-serving
curl http://localhost:8080/health
curl http://localhost:8080/ready

# If endpoints wrong, update deployment
export LIVENESS_PATH=/healthz
./deploy/run-local-deploy.sh
```

---

## Release Management

### View history
```bash
helm history model-release -n model-serving

# See changes between revisions
helm diff revision model-release 1 2 -n model-serving
```

### Describe release
```bash
helm status model-release -n model-serving
```

### Get current values
```bash
helm get values model-release -n model-serving
```

### Delete release
```bash
helm uninstall model-release -n model-serving
```

---

## Canary Deployments

### Deploy canary (10% traffic)
```bash
export DEPLOY_STRATEGY=canary
export DEPLOY_ENVIRONMENT=production
./deploy/run-local-deploy.sh
```

### Monitor canary
```bash
# View canary pods
kubectl get pods -n model-serving -l track=canary

# View canary logs
kubectl logs -n model-serving -l app.kubernetes.io/instance=model-release-canary -f

# Check metrics
kubectl top pods -n model-serving -l track=canary
```

### Promote canary (100% stable)
```bash
# 1. Verify canary is healthy & stable (monitoring needed)
# 2. Deploy new version to stable
export DEPLOY_STRATEGY=standard
./deploy/run-local-deploy.sh

# 3. Remove canary
helm uninstall model-release-canary -n model-serving
```

---

## CI/CD Integration

### GitHub Actions
```yaml
- name: Deploy
  run: |
    export IMAGE_REPOSITORY=ghcr.io/${{ github.repository }}
    export IMAGE_TAG=${{ github.sha }}
    export GIT_COMMIT=${{ github.sha }}
    export BUILD_NUMBER=${{ github.run_number }}
    ./deploy/run-local-deploy.sh
```

### GitLab CI
```yaml
deploy:
  script:
    - export IMAGE_REPOSITORY=registry.gitlab.com/$CI_PROJECT_PATH
    - export IMAGE_TAG=$CI_COMMIT_SHA
    - export GIT_COMMIT=$CI_COMMIT_SHA
    - export BUILD_NUMBER=$CI_PIPELINE_ID
    - ./deploy/run-local-deploy.sh
```

---

## Useful Kubectl Commands

### Deployment
```bash
# Get deployment
kubectl get deployment -n model-serving

# Describe
kubectl describe deployment model-release -n model-serving

# Get YAML
kubectl get deployment model-release -n model-serving -o yaml

# Scale manually (normally use HPA)
kubectl scale deployment model-release --replicas=5 -n model-serving
```

### Pods
```bash
# List pods
kubectl get pods -n model-serving

# Watch pods (real-time)
kubectl get pods -n model-serving -w

# Describe pod (for errors)
kubectl describe pod <pod-name> -n model-serving

# Get logs
kubectl logs <pod-name> -n model-serving
kubectl logs <pod-name> -n model-serving -c model-deployment  # specific container
kubectl logs <pod-name> -n model-serving -f          # follow

# Previous logs (if crashed)
kubectl logs <pod-name> -n model-serving --previous
```

### Services
```bash
# Get service
kubectl get service -n model-serving

# Port forward (local access)
kubectl port-forward svc/model-release 8080:8080 -n model-serving
```

### Resources
```bash
# View resource usage
kubectl top pods -n model-serving
kubectl top nodes

# Show resource requests/limits
kubectl get pods -n model-serving -o json | jq '.items[].spec.containers[].resources'
```

### Delete/Reset
```bash
# Delete pod (will be recreated)
kubectl delete pod <pod-name> -n model-serving

# Delete all pods (restart)
kubectl delete pods --all -n model-serving

# Delete namespace (clean slate)
kubectl delete namespace model-serving
```

---

## File Structure

```
Helm-Chart/
├── deploy/                          # Operator scripts (target Model-Deployment/chart)
│   ├── deploy_with_helm.sh          # Main deployment script
│   ├── run-local-deploy.sh          # Wrapper for local testing
│   ├── validate-deployment.sh       # Pre-deployment validation
│   ├── monitor-deployment.sh        # Real-time status dashboard
│   ├── rollback-deployment.sh       # Safe rollback helper
│   └── README.md                    # Detailed guide
├── OPTIMIZATION.md                  # Detailed optimization guide
├── DEPLOYMENT_SUMMARY.md            # This summary
└── README.md                        # Overview

# The chart itself now lives in the canonical Model-Deployment chart:
Model-Deployment/chart/
├── Chart.yaml                       # Chart metadata
├── values.yaml                      # Default values
├── values-dev.yaml                  # Dev environment (+ scheduled jobs)
├── values-staging.yaml              # Staging environment
├── values-production.yaml           # Production environment
├── values-production-canary.yaml    # Canary release config
├── values-model-example.yaml        # Example configuration
├── scripts/verify-render.sh         # Render assertions (regression gate)
└── templates/
    ├── deployment.yaml              # Main deployment
    ├── service.yaml                 # Kubernetes Service
    ├── ingress.yaml                 # Ingress (optional)
    ├── poddisruptionbudget.yaml     # HA protection
    └── ...
```

---

## Common Scenarios

### Local development with Minikube
```bash
# 1. Start Minikube
minikube start

# 2. Build image in Minikube
eval $(minikube docker-env)
docker build -t my-model:latest .

# 3. Deploy
export IMAGE_REPOSITORY=my-model
export IMAGE_TAG=latest
./deploy/run-local-deploy.sh
```

### Deploy new model version
```bash
export IMAGE_REPOSITORY=ghcr.io/org/model
export IMAGE_TAG=v1.2.3           # New version
export DEPLOY_ENVIRONMENT=staging # Test first
./deploy/run-local-deploy.sh

# Monitor
./deploy/monitor-deployment.sh

# Then promote to production
export DEPLOY_ENVIRONMENT=production
./deploy/run-local-deploy.sh
```

### Emergency rollback
```bash
# Quick check what to rollback to
helm history model-release -n model-serving

# Interactive rollback
./deploy/rollback-deployment.sh

# Monitor
./deploy/monitor-deployment.sh
```

### Performance tuning
```bash
# Check current resource usage
kubectl top pods -n model-serving

# View requests/limits
kubectl get pods -n model-serving -o json | \
  jq '.items[] | {name: .metadata.name, resources: .spec.containers[].resources}'

# Update resources
helm upgrade model-release Model-Deployment/chart \
  -f Model-Deployment/chart/values-production.yaml \
  --set resources.requests.cpu=2 \
  -n model-serving
```

---

## Tips & Tricks

1. **Always validate first**: `./deploy/validate-deployment.sh`
2. **Test in staging**: `DEPLOY_ENVIRONMENT=staging ./deploy/run-local-deploy.sh`
3. **Monitor deployment**: Open another terminal with `./deploy/monitor-deployment.sh`
4. **Check health endpoints**: `kubectl port-forward <pod> 8080:8080` then `curl localhost:8080/health`
5. **Keep it rolling**: Helm updates in-place, no downtime with multiple replicas
6. **Track everything**: Always set GIT_COMMIT and BUILD_NUMBER
7. **Use canary first**: For risky changes, test with canary before production
8. **Document startup time**: Update health probe timeouts based on model load time
9. **Monitor resources**: Use `kubectl top` to tune requests/limits
10. **Automate verification**: CI/CD should run validate-deployment.sh before deploying

---

## When to Use What

| Task | Command |
|------|---------|
| First time setup | `./deploy/validate-deployment.sh` |
| Routine deployment | `./deploy/run-local-deploy.sh` |
| Check status | `./deploy/monitor-deployment.sh` |
| View history | `helm history <release>` |
| Need to rollback | `./deploy/rollback-deployment.sh` |
| Troubleshoot | `kubectl describe pod` + `kubectl logs` |
| Scale replicas | `kubectl scale deployment` |
| Access service | `kubectl port-forward` |
| Full reset | `helm uninstall` + redeploy |

---

**Last Updated**: April 14, 2026
**Helm Version**: 3.10+
**Kubernetes Version**: 1.24+
