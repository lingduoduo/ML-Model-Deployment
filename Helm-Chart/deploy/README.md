## CD additions for model deployment

This repo is focused on deployment. Model training, image build, and image publishing are expected to happen in another repo or pipeline. This repo consumes an existing container image reference and deploys it to Kubernetes.

### Quick Start

**Validate your deployment setup:**
```bash
chmod +x deploy/*.sh
./deploy/validate-deployment.sh
```

**Deploy to staging:**
```bash
export IMAGE_REPOSITORY=ghcr.io/<your-user>/<your-image>
export IMAGE_TAG=<tag>
export DEPLOY_ENVIRONMENT=staging
./deploy/run-local-deploy.sh
```

**Deploy to production:**
```bash
export DEPLOY_ENVIRONMENT=production
./deploy/run-local-deploy.sh
```

**Deploy with canary strategy:**
```bash
export DEPLOY_STRATEGY=canary
./deploy/run-local-deploy.sh
```

### CI and CD

The workflow files do this:

1. [ci.yml](.github/workflows/ci.yml) validates the Helm chart on pushes to `main` and `master` and on pull requests
2. [cd.yml](.github/workflows/cd.yml) performs a manual Helm deployment with `workflow_dispatch`
3. CD supports `staging` and `production` environments
4. CD optionally creates a second canary Helm release in production

The deploy logic is in [deploy_with_helm.sh](deploy_with_helm.sh).

### Environment Variables

**Required:**
- `IMAGE_REPOSITORY`: Container image repository (e.g., `ghcr.io/user/model`)
- `IMAGE_TAG`: Container image tag (e.g., `v1.0.0`, `latest`)

**Optional:**
- `DEPLOY_ENVIRONMENT`: `staging` or `production` (default: `staging`)
- `DEPLOY_STRATEGY`: `standard` or `canary` (default: `standard`)
- `RELEASE_NAME`: Helm release name (default: `model-release`)
- `KUBE_NAMESPACE`: Kubernetes namespace (default: `model-serving`)
- `TIMEOUT`: Helm deployment timeout (default: `5m`)
- `GIT_COMMIT`: Git commit SHA for tracking (added as pod annotation)
- `BUILD_NUMBER`: CI/CD build number for tracking (added as pod annotation)
- `CONTAINER_PORT`: Container port (default: from values)
- `SERVICE_PORT`: Service port (default: from values)
- `LIVENESS_PATH`: Health check path for liveness (default: `/health`)
- `READINESS_PATH`: Health check path for readiness (default: `/ready`)

### Run locally on macOS

Use [run-local-deploy.sh](run-local-deploy.sh) for a one-command local deployment:

```bash
chmod +x deploy/run-local-deploy.sh deploy/deploy_with_helm.sh
export IMAGE_REPOSITORY=ghcr.io/<your-user>/<your-image>
export IMAGE_TAG=<tag>
export DEPLOY_ENVIRONMENT=staging
./deploy/run-local-deploy.sh
```

### Service and load balancing

The default recommendation in this repo is:

- `Deployment` for the serving pods
- `Service` with `type: ClusterIP` for internal Kubernetes load balancing across replicas
- `Ingress` or an external gateway for public access, TLS, and traffic controls

Use `LoadBalancer` only when you want the cloud provider to expose the service directly.

### Environment values

Helm values are configured per environment:

- [values-staging.yaml](../../Model-Deployment/chart/values-staging.yaml) - Single replica, basic resources
- [values-production.yaml](../../Model-Deployment/chart/values-production.yaml) - 3 replicas, HPA, pod disruption budget, security hardening
- [values-production-canary.yaml](../../Model-Deployment/chart/values-production-canary.yaml) - 1 replica, canary-labeled for traffic splitting

### Deployment Optimization Tips

#### 1. Health Checks
- **Liveness probe**: Detects deadlocks; set `initialDelaySeconds` based on startup time
- **Readiness probe**: Determines when to receive traffic; keep `periodSeconds` short (5s)
- **Startup probe**: Allows slow-starting model servers to initialize without being killed

Production defaults (recommended):
```yaml
livenessProbe:
  initialDelaySeconds: 30  # Wait for model to load
  periodSeconds: 10        # Check regularly
  failureThreshold: 3      # Allow 30 seconds of failures before restart

readinessProbe:
  initialDelaySeconds: 10  # Quick initial check
  periodSeconds: 5         # Frequent checks for immediate response
  failureThreshold: 2      # Fail faster for traffic control

startupProbe:
  enabled: true           # Essential for slow-loading models
  periodSeconds: 10
  failureThreshold: 30    # Allow up to 5 minutes startup
```

#### 2. Resource Management
- Set `requests` based on sustained usage (for scheduling)
- Set `limits` 1.5-2x higher than requests (prevents OOMKill)
- Use HPA with both CPU and memory targets (production only)

Example:
```yaml
# Staging
resources:
  requests: {cpu: 250m, memory: 512Mi}
  limits: {cpu: 1, memory: 1Gi}

# Production
resources:
  requests: {cpu: 1, memory: 1Gi}
  limits: {cpu: 2, memory: 2Gi}
```

#### 3. High Availability
- Enable `podDisruptionBudget` in production (prevents accidental downtime)
- Use `minAvailable: 2` with 3+ replicas
- Deploy across multiple availability zones (node affinity)

#### 4. Image Pull Policy
- **Minikube**: `Never` (load image locally with `minikube image load`)
- **Remote registry**: `IfNotPresent` (pull if not cached) or `Always` (always pull)
- Minikube detection is automatic in `run-local-deploy.sh`

#### 5. Canary Deployments
- Canary release gets 10% traffic by default (configure via Ingress)
- Monitor metrics before promoting: success rate, latency, error rate
- Promote by scaling canary up and stable down, or switch traffic 100%→canary

```bash
# Monitor canary metrics
kubectl logs -n model-serving -l app.kubernetes.io/instance=model-release-canary -f

# Promote canary
helm upgrade model-release Model-Deployment/chart -f Model-Deployment/chart/values-production.yaml --set image.tag=<new-tag>
helm uninstall model-release-canary -n model-serving
```

#### 6. Deployment Tracking
- Annotations are automatically added:
  - `deployment.kubernetes.io/timestamp`: Deployment time
  - `git.commit`: Git commit SHA (if `GIT_COMMIT` provided)
  - `build.number`: CI/CD build number (if `BUILD_NUMBER` provided)
- Query deployment history:
  ```bash
  kubectl get pods -n model-serving -o json | jq '.items[].metadata.annotations'
  ```

### Monitoring and Troubleshooting

**Check deployment status:**
```bash
kubectl get deployments -n model-serving
kubectl get pods -n model-serving -o wide
khalse watch kubectl -n model-serving get pods  # Live monitoring
```

**View pod logs:**
```bash
kubectl logs -n model-serving <pod-name>
kubectl logs -n model-serving -l app.kubernetes.io/instance=model-release -f
```

**Describe pod (for error details):**
```bash
kubectl describe pod -n model-serving <pod-name>
```

**Check resource usage:**
```bash
kubectl top pods -n model-serving
kubectl top nodes
```

**Rollback to previous release:**
```bash
helm rollback model-release -n model-serving
```

**Delete deployment:**
```bash
helm uninstall model-release -n model-serving
```

### Best Practices Checklist

- [ ] Define CPU/memory requests for proper scheduling
- [ ] Configure health checks with appropriate delays
- [ ] Use `startupProbe` for slow-loading models
- [ ] Enable HPA in production with realistic targets
- [ ] Enable `podDisruptionBudget` for HA deployments
- [ ] Set image pull policy correctly for your cluster
- [ ] Use canary deploys for risky changes
- [ ] Monitor deployment metrics during rollout
- [ ] Test database migrations before deployment
- [ ] Document model version requirements
- [ ] Maintain separate values files per environment
- [values-production-canary.yaml](../../Model-Deployment/chart/values-production-canary.yaml)

### Secrets and variables to set in GitHub

- `KUBE_CONFIG_DATA`: base64-encoded kubeconfig
- `IMAGE_REPOSITORY`: repository to push your model image to
- `REGISTRY_HOST`: optional registry host reference for your own conventions

Important:

- the secret name must be exactly `KUBE_CONFIG_DATA`
- if you use GitHub Environments such as `staging` and `production`, add the secret to each environment that runs this workflow
- a differently named secret such as `Kube_Canfig_data` will not be picked up by the workflow
- CI validation does not require `KUBE_CONFIG_DATA`; the secret is only required for manual CD runs

Example for generating the value locally:

```bash
base64 < ~/.kube/config | tr -d '\n'
```

### About canary and shadow deployment

This starter implements the deployment side of a canary release by creating a separate canary Helm release. Traffic splitting is cluster-specific and is usually handled by an ingress controller, service mesh, or rollout controller such as Argo Rollouts.

Shadow deployment is also controller-specific. The most common implementation is request mirroring at the ingress or service-mesh layer. That is not baked into this repo because the exact manifest depends on whether you use NGINX Ingress, Istio, Linkerd, or another gateway.

An NGINX Ingress mirroring example was added at [shadow-ingress-nginx-example.yaml](../../Kubernetes/shadow-ingress-nginx-example.yaml). Update the host, namespace, and mirrored service name before using it.
