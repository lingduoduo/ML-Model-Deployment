# Helm Chart (`mychart`) Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize the `mychart` Helm chart for correctness, security, HA, and resource tuning without breaking backward compatibility.

**Architecture:** In-place edits to the existing chart. "Tests" are `helm template` / `helm lint` renders with `grep` assertions (no unit-test framework; `helm` v4 and standard shell only, `yq` not available). Each task makes a focused change verified by a render assertion, then commits.

**Tech Stack:** Helm v3/v4, Go templates, GitHub Actions, bash.

---

## Conventions for every task

- Run all `helm` commands from the repo root.
- Base render command used throughout (rendering with default `values.yaml`):
  ```bash
  helm template t Helm-Chart/mychart
  ```
- Per-environment render:
  ```bash
  helm template t Helm-Chart/mychart -f Helm-Chart/mychart/values-<env>.yaml
  ```
- An assertion "fails" if the `grep` exit status is not what the step says.

---

## File Structure

- Modify: `Helm-Chart/mychart/values.yaml` (de-dup, security, resources, topology, docs)
- Modify: `Helm-Chart/mychart/templates/deployment.yaml` (annotations, volumes, topology)
- Modify: `Helm-Chart/mychart/values-production.yaml` (drop redundant security block, ephemeral-storage)
- Modify: `Helm-Chart/mychart/Chart.yaml` (version bump)
- Modify: `Helm-Chart/mychart/values-staging.yaml`, `values-production-canary.yaml`, `values-model-example.yaml` (image-tag comment)
- Create: `Helm-Chart/mychart/scripts/verify-render.sh` (lint + render + assertions)
- Modify: `.github/workflows-helm-chart/ci.yml` (call verify script across all env values)

---

## Task 1: De-duplicate `values.yaml` keys

**Files:**
- Modify: `Helm-Chart/mychart/values.yaml:142-153`

- [ ] **Step 1: Verify the duplicate exists (failing assertion)**

Run:
```bash
grep -c '^volumes:' Helm-Chart/mychart/values.yaml
```
Expected now: `2` (the defect). Target after fix: `1`.

- [ ] **Step 2: Replace the duplicated tail block**

Replace the entire block at the end of `values.yaml` (currently):
```yaml
nodeSelector: {}
affinity: {}
tolerations: []
volumeMounts: []
volumes: []

volumes: []
volumeMounts: []

nodeSelector: {}
tolerations: []
affinity: {}
```
with this single block:
```yaml
nodeSelector: {}
tolerations: []
affinity: {}
volumes: []
volumeMounts: []
```

- [ ] **Step 3: Verify each key now appears once**

Run:
```bash
for k in volumes volumeMounts nodeSelector tolerations affinity; do
  printf '%s: ' "$k"; grep -c "^$k:" Helm-Chart/mychart/values.yaml
done
```
Expected: every count is `1`.

- [ ] **Step 4: Verify the chart still renders**

Run:
```bash
helm lint Helm-Chart/mychart && helm template t Helm-Chart/mychart >/dev/null && echo OK
```
Expected: ends with `OK`.

- [ ] **Step 5: Commit**

```bash
git add Helm-Chart/mychart/values.yaml
git commit -m "fix(helm): remove duplicate keys in values.yaml"
```

---

## Task 2: Replace timestamp churn with config checksums

**Files:**
- Modify: `Helm-Chart/mychart/templates/deployment.yaml:16-23`

- [ ] **Step 1: Verify the timestamp churn (failing assertion)**

Render twice and confirm output differs (the defect):
```bash
helm template t Helm-Chart/mychart > /tmp/r1.yaml
helm template t Helm-Chart/mychart > /tmp/r2.yaml
diff /tmp/r1.yaml /tmp/r2.yaml && echo IDENTICAL || echo DIFFERS
```
Expected now: `DIFFERS` (timestamp changes each render). Target after fix: `IDENTICAL`.

- [ ] **Step 2: Replace the annotations block**

In `templates/deployment.yaml`, replace this block:
```yaml
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
        deployment.kubernetes.io/timestamp: {{ now | date "2006-01-02T15:04:05Z07:00" | quote }}
      {{- else }}
      annotations:
        deployment.kubernetes.io/timestamp: {{ now | date "2006-01-02T15:04:05Z07:00" | quote }}
      {{- end }}
```
with:
```yaml
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
        checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
```

- [ ] **Step 3: Verify renders are now stable and timestamp is gone**

Run:
```bash
helm template t Helm-Chart/mychart > /tmp/r1.yaml
helm template t Helm-Chart/mychart > /tmp/r2.yaml
diff /tmp/r1.yaml /tmp/r2.yaml && echo IDENTICAL
grep -q 'deployment.kubernetes.io/timestamp' /tmp/r1.yaml && echo "BAD: timestamp present" || echo "OK: no timestamp"
grep -q 'checksum/config' /tmp/r1.yaml && echo "OK: checksum present"
```
Expected: `IDENTICAL`, `OK: no timestamp`, `OK: checksum present`.

- [ ] **Step 4: Verify the checksum rolls pods when config changes**

Run (enabling a configmap should change the checksum):
```bash
A=$(helm template t Helm-Chart/mychart | grep 'checksum/config')
B=$(helm template t Helm-Chart/mychart --set configMap.enabled=true --set configMap.data.FOO=bar | grep 'checksum/config')
[ "$A" != "$B" ] && echo "OK: checksum changed" || echo "BAD: checksum unchanged"
```
Expected: `OK: checksum changed`.

- [ ] **Step 5: Commit**

```bash
git add Helm-Chart/mychart/templates/deployment.yaml
git commit -m "fix(helm): roll pods on config checksum instead of timestamp"
```

---

## Task 3: Secure-by-default security context + writable /tmp

**Files:**
- Modify: `Helm-Chart/mychart/values.yaml:26-33` (security contexts) and add `writableTmp`
- Modify: `Helm-Chart/mychart/templates/deployment.yaml:95-118` (volumes/volumeMounts)
- Modify: `Helm-Chart/mychart/values-production.yaml` (remove redundant security block)

- [ ] **Step 1: Verify weak defaults (failing assertion)**

Run:
```bash
helm template t Helm-Chart/mychart | grep -q 'runAsNonRoot: true' && echo "OK" || echo "BAD: runAsNonRoot not true"
```
Expected now: `BAD: runAsNonRoot not true`. Target after fix: `OK`.

- [ ] **Step 2: Harden the security contexts in `values.yaml`**

Replace:
```yaml
podSecurityContext:
  runAsNonRoot: false
  runAsUser: 1000
  fsGroup: 1000

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false
```
with:
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

- [ ] **Step 3: Add `writableTmp` value**

In `values.yaml`, immediately after the `securityContext` block added in Step 2, add:
```yaml
# Writable scratch space mounted at /tmp.
# Required because readOnlyRootFilesystem is true by default.
writableTmp:
  enabled: true
  sizeLimit: 1Gi
```

- [ ] **Step 4: Wire `/tmp` mount into `deployment.yaml`**

Replace the `volumeMounts` block:
```yaml
          {{- if or .Values.persistence.enabled .Values.volumeMounts }}
          volumeMounts:
            {{- if .Values.persistence.enabled }}
            - name: model-storage
              mountPath: {{ .Values.persistence.mountPath }}
            {{- end }}
            {{- with .Values.volumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- end }}
```
with:
```yaml
          {{- if or .Values.persistence.enabled .Values.writableTmp.enabled .Values.volumeMounts }}
          volumeMounts:
            {{- if .Values.persistence.enabled }}
            - name: model-storage
              mountPath: {{ .Values.persistence.mountPath }}
            {{- end }}
            {{- if .Values.writableTmp.enabled }}
            - name: tmp
              mountPath: /tmp
            {{- end }}
            {{- with .Values.volumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- end }}
```

- [ ] **Step 5: Wire `/tmp` volume into `deployment.yaml`**

Replace the `volumes` block:
```yaml
      {{- if or .Values.persistence.enabled .Values.volumes }}
      volumes:
        {{- if .Values.persistence.enabled }}
        - name: model-storage
          persistentVolumeClaim:
            claimName: {{ .Values.persistence.existingClaim | default (printf "%s-model-storage" (include "mychart.fullname" .)) }}
        {{- end }}
        {{- with .Values.volumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- else }}
      volumes:
        []
      {{- end }}
```
with:
```yaml
      {{- if or .Values.persistence.enabled .Values.writableTmp.enabled .Values.volumes }}
      volumes:
        {{- if .Values.persistence.enabled }}
        - name: model-storage
          persistentVolumeClaim:
            claimName: {{ .Values.persistence.existingClaim | default (printf "%s-model-storage" (include "mychart.fullname" .)) }}
        {{- end }}
        {{- if .Values.writableTmp.enabled }}
        - name: tmp
          emptyDir:
            sizeLimit: {{ .Values.writableTmp.sizeLimit }}
        {{- end }}
        {{- with .Values.volumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- end }}
```

- [ ] **Step 6: Remove the now-redundant security block from `values-production.yaml`**

Delete this block (base values now provide stronger defaults):
```yaml
# Security context for production
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false
  capabilities:
    drop:
      - ALL
```

- [ ] **Step 7: Verify hardened render (base and production)**

Run:
```bash
for f in "" "-f Helm-Chart/mychart/values-production.yaml"; do
  out=$(helm template t Helm-Chart/mychart $f)
  echo "$out" | grep -q 'runAsNonRoot: true'        && \
  echo "$out" | grep -q 'readOnlyRootFilesystem: true' && \
  echo "$out" | grep -q 'seccompProfile' && \
  echo "$out" | grep -q -- '- ALL' && \
  echo "$out" | grep -q 'mountPath: /tmp' && echo "OK ${f:-base}" || echo "BAD ${f:-base}"
done
```
Expected: `OK base` and `OK -f .../values-production.yaml`.

- [ ] **Step 8: Commit**

```bash
git add Helm-Chart/mychart/values.yaml Helm-Chart/mychart/templates/deployment.yaml Helm-Chart/mychart/values-production.yaml
git commit -m "feat(helm): secure-by-default security context with writable /tmp"
```

---

## Task 4: Topology spread constraints for HA

**Files:**
- Modify: `Helm-Chart/mychart/values.yaml` (add `topologySpreadConstraints`)
- Modify: `Helm-Chart/mychart/templates/deployment.yaml` (render after `affinity`/`tolerations`)

- [ ] **Step 1: Verify no spread today (failing assertion)**

Run:
```bash
helm template t Helm-Chart/mychart | grep -q 'topologySpreadConstraints' && echo OK || echo "BAD: none"
```
Expected now: `BAD: none`. Target after fix: `OK`.

- [ ] **Step 2: Add the default value**

In `values.yaml`, replace the `affinity: {}` line (in the single block created in Task 1) so the tail block reads:
```yaml
nodeSelector: {}
tolerations: []
affinity: {}
# Spread replicas across nodes for availability.
# The labelSelector is injected automatically from the chart's selector labels;
# do NOT add labelSelector here. Set to [] to disable.
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
volumes: []
volumeMounts: []
```

- [ ] **Step 3: Render it in `deployment.yaml`**

In `templates/deployment.yaml`, after the `tolerations` block (the last block in the pod spec):
```yaml
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```
add:
```yaml
      {{- with .Values.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{- range . }}
        - {{ toYaml . | nindent 10 | trim }}
          labelSelector:
            matchLabels:
              {{- include "mychart.selectorLabels" $ | nindent 14 }}
        {{- end }}
      {{- end }}
```

- [ ] **Step 4: Verify the rendered constraint includes the selector**

Run:
```bash
out=$(helm template t Helm-Chart/mychart)
echo "$out" | grep -q 'topologySpreadConstraints' && \
echo "$out" | grep -q 'topologyKey: kubernetes.io/hostname' && \
echo "$out" | grep -q 'app.kubernetes.io/instance: t' && echo OK || echo BAD
```
Expected: `OK` (selector labels were injected under the constraint).

- [ ] **Step 5: Verify disabling works**

Run:
```bash
helm template t Helm-Chart/mychart --set 'topologySpreadConstraints=[]' | grep -q 'topologySpreadConstraints' && echo BAD || echo "OK: disabled"
```
Expected: `OK: disabled`.

- [ ] **Step 6: Commit**

```bash
git add Helm-Chart/mychart/values.yaml Helm-Chart/mychart/templates/deployment.yaml
git commit -m "feat(helm): default topology spread constraints for HA"
```

---

## Task 5: Ephemeral storage + GPU resourcing docs

**Files:**
- Modify: `Helm-Chart/mychart/values.yaml:93-99` (resources)
- Modify: `Helm-Chart/mychart/values-production.yaml` (resources)

- [ ] **Step 1: Verify no ephemeral-storage today (failing assertion)**

Run:
```bash
helm template t Helm-Chart/mychart | grep -q 'ephemeral-storage' && echo OK || echo "BAD: none"
```
Expected now: `BAD: none`. Target after fix: `OK`.

- [ ] **Step 2: Update base `resources` in `values.yaml`**

Replace:
```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: "1"
    memory: 1Gi
```
with:
```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
    ephemeral-storage: 1Gi
  limits:
    cpu: "1"
    memory: 1Gi
    ephemeral-storage: 2Gi
  # GPU model serving (uncomment and pair with GPU nodes):
  #   limits:
  #     nvidia.com/gpu: 1
  # Then schedule onto GPU nodes via the top-level keys:
  # nodeSelector:
  #   accelerator: nvidia
  # tolerations:
  #   - key: nvidia.com/gpu
  #     operator: Exists
  #     effect: NoSchedule
```

- [ ] **Step 3: Add ephemeral-storage to `values-production.yaml`**

Replace:
```yaml
resources:
  requests:
    cpu: "1"
    memory: 1Gi
  limits:
    cpu: "2"
    memory: 2Gi
```
with:
```yaml
resources:
  requests:
    cpu: "1"
    memory: 1Gi
    ephemeral-storage: 2Gi
  limits:
    cpu: "2"
    memory: 2Gi
    ephemeral-storage: 4Gi
```

- [ ] **Step 4: Verify render**

Run:
```bash
helm template t Helm-Chart/mychart | grep -q 'ephemeral-storage: 1Gi' && \
helm template t Helm-Chart/mychart -f Helm-Chart/mychart/values-production.yaml | grep -q 'ephemeral-storage: 2Gi' && echo OK || echo BAD
```
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add Helm-Chart/mychart/values.yaml Helm-Chart/mychart/values-production.yaml
git commit -m "feat(helm): add ephemeral-storage limits and GPU resourcing docs"
```

---

## Task 6: Image-tag immutability guidance (docs only)

**Files:**
- Modify: `Helm-Chart/mychart/values.yaml:3-6`
- Modify: `Helm-Chart/mychart/values-staging.yaml`, `values-production.yaml`, `values-production-canary.yaml`, `values-model-example.yaml`

- [ ] **Step 1: Add a guidance comment in `values.yaml`**

Replace:
```yaml
image:
  repository: your-docker-registry/model-server
  pullPolicy: IfNotPresent
  tag: "latest"
```
with:
```yaml
image:
  repository: your-docker-registry/model-server
  pullPolicy: IfNotPresent
  # Pin an immutable tag or digest per environment for safe rollbacks.
  # "latest" is a non-production default only.
  tag: "latest"
```

- [ ] **Step 2: Add the same one-line note above each env `image:` block**

In each of `values-staging.yaml`, `values-production.yaml`, `values-production-canary.yaml`, `values-model-example.yaml`, add this comment line directly above the `image:` key:
```yaml
# Override tag with an immutable image tag or digest in CI/CD.
```

- [ ] **Step 3: Verify charts still lint/render**

Run:
```bash
for f in values values-staging values-production values-production-canary; do
  helm lint Helm-Chart/mychart -f Helm-Chart/mychart/$f.yaml >/dev/null && echo "OK $f" || echo "BAD $f"
done
```
Expected: `OK` for each.

- [ ] **Step 4: Commit**

```bash
git add Helm-Chart/mychart/values.yaml Helm-Chart/mychart/values-staging.yaml Helm-Chart/mychart/values-production.yaml Helm-Chart/mychart/values-production-canary.yaml Helm-Chart/mychart/values-model-example.yaml
git commit -m "docs(helm): advise immutable image tags per environment"
```

---

## Task 7: Chart version bump, verify script, and CI

**Files:**
- Modify: `Helm-Chart/mychart/Chart.yaml:18`
- Create: `Helm-Chart/mychart/scripts/verify-render.sh`
- Modify: `.github/workflows-helm-chart/ci.yml`

- [ ] **Step 1: Bump chart version**

In `Chart.yaml`, change:
```yaml
version: 0.2.0
```
to:
```yaml
version: 0.3.0
```

- [ ] **Step 2: Create the verification script**

Create `Helm-Chart/mychart/scripts/verify-render.sh`:
```bash
#!/usr/bin/env bash
# Lint + render the chart against every environment values file and assert
# the optimization invariants hold. Usage: scripts/verify-render.sh
set -euo pipefail

CHART="$(cd "$(dirname "$0")/.." && pwd)"
REPO_OVERRIDE="${IMAGE_REPOSITORY:-ghcr.io/example/model-server}"
TAG_OVERRIDE="${IMAGE_TAG:-ci-test}"

ENVS=("" "values-staging" "values-production" "values-production-canary")

fail() { echo "ASSERTION FAILED: $1" >&2; exit 1; }

for env in "${ENVS[@]}"; do
  args=(--set "image.repository=${REPO_OVERRIDE}" --set "image.tag=${TAG_OVERRIDE}")
  [ -n "$env" ] && args+=(-f "${CHART}/${env}.yaml")
  label="${env:-base}"

  echo "== lint ${label} =="
  helm lint "${CHART}" "${args[@]}"

  echo "== render ${label} =="
  out="$(helm template render "${CHART}" "${args[@]}")"

  # Invariants that must hold for EVERY environment.
  grep -q 'runAsNonRoot: true'         <<<"$out" || fail "${label}: runAsNonRoot not true"
  grep -q 'readOnlyRootFilesystem: true' <<<"$out" || fail "${label}: rootfs not read-only"
  grep -q 'seccompProfile'             <<<"$out" || fail "${label}: missing seccompProfile"
  grep -q 'checksum/config'            <<<"$out" || fail "${label}: missing checksum annotation"
  grep -q 'ephemeral-storage'          <<<"$out" || fail "${label}: missing ephemeral-storage"
  grep -q 'deployment.kubernetes.io/timestamp' <<<"$out" && fail "${label}: timestamp annotation still present"

  # Render must be deterministic (no churn).
  out2="$(helm template render "${CHART}" "${args[@]}")"
  [ "$out" = "$out2" ] || fail "${label}: render not deterministic"
done

echo "All assertions passed."
```
Then make it executable:
```bash
chmod +x Helm-Chart/mychart/scripts/verify-render.sh
```

- [ ] **Step 3: Run the verify script locally**

Run:
```bash
Helm-Chart/mychart/scripts/verify-render.sh
```
Expected: ends with `All assertions passed.`

- [ ] **Step 4: Wire the script into CI**

In `.github/workflows-helm-chart/ci.yml`, replace the `Validate Helm chart` step (the whole `run: |` block) with a call to the script across all environments:
```yaml
      - name: Validate Helm chart
        env:
          IMAGE_REPOSITORY: ${{ vars.IMAGE_REPOSITORY || 'ghcr.io/example/model-server' }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          chmod +x "${CHART_PATH}/scripts/verify-render.sh"
          "${CHART_PATH}/scripts/verify-render.sh"
```

- [ ] **Step 5: Verify the workflow YAML is well-formed**

Run:
```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows-helm-chart/ci.yml')); print('YAML OK')"
```
Expected: `YAML OK`.

- [ ] **Step 6: Commit**

```bash
git add Helm-Chart/mychart/Chart.yaml Helm-Chart/mychart/scripts/verify-render.sh .github/workflows-helm-chart/ci.yml
git commit -m "chore(helm): bump to 0.3.0 and add render verification in CI"
```

---

## Final verification

- [ ] Run the full check:
```bash
Helm-Chart/mychart/scripts/verify-render.sh && echo "ALL GREEN"
```
Expected: `All assertions passed.` then `ALL GREEN`.

- [ ] Confirm clean tree:
```bash
git status --short
```
Expected: empty.

---

## Spec coverage map

| Spec section | Task |
|---|---|
| §1 de-dup values | Task 1 |
| §1 checksum rollout (remove `now`) | Task 2 |
| §1 image-tag guidance | Task 6 |
| §2 secure-by-default context + writableTmp | Task 3 |
| §3 topologySpreadConstraints | Task 4 |
| §4 ephemeral-storage + GPU docs | Task 5 |
| §5 chart version bump + CI verification | Task 7 |
