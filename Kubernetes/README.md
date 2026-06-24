## Kubernetes

Kubernetes manifests for local testing and deployment patterns.

### Folder contents

| File / Folder | Purpose |
|---|---|
| `local-model-deployment.yaml` | Deployment for local Minikube testing |
| `local-model-service.yaml` | ClusterIP Service for local Minikube testing |
| `shadow-ingress-nginx-example.yaml` | Ingress with nginx mirror (shadow) routing |
| `cronjob.yaml` | CronJob example (batch job every 15 minutes) |
| `Voting-app/` | Multi-service example app (redis, postgres, voting, result, worker) |
| `notes/` | Reference YAML examples and Kubernetes concepts |

### Local test flow

Prerequisites: Minikube running and the image built inside Minikube's Docker daemon.

```bash
# Point the shell at Minikube's Docker daemon, then build
eval $(minikube -p minikube docker-env)
docker build -t ling-mlops-sandbox:latest ~/Git/Recommendation/TFRecommenders-MLops-Sandbox
docker image ls | grep ling-mlops-sandbox
```

The `eval` only affects the current shell — build the image in the same terminal.

```bash
# Apply manifests (run from repo root)
kubectl apply -f Kubernetes/local-model-deployment.yaml
kubectl apply -f Kubernetes/local-model-service.yaml

# Check workload
kubectl get deploy,pods,svc
kubectl logs deploy/local-model-deployment

# Watch pod start-up
kubectl get pods -w
```

If the pod shows `ErrImageNeverPull`, the image is not in Minikube's runtime — rerun the `eval` + `docker build` step in the same shell.

```bash
# Port-forward and test
kubectl port-forward svc/local-model-service 8080:8080
```

In another terminal:

```bash
curl http://localhost:8080/health

curl -X POST http://localhost:8080/predict \
  -H "Content-Type: application/json" \
  -d '{"user_id":"u1","top_k":5}'
```

Clean up:

```bash
kubectl delete -f Kubernetes/local-model-service.yaml
kubectl delete -f Kubernetes/local-model-deployment.yaml
```

### Docker → Kubernetes mapping

| Docker | Kubernetes equivalent |
|---|---|
| `docker run -p 8080:8080 ...` | `helm upgrade --install ...` + `kubectl port-forward` |
| `docker logs <container>` | `kubectl logs -n model-serving deploy/model-release-model-deployment` |
| `docker exec -it <container> sh` | `kubectl exec -it -n model-serving deploy/model-release-model-deployment -- sh` |

### Traffic pattern

- `Deployment` runs the serving pods
- `Service` with `ClusterIP` load-balances internally across replicas
- `Ingress` handles external access, TLS, canary, or shadow routing — see [`shadow-ingress-nginx-example.yaml`](shadow-ingress-nginx-example.yaml)

### Moving to Helm

After raw manifest tests pass, use Helm for full deployments:

- [Helm chart guide](../Helm-Chart/README.md)
- [Root deployment guide](../README.md)
