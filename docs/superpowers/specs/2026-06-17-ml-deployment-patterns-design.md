# ML Deployment Patterns (deploy-code + deploy-models) — Design Spec

**Date:** 2026-06-17
**Scope:** New self-contained `Model-Deployment/` folder
**Status:** Pending implementation plan

## Goal

Implement **both** ML deployment patterns from the reference visuals over a
single Helm chart, selectable per release via a `deploymentPattern` flag:

- **`deploy-code`** — code and model have *independent lifecycles*. The
  container image is promoted dev → staging → production unchanged; the model is
  a separately-versioned artifact pulled at runtime. Code is tested in staging
  on a data **subset** and executed in production on full data. New-model
  **validation and comparison against the running production model both happen
  in production**.
- **`deploy-models`** — the *model artifact* is the unit that is promoted dev →
  staging → production. The model is produced upstream (training is already
  periodic/external), **validated in staging** with model-validation checks, and
  then deployed to production. Ancillary code (inference/monitoring) rides a
  **separate** deploy-code lifecycle. Suited to one-off or expensive-training
  models.

All artifacts live in a new top-level **`Model-Deployment/`** folder —
self-contained, so `Helm-Chart/mychart` is not edited in place. The chart is
derived from the hardened `mychart` (inherits its security context, topology
spread, ephemeral-storage, and checksum-based rollout) and adds the
model-lifecycle, pattern-selection, and validation-gate features below.

## Out of scope

- **Model training execution and storage** — handled by a periodic external
  pipeline. This spec *consumes* already-produced model artifacts (in both
  patterns the artifact is built upstream; the chart never trains).
- Raw manifests under `Kubernetes/`, the `LLM-Inference-vLLM/` stack, Docker,
  Xinference, OpenClaw.
- Choice of model-registry backend (S3 / GCS / MLflow / etc.) — configurable
  via `modelStore.uri`; no backend is hard-coded.

## The two patterns side by side

| Aspect | `deploy-code` | `deploy-models` |
|--------|---------------|-----------------|
| Unit promoted dev→staging→prod | container **image** (immutable) | **model artifact** (`model.version`) |
| Model source per env | pulled from `modelStore` by version, set independently of code | the promoted artifact; version advances through envs |
| Code (inference/monitoring) | promoted together with the serving image | **separate** deploy-code path for ancillary code |
| Where validation runs | **production** (validate + compare vs current prod model, via canary) | **staging** (model-validation checks before prod) |
| Staging role | run code on a data **subset** | gate the model artifact before prod |
| Typical use | frequent code changes, model updated independently | one-off / expensive-training models |

Both patterns share the **same serving chart and model-loading mechanics**
(below). They differ only in (a) what the CD pipeline promotes and (b) where the
validation gate Job runs. The `deploymentPattern` value selects the behavior.

## Design

### 1. Pattern selector

New top-level value:

```yaml
# deploy-code | deploy-models
deploymentPattern: deploy-code
```

It drives template conditionals (which gate Job renders, default annotations)
and is read by the CD pipelines to pick the promotion flow. Invalid values fail
template rendering with a clear message (helper `fail`).

### 2. Environments

Three first-class environments, each its own namespace + GitHub Environment:

| Env | Values file | `deploy-code` role | `deploy-models` role |
|-----|-------------|--------------------|----------------------|
| dev | `values-dev.yaml` *(new)* | smoke test code, 1 replica | model produced/registered upstream; smoke load |
| staging | `values-staging.yaml` | run code on data **subset** | **model-validation checks** before prod |
| production | `values-production.yaml` (+`-canary`) | full scale; canary + **compare vs current prod model** | full scale; deploy validated model |

`values-dev.yaml` is the only new env file; staging/production/canary already
exist and are carried into the new chart.

### 3. Model loading (shared by both patterns)

New values block in the chart's `values.yaml`:

```yaml
modelStore:
  uri: ""              # backend-agnostic base, e.g. s3://models-bucket/model-server
  pullSecretName: ""   # optional credentials secret for the init container
model:
  name: sample-model
  path: /models/model  # mount the server reads from
  version: ""          # the model version to serve
  pullPolicy: IfNotPresent
```

- An **init container** in `deployment.yaml` pulls
  `<modelStore.uri>/<model.version>` into the `/models` mount before the server
  starts. When `modelStore.uri` is empty the init container is omitted (image-
  baked / PVC-preloaded models still render).
- `model.version` is surfaced as a pod annotation so the chart's existing
  checksum/rollout machinery yields exactly **one** controlled rollout when the
  model version changes, and none when it does not.

The difference between patterns is **how `model.version` advances**:

- **`deploy-code`**: an operator/CD bumps `model.version` per environment
  independently of the image — a new prod model ships with no code change.
- **`deploy-models`**: `model.version` is the promoted unit — the same version
  moves dev → staging → prod as it passes each gate; the image stays fixed.

### 4. Code lifecycle

- **`deploy-code`**: the same immutable serving image is promoted dev → staging
  → production by tag/digest; CD never rebuilds per env. Data-scale differences
  (subset in staging, full in prod) live in env values, not in code.
- **`deploy-models`**: the serving/inference/monitoring image follows its **own**
  deploy-code promotion (tested in staging, deployed to prod) on a cadence
  independent of the model artifact. The spec documents this as a distinct CD
  flow; the chart treats the image as a normal promoted artifact.

### 5. Validation gates

A single Job template `templates/model-gate-job.yaml`, parametrized by mode and
gated to render only in the appropriate environment:

```yaml
modelGate:
  enabled: false        # turned on in the gating env per pattern
  mode: ""              # validate | compare
  holdoutUri: ""        # dataset/metrics source for the check
  verdictSink: ""       # where pass/fail + metric deltas are written
```

- **`deploy-code`** → `mode: compare`, enabled in **production**. The new model
  rolls out as a **canary** (reusing `values-production-canary.yaml`); the Job
  scores candidate vs the current production model on the holdout/live metric
  set and gates **promote-or-rollback**. Validation + comparison run entirely in
  production (matches the deploy-code visual's third bullet).
- **`deploy-models`** → `mode: validate`, enabled in **staging**. The Job runs
  model-validation checks on the promoted artifact before it is allowed to
  promote to production (matches the deploy-models visual's first bullet).
  No compare-vs-prod, since validation precedes prod.

Default `modelGate.enabled: false` so base renders carry no Job.

### 6. CD pipelines

Two pipeline definitions under `Model-Deployment/cicd/`, chosen by
`deploymentPattern`:

- **`cd-deploy-code.yml`**: deploy image to dev → smoke → promote same image to
  staging → integration test on subset → manual approval → production (standard
  or canary) → in-prod compare gate.
- **`cd-deploy-models.yml`**: register/stage model version in dev → promote
  artifact to staging → run `mode: validate` gate → manual approval → deploy
  validated model to production. Ancillary code changes flow through
  `cd-deploy-code.yml` separately.

`ci.yml` lints and templates all env values for **both** pattern values.

### 7. Folder layout & deliverables

```
Model-Deployment/
  README.md                         # both patterns, when to use each, how promotion works
  chart/
    Chart.yaml                      # name: model-deployment, version 0.1.0
    values.yaml                     # + deploymentPattern / modelStore / model.version / modelGate
    values-dev.yaml                 # NEW
    values-staging.yaml
    values-production.yaml
    values-production-canary.yaml
    templates/
      deployment.yaml               # + model-pull init container, model.version annotation
      model-gate-job.yaml           # NEW, validate|compare, env-gated
      _helpers.tpl                  # + deploymentPattern validation helper
      ... (inherited templates)
    scripts/verify-render.sh        # inherited assertions, extended
  cicd/
    ci.yml                          # lint + template, both patterns, all envs
    cd-deploy-code.yml              # deploy-code promotion flow
    cd-deploy-models.yml            # deploy-models promotion flow
  deploy/                           # promotion / rollback helper scripts
```

### 8. Chart hygiene & verification

- New chart `Chart.yaml`: `name: model-deployment`, `version: 0.1.0`.
- `ci.yml` runs `helm lint` + `helm template` across dev/staging/production/
  canary for **both** `deploymentPattern` values via `verify-render.sh`.
  Render assertions:
  - init container present iff `modelStore.uri` set;
  - `model.version` pod annotation reflects configured version;
  - `model-gate-job.yaml` renders only when `modelGate.enabled: true`, with the
    correct `mode` per pattern (compare in prod for deploy-code; validate in
    staging for deploy-models);
  - invalid `deploymentPattern` fails rendering;
  - inherited security-context / checksum assertions still pass;
  - renders are deterministic (byte-identical on repeat with identical inputs).

## Backward compatibility

- New folder; nothing in `Helm-Chart/mychart` changes, so existing releases are
  unaffected.
- All new values default safely: `deploymentPattern: deploy-code`, empty
  `modelStore.uri` omits the init container, `modelGate.enabled: false` omits the
  Job. A chart with no model values renders the same shape as hardened `mychart`.

## Verification

- `helm lint Model-Deployment/chart -f <each values file>` passes for both
  patterns.
- `helm template` renders cleanly for dev/staging/production/canary under both
  `deploymentPattern` values.
- Init container appears/disappears with `modelStore.uri`; gate Job
  appears/disappears with `modelGate.enabled` and carries the right `mode`.
- Bumping `model.version` alone changes only the model annotation/init args;
  bumping `image.tag` alone changes only the image (proves independence in
  `deploy-code`).
- Invalid `deploymentPattern` produces a clear render failure.
- `scripts/verify-render.sh` assertions pass.
