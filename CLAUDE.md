# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of **independent, self-contained modules** exploring ML model
deployment and serving infrastructure. There is no root build system or shared
dependency graph — each top-level directory is its own project with its own
README and tooling. Work within one module at a time; changes in one rarely
affect another.

| Module | What it is |
|--------|-----------|
| `Model-Deployment/` | Flagship Helm chart + CI/CD implementing two ML deployment patterns (`deploy-code` / `deploy-models`). Derived from `Helm-Chart/mychart` without modifying it. |
| `Helm-Chart/mychart` | Hardened production serving chart (security context, HPA/PDB, topology spread, checksum rollout) with env values + `deploy/` operator scripts. |
| `LLM-Inference-vLLM/` | FastAPI + vLLM LLM serving app with a CPU/mock mode, Prometheus metrics, and a load-test benchmark client. |
| `Kubernetes/` | Standalone raw manifests (voting-app, cronjob, local model deploy/service, shadow-ingress example) — teaching/reference, not wired to the charts. |
| `Docker/` | Docker + ML reference notes, a Dockerfile, and docker-compose. |
| `Xinference/`, `OpenClaw/` | Notebook/notes and a small agent Dockerfile, respectively. |
| `docs/superpowers/` | Design specs (`specs/`) and implementation plans (`plans/`) authored via the spec-driven workflow. |

## Repo-wide conventions (important, non-obvious)

- **Model-Deployment CI/CD is now under `.github/workflows/`.** The runnable
  workflows are thin GitHub Actions wrappers that call
  `Model-Deployment/test.sh --render` and `Model-Deployment/deploy/deploy.sh`.
  Local deployment remains script-first. Older Helm-chart workflow templates
  still live in `.github/workflows-helm-chart/`.
- **Helm charts have no `values.schema.json`.** IDE/YAML language servers emit
  "Property X is not allowed" errors for custom values (`deploymentPattern`,
  `modelStore`, `modelGate`, `scheduledJobs`, etc.) — these are **false
  positives**. `helm lint`/`helm template` are the source of truth.
- **Spec-driven changes**: substantial features are designed in
  `docs/superpowers/specs/YYYY-MM-DD-*.md` and planned in
  `docs/superpowers/plans/` before implementation.
- **Branch + PR workflow**: `master` is the default branch; land changes via a
  feature branch and PR, not direct commits to `master`. Commit messages end with
  a `Co-Authored-By` trailer.
- `CHANGELOG.md` is auto-generated (`git log --pretty="- %s" > CHANGELOG.md`);
  don't hand-edit it.

## Model-Deployment (the chart most work touches)

A single chart whose behavior is selected per release by `deploymentPattern`
(`deploy-code` | `deploy-models`). Architecture worth knowing before editing:

- **One accumulator validator.** `templates/_helpers.tpl` defines
  `model-deployment.validate`, invoked once at the top of `deployment.yaml`. It
  rejects (via `fail`) invalid `deploymentPattern`, invalid `rolloutStrategy`,
  invalid `modelGate.mode` (when the gate is enabled), `rolloutStrategy: shadow`
  with `trafficRouting.provider: none`, and any `modelStore.catalog` that doesn't
  match `environment` (mapping: `dev→dev`, `staging→staging`, `production→prod`).
  When adding a new validated value, extend this single define — don't add a new one.
- **Backward-safe defaults.** With defaults (no `modelStore.uri`, gates/online-eval
  off, `provider: none`, empty `scheduledJobs`) the chart renders the same shape
  as `mychart` and emits none of the optional objects (init container, gate Job,
  CronJobs, routing object). Preserve this when adding features — guard new
  templates behind their enabling value.
- **Independent code/model lifecycle**: image promoted via `image.tag`; model
  pulled at runtime via `model.version` + `modelStore.uri` (an init container).
  Bumping one must not roll the other.
- **Per-env values** (`values-dev/staging/production/production-canary.yaml`) carry
  catalog + SLA + online-eval; `deploymentPattern`/gate/rollout are set at deploy
  time by CD, not hard-coded in env files.
- The init container's default `modelStore.pullCommand` and the gate Job's default
  command are **documented placeholders** (backend-agnostic, meant to be
  overridden) — not defects.

### Commands

```bash
# Lint + render every env file for BOTH patterns and assert all invariants:
bash Model-Deployment/chart/scripts/verify-render.sh        # => All assertions passed.

# Full local end-to-end (render checks -> minikube via Colima -> install -> helm test -> CronJob):
Model-Deployment/test.sh                # full flow
Model-Deployment/test.sh --render       # offline render+lint only, no cluster
Model-Deployment/test.sh --cleanup      # uninstall + delete cluster

# Render a single env (use ./chart, or full path from repo root — a bare path is read as a repo name):
helm template demo Model-Deployment/chart -f Model-Deployment/chart/values-staging.yaml
helm install  demo Model-Deployment/chart -f Model-Deployment/chart/values-staging.yaml --dry-run=client

# Deploy via the wrapper (selects env values + wires pattern/gate/rollout from env vars):
DEPLOY_ENVIRONMENT=staging DEPLOYMENT_PATTERN=deploy-code \
  IMAGE_REPOSITORY=... IMAGE_TAG=... MODEL_VERSION=... \
  bash Model-Deployment/deploy/deploy.sh
```

There is no unit-test framework — `verify-render.sh` (helm template + grep
assertions, both patterns × all envs, incl. negative cases) is the regression gate.

## Helm-Chart/mychart

```bash
bash Helm-Chart/mychart/scripts/verify-render.sh            # render assertions
./Helm-Chart/deploy/validate-deployment.sh                  # preflight checks
DEPLOY_ENVIRONMENT=production DEPLOY_STRATEGY=canary ./Helm-Chart/deploy/run-local-deploy.sh
./Helm-Chart/deploy/monitor-deployment.sh                   # live dashboard
./Helm-Chart/deploy/rollback-deployment.sh                  # interactive rollback
```
Default release/namespace used by the scripts: `model-release` / `model-serving`.

## LLM-Inference-vLLM

FastAPI app (`app/main.py` serving, `app/engine.py` vLLM wrapper with a mock
fallback, `app/config.py` env-driven settings, `app/metrics.py` Prometheus).
Runs without a GPU in mock mode.

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r LLM-Inference-vLLM/requirements-cpu.txt        # or requirements.txt for GPU/vLLM
cd LLM-Inference-vLLM
USE_MOCK_LLM=true uvicorn app.main:app --host 0.0.0.0 --port 8000   # or: scripts/run_server.sh
python benchmarks/benchmark_api.py --url http://localhost:8000/generate --concurrency 8 --requests 32
```
Key env vars: `USE_MOCK_LLM`, `MODEL_NAME`, `DTYPE`, `GPU_MEMORY_UTILIZATION`,
`MAX_BATCH_SIZE`, `BATCH_TIMEOUT_MS`.

## Local cluster note

No Kubernetes cluster runtime is preinstalled. The local-trial paths use **Colima**
(`colima start`) as the docker runtime + **minikube** (`minikube start --driver=docker`).
For Helm-chart workloads in trials, use a shell-capable image (e.g. `busybox`) —
a from-scratch image (e.g. `traefik/whoami`) breaks the `model-pull` init container
(`Init:RunContainerError`) because its default command needs `/bin/sh`.
