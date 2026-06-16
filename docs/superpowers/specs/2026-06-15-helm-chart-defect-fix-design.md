# Helm Chart (`mychart`) Optimization — Design Spec

**Date:** 2026-06-15
**Scope:** `Helm-Chart/mychart` only
**Status:** Approved design, pending implementation plan

## Goal

Optimize the `mychart` Helm chart across four dimensions the user selected:
correctness/defect fixes, security hardening, HA/reliability, and
resource/cost tuning. Changes must be backward-compatible (no required new
values; existing releases upgrade cleanly) and verifiable via `helm lint` /
`helm template`.

## Out of scope

- Raw manifests under `Kubernetes/` (local-model, cronjob, voting-app, notes).
- Restructuring into a base library chart + thin app chart (YAGNI for one chart).
- Enforcing image digest/version pinning — documented as guidance only, not enforced.

## Findings (current defects)

| # | Location | Issue |
|---|----------|-------|
| 1 | `values.yaml:142-153` | `volumes`, `volumeMounts`, `nodeSelector`, `tolerations`, `affinity` each declared twice (YAML last-wins; dead/confusing config). |
| 2 | `templates/deployment.yaml:19-22` | `deployment.kubernetes.io/timestamp: now` injected on every render → rolling restart on **every** `helm upgrade` even with no change, and does **not** roll pods when a ConfigMap/Secret content changes. |
| 3 | all `values*.yaml` | `image.tag: "latest"` — mutable tag defeats rollback/reproducibility. |
| 4 | `values.yaml:26-33` | `runAsNonRoot: false`, no `capabilities.drop: [ALL]`, no `seccompProfile`; even production leaves `readOnlyRootFilesystem: false`. |
| 5 | pod spec | No pod anti-affinity / `topologySpreadConstraints` — multiple replicas can co-locate on one node. |
| 6 | `values.yaml` resources | No `ephemeral-storage` request/limit; no documented GPU (`nvidia.com/gpu`) resourcing path for ML serving. |

## Design

### 1. Defect fixes (correctness)

- **De-duplicate `values.yaml`**: collapse the doubled `volumes` / `volumeMounts`
  / `nodeSelector` / `tolerations` / `affinity` keys into a single declaration
  each, in a logical order.
- **Replace timestamp churn**: remove the `now`-based annotation from
  `templates/deployment.yaml`. Add checksum annotations so pods roll only when
  config content actually changes:
  ```yaml
  checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
  ```
  Keep the existing `{{- with .Values.podAnnotations }}` block; the checksum
  annotations are always emitted, merged with any user podAnnotations.
- **Image tag guidance**: keep `latest` as the bare chart default, but add a
  comment in `values.yaml` and env values files instructing operators to pin an
  immutable tag or digest per environment. No behavior change (CI already injects
  `image.tag=${github.sha}`).

### 2. Security hardening (secure-by-default in base `values.yaml`)

- `podSecurityContext`: `runAsNonRoot: true`, keep `runAsUser: 1000` /
  `fsGroup: 1000`, add `seccompProfile.type: RuntimeDefault`.
- `securityContext`: add `capabilities.drop: [ALL]`, set
  `readOnlyRootFilesystem: true`, keep `allowPrivilegeEscalation: false`.
- Add a `writableTmp.enabled` flag (default `true`) that mounts an `emptyDir` at
  `/tmp`, wired into the existing `volumes`/`volumeMounts` blocks in
  `deployment.yaml`. This satisfies `readOnlyRootFilesystem: true` for processes
  needing scratch space.
- Production/staging values inherit the secure base; remove now-redundant
  security overrides (e.g. the `runAsNonRoot: true` block in
  `values-production.yaml` becomes unnecessary).

### 3. HA / reliability

- Add a `topologySpreadConstraints` value rendered into the pod spec. Default:
  spread across `topologyKey: kubernetes.io/hostname`, `maxSkew: 1`,
  `whenUnsatisfiable: ScheduleAnyway`, selecting on `mychart.selectorLabels`.
  Empty list disables it. Rendered via `{{- with .Values.topologySpreadConstraints }}`.
- Config-driven rollouts handled correctly by the checksum annotations (§1).
- HPA and PDB are already correct and enabled in `values-production.yaml`; no change.

### 4. Resource / cost

- Add `ephemeral-storage` to `requests` and `limits` in base `values.yaml`
  resources (e.g. request `1Gi`, limit `2Gi`); env values may override.
- Add a commented GPU example to `values.yaml` (`nvidia.com/gpu` under
  resources, plus a `nodeSelector`/`tolerations` snippet) and a note in
  `values-model-example.yaml`. Documentation only — no default behavior change.

### 5. Chart hygiene & verification

- Bump `Chart.yaml` `version` `0.2.0` → `0.3.0` (templates changed; appVersion
  unchanged).
- Extend `.github/workflows-helm-chart/ci.yml`: run `helm lint` + `helm template`
  against **all** env values files (staging, production, production-canary), not
  just staging. Add post-render assertions on the staging/production render:
  - security context fields present (`runAsNonRoot: true`, `capabilities`/`drop`,
    `seccompProfile`, `readOnlyRootFilesystem: true`);
  - `checksum/config` annotation present;
  - no `deployment.kubernetes.io/timestamp` annotation remains.

## Backward compatibility

- No new **required** values. All new values have safe defaults.
- Existing releases: first upgrade after this change will roll pods once (because
  the security context and `/tmp` mount change the pod template) — expected and
  one-time. Subsequent no-op upgrades will **not** churn (the defect being fixed).
- `readOnlyRootFilesystem: true` is the one behavioral risk: a model server that
  writes outside `/tmp` would fail. Mitigation: the `writableTmp` mount covers the
  common case; operators with other writable paths add `volumeMounts`. Document
  this in the chart notes.

## Verification

- `helm lint Helm-Chart/mychart -f <each values file>` passes.
- `helm template` renders cleanly for base, staging, production, canary.
- Assertions in §5 pass against the rendered output.
- Spot-check: rendering twice with identical inputs produces identical output
  (proves the timestamp churn is gone).
