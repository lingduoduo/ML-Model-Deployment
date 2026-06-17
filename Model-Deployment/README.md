# Model-Deployment

Self-contained Helm chart + CI/CD implementing **two ML deployment patterns** over
one chart, selected per release by `deploymentPattern`. Derived from the hardened
`Helm-Chart/mychart` (which it does not modify), it adds independent code/model
lifecycles, catalog-segregated model stores, validation/comparison gates with SLA
load testing, online evaluation, and real-time rollout strategies.

## Contents

- [Patterns](#patterns)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Configuration reference](#configuration-reference)
- [Catalog segregation](#catalog-segregation)
- [Real-time serving](#real-time-serving)
- [Scheduled jobs](#scheduled-jobs)
- [Install](#install)
- [Inspecting a release](#inspecting-a-release)
- [Validation / render checks](#validation--render-checks)
- [Promotion (CD)](#promotion-cd)
- [Local trial (minikube)](#local-trial-minikube)
- [Notes & gotchas](#notes--gotchas)

## Patterns

- **deploy-code** (default): the container image is promoted dev→staging→prod
  unchanged; the model is pulled at runtime by `model.version`, bumped
  independently of code. Validation + comparison vs the running prod model run
  **in production** (canary + `modelGate.mode=compare`).
- **deploy-models**: the *model artifact* (`model.version`) is promoted
  dev→staging→prod; it is **validated in staging** (`modelGate.mode=validate`)
  before prod. Inference/monitoring code rides the deploy-code path separately.
  Use for one-off / expensive-training models.

| Aspect | `deploy-code` | `deploy-models` |
|--------|---------------|-----------------|
| Unit promoted dev→staging→prod | container **image** | **model artifact** (`model.version`) |
| Model source per env | pulled from `modelStore` by version, independent of code | the promoted artifact |
| Where validation runs | **production** (compare vs current prod model, via canary) | **staging** (validation checks before prod) |
| Staging role | run code on a data **subset** | gate the model artifact before prod |

## Repository layout

```
Model-Deployment/
  README.md                         # this file
  chart/                            # the model-deployment Helm chart
    Chart.yaml                      # name: model-deployment, version 0.1.0
    values.yaml                     # defaults (all new features off)
    values-dev.yaml                 # dev catalog, open access
    values-staging.yaml             # staging catalog, SLA/load, subset scale
    values-production.yaml          # prod catalog, online-eval, HA
    values-production-canary.yaml   # challenger release (nameOverride: canary)
    templates/
      deployment.yaml               # serving Deployment + model-pull init container
      model-gate-job.yaml           # validate|compare gate (Helm hook Job)
      model-online-eval-cronjob.yaml# opt-in prod online evaluation
      traffic-routing.yaml          # Istio VirtualService / Gateway API HTTPRoute
      _helpers.tpl                  # model-deployment.* helpers + validation
      tests/test-connection.yaml    # `helm test` connectivity pod
      ...
    scripts/verify-render.sh        # lint+render+assert, both patterns × all envs
  cicd/
    ci.yml                          # lint+render verification
    cd-deploy-code.yml              # deploy-code promotion (canary → compare gate)
    cd-deploy-models.yml            # deploy-models promotion (staging validate gate)
  deploy/deploy.sh                  # shared helm upgrade --install wrapper
```

## Prerequisites

- **Helm** v3.15+ (built/tested on v4.1.x).
- **kubectl** + a Kubernetes cluster (any). For a local cluster see
  [Local trial](#local-trial-minikube).
- A model store / object bucket reachable from the cluster (S3/GCS/MLflow/…),
  plus a pull-credentials secret, **if** you set `modelStore.uri`.

## Configuration reference

Key values (see `chart/values.yaml` for the full set and inline docs):

| Value | Default | Purpose |
|-------|---------|---------|
| `deploymentPattern` | `deploy-code` | `deploy-code` \| `deploy-models` |
| `image.repository` / `image.tag` | `your-docker-registry/model-server` / `latest` | serving image; pin an immutable tag/digest per env |
| `model.name` / `model.path` | `sample-model` / `/models/model` | model identity + mount path the server reads |
| `model.version` | `""` | model version to serve; bump to ship a new model (rolls only the model) |
| `environment` | `""` | `dev` \| `staging` \| `production` (set per env file) |
| `modelStore.uri` | `""` | backend-agnostic base, e.g. `s3://ml-staging/model-server`; when set, an init container pulls `<uri>/<model.version>` |
| `modelStore.catalog` | `""` | `dev` \| `staging` \| `prod`; **must match** `environment` |
| `modelStore.pullSecretName` | `""` | credentials secret for the init container |
| `modelStore.pullCommand` | `[]` | override the default placeholder pull command for your backend |
| `modelGate.enabled` / `modelGate.mode` | `false` / `""` | gate Job; `validate` (staging, deploy-models) or `compare` (prod, deploy-code) |
| `modelGate.readinessChecks` | `true` | pre-flight config/deps/schema checks before load testing |
| `modelGate.sla.*` | `0` | `medianLatencyMs`, `p95LatencyMs`, `p99LatencyMs`, `minQps`, `errorRateMax` |
| `modelGate.load.*` | `0` / off | `peakQps`, `stress.{enabled,multiplier}` |
| `onlineEval.enabled` | `false` | opt-in prod CronJob re-scoring the live model |
| `onlineEval.{schedule,holdoutUri,driftAction}` | `0 * * * *` / `""` / `alert` | online-eval config |
| `rolloutStrategy` | `gradual` | `gradual` \| `ab-testing` \| `shadow` |
| `trafficRouting.provider` | `none` | `none` \| `istio` \| `gateway-api` |
| `trafficRouting.{abSplit,gradualSteps,challengerService}` | `50` / `[10,25,50,100]` / `""` | traffic weights + challenger service name (defaults to `<fullname>-canary`) |

With all defaults the chart renders the same shape as `mychart` and emits none of
the new objects (no init container, gate Job, CronJob, or routing object).

The chart **fails `helm template`/`install`** on: invalid `deploymentPattern`,
invalid `rolloutStrategy`, invalid `modelGate.mode` (when enabled),
`rolloutStrategy: shadow` with `trafficRouting.provider: none`, or a
`modelStore.catalog` that does not match `environment`.

## Catalog segregation

Each environment reads from its own model-store catalog. Access posture is
enforced out-of-band (IAM / bucket policy / service principal via
`modelStore.pullSecretName`); the chart pins the mapping and stamps a
`model.catalog` provenance annotation on every pod.

| Catalog | Example `modelStore.uri` | Write access | Read access |
|---------|--------------------------|--------------|-------------|
| **dev** | `s3://ml-dev/model-server` | open to developers | open |
| **staging** | `s3://ml-staging/model-server` | admins + CI service principals; may be temporary | enabled for debugging |
| **prod** | `s3://ml-prod/model-server` | small set of admins + service principals | grantable to non-prod |

Catalog↔environment mapping (asserted at render): `dev→dev`, `staging→staging`,
`production→prod`.

## Real-time serving

- **Pre-deployment testing** — the gate runs `modelGate.readinessChecks`
  (config/deps/input-schema) then load testing against `modelGate.sla` /
  `modelGate.load` (median/p95/p99 latency, QPS, peak, opt-in stress). A failed
  readiness check or missed SLA fails promotion.
- **Online evaluation** — opt-in prod `onlineEval` CronJob periodically re-scores
  the live model on fresh data and alerts or triggers refresh.
- **Rollout strategies** — `rolloutStrategy` = `gradual` | `ab-testing` |
  `shadow`, realized via mesh-optional `trafficRouting.provider`
  (`none` = canary release fallback; `istio` = VirtualService weights/mirror;
  `gateway-api` = HTTPRoute weights / RequestMirror).

## Scheduled jobs

Recurring batch / model-training jobs are declared as a list under
`scheduledJobs`; each entry renders one `CronJob` (`<release>-model-deployment-<name>`).
Empty by default (no CronJobs), so it is opt-in per environment. Per-entry fields:
`name`, `schedule` (required); `image`, `command`, `args`, `env`, `resources`,
`restartPolicy` (default `OnFailure`), `concurrencyPolicy` (default `Forbid`),
`backoffLimit` (default `0`), `suspend` (default `false`).

`values-dev.yaml` ships a worked example with staggered schedules (an
optimus-style crontab): cheap jobs on even hours, heavier jobs on odd hours, and
a periodic accuracy check:

```yaml
scheduledJobs:
  - name: click-model-lightgbm        # hours 0,2,4,...
    schedule: "0 0-23/2 * * *"
    image: ghcr.io/example/optimus:dev
    command: ["/opt/anaconda/bin/python"]
    args: ["/opt/optimus2/src/jobs/click_model_lightgbm_add_ccbin_job.py", "$(OPTIMUS_VERSION)"]
    env:
      - { name: PYTHONPATH, value: /opt/optimus2 }
      - { name: OPTIMUS_VERSION, value: dev }
  - name: conversion-first-success    # hours 1,3,5,...
    schedule: "0 1-23/2 * * *"
    # ...
  - name: click-model-new-widget      # daily 02:30, heavier resources
    schedule: "30 2 * * *"
    # ...
  - name: model-accuracy-check        # every 8 hours
    schedule: "0 */8 * * *"
    # ...
```

Inspect them:

```bash
kubectl get cronjob -n <ns>
kubectl get jobs,pods -n <ns> -l model-deployment.io/scheduled-job=click-model-lightgbm
# trigger one immediately for testing:
kubectl create job --from=cronjob/<release>-model-deployment-model-accuracy-check adhoc-check -n <ns>
```

Jobs use the chart's serving image unless `image` is set per entry, and inherit
the non-root / read-only-rootfs security context — a job that writes outside
`/tmp` needs extra `volumes`/`volumeMounts` or a relaxed `readOnlyRootFilesystem`.

## Install

Run from the repo root. The chart lives at `Model-Deployment/chart` (name:
`model-deployment`).

**Minimal** (defaults: deploy-code, no model store, no gates):

```bash
helm install my-release Model-Deployment/chart
```

**Per-environment** with the values the chart expects:

```bash
helm install model-release Model-Deployment/chart \
  -f Model-Deployment/chart/values-staging.yaml \
  --set image.repository=ghcr.io/example/model-server \
  --set image.tag=<immutable-tag> \
  --set model.version=<model-version>
```

Swap in `values-dev.yaml` / `values-production.yaml` as needed.

**Preview without a cluster, or client-side dry run:**

```bash
helm template my-release Model-Deployment/chart -f Model-Deployment/chart/values-staging.yaml
helm install  my-release Model-Deployment/chart -f Model-Deployment/chart/values-staging.yaml --dry-run=client
```

**Upgrade** (same syntax via `helm upgrade --install`). Independent lifecycles:

```bash
# Ship a new model only (rolls just the model):
helm upgrade model-release Model-Deployment/chart -f Model-Deployment/chart/values-staging.yaml \
  --reuse-values --set model.version=<new-version>

# Ship new code only (rolls just the image):
helm upgrade model-release Model-Deployment/chart -f Model-Deployment/chart/values-staging.yaml \
  --reuse-values --set image.tag=<new-tag>
```

**Run the bundled connection test** (`templates/tests/test-connection.yaml`):

```bash
helm test model-release -n <namespace>
```

## Inspecting a release

```bash
kubectl get pods -n <ns> -o wide
kubectl get pods -n <ns> -l app.kubernetes.io/instance=<release>     # just this release
kubectl get deploy,svc,cronjob,job -n <ns>

# init container (model fetch) logs
POD=$(kubectl get pod -n <ns> -l app.kubernetes.io/instance=<release> -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n <ns> "$POD" -c model-pull

# model provenance annotations
kubectl get pod -n <ns> "$POD" \
  -o jsonpath='{.metadata.annotations.model\.version}{"  "}{.metadata.annotations.model\.catalog}{"\n"}'

# gate Job output / rollout
kubectl logs job/<release>-model-deployment-gate-compare -n <ns>
kubectl rollout status deploy/<release>-model-deployment -n <ns>
```

What you may see per release: the serving Deployment pod (with a `model-pull`
**initContainer** when `modelStore.uri` is set); a `gate-<mode>` **hook Job** when
`modelGate.enabled`; a `<release>-canary` pod when deployed with
`DEPLOY_VARIANT=canary`; `online-eval` CronJob pods (prod, on schedule); and the
`test-connection` pod after `helm test`.

## Validation / render checks

Lint + render every env file for **both** patterns and assert all invariants
(security hardening, init container + catalog annotation present, determinism),
negative cases (bad pattern/strategy/mode, shadow+none, catalog mismatch), and
feature toggles:

```bash
bash Model-Deployment/chart/scripts/verify-render.sh
# => All assertions passed.
```

CI runs the same script (`cicd/ci.yml`).

## Promotion (CD)

The intended path is the wrapper, not raw `helm install`. `deploy/deploy.sh`
selects the env values file and wires pattern/gate/rollout from env vars, via
`helm upgrade --install` (safe for first install and updates).

```bash
DEPLOY_ENVIRONMENT=staging \      # dev | staging | production  (required)
DEPLOYMENT_PATTERN=deploy-code \  # deploy-code | deploy-models (required)
IMAGE_REPOSITORY=ghcr.io/example/model-server \  # required
IMAGE_TAG=<immutable-tag> \       # required
MODEL_VERSION=<model-version> \   # required
ROLLOUT_STRATEGY=gradual \        # optional (gradual|ab-testing|shadow)
GATE_ENABLED=true GATE_MODE=compare \  # optional
DEPLOY_VARIANT=canary \           # optional: production-only; deploys <release>-canary from values-production-canary.yaml
RELEASE_NAME=model-release KUBE_NAMESPACE=model-serving \  # optional overrides
bash Model-Deployment/deploy/deploy.sh
```

The two GitHub Actions workflows (manual `workflow_dispatch`, gated dev→staging→prod):

- **`cicd/cd-deploy-code.yml`** — promotes the same image dev→staging→prod;
  production deploys the canary (`DEPLOY_VARIANT=canary`) then runs the in-prod
  `compare` gate. Inputs: `image_repository`, `image_tag`, `model_version`,
  `rollout_strategy`.
- **`cicd/cd-deploy-models.yml`** — promotes the model artifact dev→staging→prod;
  staging runs the `validate` gate before the prod deploy. Inputs:
  `image_repository`, `image_tag`, `model_version`.

> Note: these workflow files live under `Model-Deployment/cicd/` (the repo's
> convention), so GitHub Actions does not auto-discover them from
> `.github/workflows/`. Run them via `gh workflow run` against a copy placed in
> `.github/workflows/`, or invoke `deploy/deploy.sh` directly.

## Local trial (minikube)

The fastest path is the bundled script, which does everything below
automatically (render checks → cluster → install → verify → `helm test` →
exercise a CronJob). It resolves paths relative to itself, so run it from anywhere:

```bash
Model-Deployment/test.sh            # full flow on a local cluster
Model-Deployment/test.sh --render   # offline render + lint checks only (no cluster)
Model-Deployment/test.sh --cleanup  # uninstall release + delete the cluster
```

The manual equivalent follows. Spin up a throwaway cluster and run the chart with
a shell-capable image so the `model-pull` init container and the
read-only-rootfs / non-root security context all work. `busybox` is used because
the init container's default command needs a shell (a from-scratch image like
`traefik/whoami` fails with `Init:RunContainerError`).

```bash
# Cluster (Colima provides the docker runtime on macOS; or use Docker Desktop):
colima start
minikube start --driver=docker

# Install with a runnable image; busybox httpd serves /health, /ready, / on :8080
helm upgrade --install demo Model-Deployment/chart \
  -n model-demo --create-namespace \
  -f Model-Deployment/chart/values-staging.yaml \
  --set image.repository=busybox --set image.tag=1.36 \
  --set model.version=2026-06-01 \
  --set-string 'container.command[0]=/bin/sh' \
  --set-string 'container.command[1]=-c' \
  --set-string 'container.command[2]=mkdir -p /tmp/www && printf ok > /tmp/www/health && printf ok > /tmp/www/ready && printf hello > /tmp/www/index.html && httpd -f -p 8080 -h /tmp/www'

kubectl rollout status deploy/demo-model-deployment -n model-demo
kubectl get pods -n model-demo -o wide
helm test demo -n model-demo
```

**Teardown:**

```bash
helm uninstall demo -n model-demo
minikube delete
colima stop
```

## Notes & gotchas

- **Read-only root filesystem** is on by default; a writable `emptyDir` is mounted
  at `/tmp` (`writableTmp.enabled`). A process that writes elsewhere will fail —
  add `volumes`/`volumeMounts` or set `securityContext.readOnlyRootFilesystem=false`.
- **Init container needs a shell.** The default `modelStore.pullCommand` is a
  documented placeholder (`/bin/sh -c …` echo + override hint). Provide a real
  backend command via `modelStore.pullCommand`, and use an image that contains the
  pull tooling. Shell-less scratch images fail the init container.
- **Pin immutable image tags** per environment for safe rollback; `latest` is a
  non-production default only.
- **`Helm-Chart/mychart` is untouched** — this is a separate, self-contained chart.
