# ML Model Deployment

A collection of **independent, self-contained modules** covering how to package,
deploy, serve, and operate machine-learning models on containers and Kubernetes.
There is no shared build — each top-level directory is its own project with its
own README and tooling. Pick the module you need and follow its README.

## Modules

| Module | What it is | Start here |
|--------|-----------|-----------|
| **[Model-Deployment/](Model-Deployment/README.md)** | Flagship Helm chart + CI/CD implementing two ML deployment patterns (`deploy-code` / `deploy-models`): independent code/model lifecycles, catalog-segregated model stores, validation/compare gates with SLA load testing, online evaluation, scheduled training jobs, and real-time rollout strategies. | [Quick start](Model-Deployment/README.md#quick-start) |
| **[Helm-Chart/](Helm-Chart/README.md)** | Hardened production serving chart (`mychart`) with per-env values, security context, HPA/PDB, topology spread, and operator scripts for deploy/monitor/rollback. | [Quick reference](Helm-Chart/QUICK_REFERENCE.md) |
| **[LLM-Inference-vLLM/](LLM-Inference-vLLM/README.md)** | FastAPI + vLLM LLM-serving app with a CPU/mock mode, Prometheus metrics, and a load-test benchmark client. | [Quick start](LLM-Inference-vLLM/README.md) |
| **[Kubernetes/](Kubernetes/README.md)** | Standalone reference manifests (voting-app, cronjob, local model deploy/service, shadow-ingress). | — |
| **[Docker/](Docker/README.md)** | Docker + ML reference notes, a Dockerfile, and docker-compose. | — |
| **[Xinference/](Xinference/README.md)** | Xinference notebook and notes. | — |
| **[OpenClaw/](OpenClaw/README.md)** | Small agent Dockerfile and notes. | — |

## The two deployment patterns

The **Model-Deployment** module centers on the idea that **code and models have
independent lifecycles**:

- **deploy-code** (default) — promote one immutable container image
  dev→staging→prod; pull the model at runtime by version, updated independently of
  code. New-model validation + comparison happen in production (canary).
- **deploy-models** — promote the model *artifact* through the environments,
  validated in staging before production; inference/monitoring code rides its own
  deploy-code track. Suited to one-off / expensive-training models.

See [Model-Deployment/README.md](Model-Deployment/README.md) for the full guide,
and [docs/superpowers/](docs/superpowers/) for the design spec and implementation
plan behind it.

## Try the flagship module in one command

```bash
Model-Deployment/test.sh            # render checks → local cluster → install → helm test → CronJob
Model-Deployment/test.sh --render   # offline render + lint only (no cluster)
```

## Test GPU access in Colab

Google Colab is useful for checking CUDA and PyTorch GPU access, but it is not a
full Linux GPU host for validating Docker daemon changes such as
`nvidia-ctk runtime configure --runtime=docker` and `systemctl restart docker`.
Use a local Linux NVIDIA machine or GPU VM for the full NVIDIA Container Toolkit
Docker runtime test.

In a Colab notebook, enable a GPU runtime, then run:

```bash
!nvidia-smi
```

Check PyTorch CUDA access:

```python
import torch

print(torch.__version__)
print(torch.version.cuda)
print(torch.cuda.is_available())

if torch.cuda.is_available():
    print(torch.cuda.get_device_name(0))
    x = torch.randn(1024, 1024, device="cuda")
    print((x @ x).shape)
```

You can also try building the CUDA 12.4.1 Docker image in Colab:

```bash
!apt-get update -qq
!apt-get install -y -qq docker.io
!nohup dockerd > /tmp/dockerd.log 2>&1 &
!sleep 10
!docker info

%cd /content/ML-Model-Deployment
!docker build -t gpu-image-test Docker/gpu
!docker run --rm gpu-image-test python -c "import torch; print(torch.__version__, torch.version.cuda)"
```

This final GPU-in-container check may fail in Colab because Colab usually does
not expose a normal host Docker runtime:

```bash
!docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

## Repo conventions

- **Work via branch + PR**; `master` is the default branch.
- **Model-Deployment CI/CD runs through GitHub Actions at `.github/workflows/`**
  and delegates to the module's local scripts. Local deployments still use
  `Model-Deployment/test.sh` and `Model-Deployment/deploy/deploy.sh` directly.
  Older Helm-chart workflow templates remain under `.github/workflows-helm-chart/`.
- See **[CLAUDE.md](CLAUDE.md)** for module commands, architecture notes, and the
  non-obvious conventions in one place.
