# Deploy-Code Promotion Pattern for ML Model Serving — Design Spec

**Date:** 2026-06-17
**Scope:** New self-contained `Model-Deployment/` folder
**Status:** Pending implementation plan

## Goal

Implement the **"deploy code"** ML deployment pattern from the reference visual:
code and models progress through **dev → staging → production** on
*independent lifecycles*. Training code is developed in dev, tested in staging
on a data subset, and executed in production on full data; a new production
model can be shipped **without a code change**, and new code can be shipped
without changing the model. Model validation and comparison against the
currently-running production model both happen **inside production**.

All artifacts for this spec live in a new top-level **`Model-Deployment/`**
folder — self-contained, so the existing `Helm-Chart/mychart` is not edited in
place. The chart under `Model-Deployment/` is derived from the hardened
`mychart` (it inherits its security context, topology spread, ephemeral-storage,
and checksum-based rollout work) and adds the model-lifecycle and promotion
features below.

## Out of scope

- **Model training and storage** — already handled by a periodic external
  pipeline. This spec only *consumes* already-stored model artifacts.
- Raw manifests under `Kubernetes/`, the `LLM-Inference-vLLM/` stack, Docker,
  Xinference, and OpenClaw.
- Choice of model-registry backend (S3 / GCS / MLflow / etc.) — left
  configurable through `modelStore.uri`; no backend is hard-coded.
- The training-side "deploy models" alternative strategy (the visual's opposing
  pattern) — only "deploy code" is implemented.

## Core principle

Code and model are **separately-versioned artifacts**:

| Artifact | Versioned by | Promotion mechanism | Triggers rollout when |
|----------|--------------|---------------------|-----------------------|
| Code     | container image tag/digest | same immutable image promoted dev→staging→prod | `image.tag` changes |
| Model    | `model.version` value | model version bumped per env, independent of code | `model.version` changes |

Bumping one never forces a rebuild or re-promotion of the other.

## Design

### 1. Environments

Three first-class environments, each its own namespace + GitHub Environment:

| Env | Values file | Scale / data | Image tags | HA features | Model gate |
|-----|-------------|--------------|-----------|-------------|------------|
| dev | `values-dev.yaml` *(new)* | 1 replica, smoke only | `latest` allowed | none | none |
| staging | `values-staging.yaml` | subset-scale config, integration tests on data **subset** | immutable tag | optional | validation only |
| production | `values-production.yaml` (+ `values-production-canary.yaml`) | **full** scale | immutable tag/digest | HPA + PDB + topology spread | canary + comparison Job |

`values-dev.yaml` is the only new env file; staging/production/canary already
exist and are carried into `Model-Deployment/`.

### 2. Independent model lifecycle

New values block in the chart's `values.yaml`:

```yaml
modelStore:
  # Registry / object-store base URI. Backend-agnostic (s3://, gs://, https://, etc.).
  uri: ""              # e.g. s3://models-bucket/model-server
  pullSecretName: ""   # optional credentials secret for the init container
model:
  name: sample-model
  path: /models/model  # existing mount the server reads from
  version: ""          # e.g. 2026-06-01 or v3 — bump to ship a new model
  pullPolicy: IfNotPresent
```

- An **init container** in `deployment.yaml` pulls
  `<modelStore.uri>/<model.version>` into the existing `/models` mount (an
  `emptyDir` or the existing `persistence` PVC) before the server container
  starts. When `modelStore.uri` is empty the init container is omitted, so the
  chart still renders for image-baked or PVC-preloaded models.
- The model version is surfaced as a pod annotation
  (`model.version: <value>`) so the chart's existing checksum/rollout machinery
  produces exactly **one** controlled rollout when the model version changes and
  no rollout when it does not.

### 3. Code promotion (deploy-code)

- The **same immutable image + chart revision** flows dev → staging →
  production. CD promotes by tag/digest and never rebuilds per environment.
- Per the visual: **staging exercises the code on a data subset**, **production
  runs it on full data**. The data-scale difference is expressed purely in env
  values (replica count, subset config/env vars), not in code or image.
- Extend the CD pipeline (`Model-Deployment/cicd/cd.yml`) into a gated
  promotion flow:
  1. Deploy to **dev** → run smoke test.
  2. Promote to **staging** (same image) → run integration test against the
     data subset.
  3. **Manual approval** gate.
  4. Deploy to **production** (same image) via the standard or canary strategy.

### 4. Production validation + model comparison (all in production)

- A new production model first rolls out as a **canary** alongside the current
  production model, reusing `values-production-canary.yaml`.
- A new **comparison Job** template (`templates/model-compare-job.yaml`,
  **opt-in via `modelCompare.enabled`, default `false`, enabled in production**)
  runs inside the production environment. It:
  - loads the candidate model version and the current production model version,
  - scores both on a configured holdout / live-metric set,
  - writes a verdict (pass/fail with metric deltas) to a configurable sink,
  - gates **promote-or-rollback**: on pass, the candidate is promoted to the
    main production deployment; on fail, the canary is rolled back.
- Validation and comparison therefore run **entirely in production**, matching
  the visual's third bullet. Staging performs validation only (no
  compare-against-prod), since the production model exists only in production.

### 5. Folder layout & deliverables

Everything under the new `Model-Deployment/` folder:

```
Model-Deployment/
  README.md                         # pattern overview + how code/model promote
  chart/                            # Helm chart derived from mychart
    Chart.yaml                      # name: model-deployment, version 0.1.0
    values.yaml                     # + modelStore / model.version / modelCompare
    values-dev.yaml                 # NEW
    values-staging.yaml             # subset-scale
    values-production.yaml
    values-production-canary.yaml
    templates/
      deployment.yaml               # + model-pull init container, model.version annotation
      model-compare-job.yaml        # NEW, opt-in
      ... (inherited templates)
    scripts/verify-render.sh        # inherited render assertions, extended
  cicd/
    cd.yml                          # gated dev→staging→prod promotion
    ci.yml                          # lint + template all env values
  deploy/                           # promotion / rollback helper scripts
```

### 6. Chart hygiene & verification

- New chart `Chart.yaml`: `name: model-deployment`, `version: 0.1.0`.
- CI (`Model-Deployment/cicd/ci.yml`) runs `helm lint` + `helm template`
  against **all** env values files (dev, staging, production, canary) via
  `verify-render.sh`. Render assertions:
  - model-pull init container present when `modelStore.uri` is set, absent when
    empty;
  - `model.version` pod annotation reflects the configured version;
  - `model-compare-job.yaml` renders only when `modelCompare.enabled: true`;
  - inherited security-context / checksum assertions still pass;
  - renders are deterministic (rendering twice with identical inputs is
    byte-identical).

## Backward compatibility

- This is a **new folder**; nothing in `Helm-Chart/mychart` changes, so existing
  releases are unaffected.
- Within the new chart, all new values default safely: empty `modelStore.uri`
  omits the init container, `modelCompare.enabled: false` omits the Job. A chart
  with no model values renders the same shape as the hardened `mychart`.

## Verification

- `helm lint Model-Deployment/chart -f <each values file>` passes.
- `helm template` renders cleanly for dev, staging, production, canary.
- Init container appears/disappears with `modelStore.uri`; compare Job
  appears/disappears with `modelCompare.enabled`.
- Bumping `model.version` alone changes only the model annotation/init args
  (proves code/model independence); bumping `image.tag` alone changes only the
  image.
- `scripts/verify-render.sh` assertions pass.
