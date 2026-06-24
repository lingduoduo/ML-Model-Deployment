# ML Model Deployment

A collection of **independent, self-contained modules** covering how to package,
deploy, serve, and operate machine-learning models on containers and Kubernetes.
There is no shared build — each top-level directory is its own project with its
own README and tooling. Pick the module you need and follow its README.

## Modules

| Module | What it is | Start here |
|--------|-----------|-----------|
| **[Model-Deployment/](Model-Deployment/README.md)** | Flagship Helm chart + CI/CD implementing two ML deployment patterns (`deploy-code` / `deploy-models`): independent code/model lifecycles, catalog-segregated model stores, validation/compare gates with SLA load testing, online evaluation, scheduled training jobs, and real-time rollout strategies. | [Quick start](Model-Deployment/README.md#quick-start) |
| **[Helm-Chart/](Helm-Chart/README.md)** | Operator scripts (deploy / validate / monitor / rollback) that target the canonical `Model-Deployment/chart`. The former standalone `mychart` chart was folded into that chart during consolidation. | [Quick reference](Helm-Chart/QUICK_REFERENCE.md) |
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

## Repo conventions

- **Work via branch + PR**; `master` is the default branch.
- **CI/CD workflows live outside `.github/workflows/`** (under
  `.github/workflows-helm-chart/` and `Model-Deployment/cicd/`), so they are run
  manually rather than auto-triggered.
- See **[CLAUDE.md](CLAUDE.md)** for module commands, architecture notes, and the
  non-obvious conventions in one place.
