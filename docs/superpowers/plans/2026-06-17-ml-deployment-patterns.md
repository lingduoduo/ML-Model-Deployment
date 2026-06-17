# ML Deployment Patterns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-contained `Model-Deployment/` folder containing a Helm chart (`model-deployment`) plus CI/CD that implements both the deploy-code and deploy-models ML deployment patterns, catalog-segregated model stores, in-prod/staging validation gates with SLA load testing, online evaluation, and selectable real-time rollout strategies.

**Architecture:** Copy the hardened `Helm-Chart/mychart` into `Model-Deployment/chart`, rename its helper namespace to `model-deployment`, then layer new values + templates on top. Behavior is selected by `deploymentPattern` (deploy-code | deploy-models) and `rolloutStrategy` (gradual | ab-testing | shadow); a render-time validation helper rejects invalid combinations. All new features default off so the chart's baseline render matches `mychart`.

**Tech Stack:** Helm v4 (installed: v4.1.3), Kubernetes manifests (Deployment, Job, CronJob, Istio VirtualService / Gateway API HTTPRoute), GitHub Actions, bash.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-06-17-ml-deployment-patterns-design.md`.
- **All artifacts live under `Model-Deployment/`.** Do NOT edit `Helm-Chart/mychart`.
- **Helper namespace** in the new chart is `model-deployment.*` (not `mychart.*`).
- **New chart `Chart.yaml`:** `name: model-deployment`, `version: 0.1.0`, `appVersion: "1.0.0"`, `type: application`.
- **Backward-safe defaults:** `deploymentPattern: deploy-code`, `rolloutStrategy: gradual`, `trafficRouting.provider: none`, `modelStore.uri: ""`, `modelStore.catalog: ""`, `modelGate.enabled: false`, `onlineEval.enabled: false`, empty `modelGate.sla` thresholds. With these defaults the chart renders the same shape as `mychart`.
- **Pattern values (verbatim):** `deploy-code | deploy-models`. **Rollout values:** `gradual | ab-testing | shadow`. **Provider values:** `none | istio | gateway-api`. **Gate modes:** `validate | compare`. **Catalogs:** `dev | staging | prod`. **Environments:** `dev | staging | production`.
- **Catalog↔environment mapping:** `dev→dev`, `staging→staging`, `production→prod`.
- **Invalid `deploymentPattern`, `rolloutStrategy`, `modelGate.mode` (when enabled), or a catalog/environment mismatch MUST fail `helm template` with a clear message.** `shadow` + `provider: none` MUST fail rendering.
- **Test method:** every chart test is a `helm template` render piped to `grep`/comparison. Run from repo root. Commit after each task passes.

---

### Task 1: Scaffold the `model-deployment` chart from `mychart`

**Files:**
- Create: `Model-Deployment/chart/` (copy of `Helm-Chart/mychart`)
- Modify: `Model-Deployment/chart/Chart.yaml`
- Modify: `Model-Deployment/chart/templates/_helpers.tpl` (rename defines)
- Modify: all files under `Model-Deployment/chart/templates/` (rename `mychart.` → `model-deployment.` references)
- Modify: `Model-Deployment/chart/scripts/verify-render.sh` (CHART path comment only; logic unchanged this task)

**Interfaces:**
- Produces: helper templates `model-deployment.name`, `model-deployment.fullname`, `model-deployment.chart`, `model-deployment.labels`, `model-deployment.selectorLabels`, `model-deployment.serviceAccountName`.

- [ ] **Step 1: Copy the chart**

```bash
mkdir -p Model-Deployment
cp -R Helm-Chart/mychart Model-Deployment/chart
```

- [ ] **Step 2: Write the failing test (chart name renamed, renders)**

Run:
```bash
helm template r Model-Deployment/chart | grep -q 'app.kubernetes.io/name: model-deployment' && echo PASS || echo FAIL
```
Expected: `FAIL` (name is still `mychart` and helpers still `mychart.*`).

- [ ] **Step 3: Rename the chart and helper namespace**

Edit `Model-Deployment/chart/Chart.yaml`: set `name: model-deployment` and `version: 0.1.0` (leave `appVersion: "1.0.0"`, `type: application`, description as-is).

Rename every `mychart.` helper reference to `model-deployment.` across templates and the helper defines:
```bash
grep -rl 'mychart\.' Model-Deployment/chart/templates \
  | xargs sed -i '' 's/mychart\./model-deployment./g'
```
(On GNU sed use `sed -i` without `''`.)

- [ ] **Step 4: Run tests to verify rename + baseline parity**

Run:
```bash
helm lint Model-Deployment/chart
helm template r Model-Deployment/chart | grep -q 'app.kubernetes.io/name: model-deployment' && echo NAME_OK
# Baseline parity: rendered output equals mychart's except for the chart name/version strings.
diff <(helm template r Helm-Chart/mychart | sed 's/mychart/model-deployment/g') \
     <(helm template r Model-Deployment/chart) && echo PARITY_OK
```
Expected: lint passes, `NAME_OK`, `PARITY_OK` (the only differences are the renamed strings, which the sed normalizes; `helm.sh/chart: mychart-0.3.0` → `model-deployment-0.1.0` will differ — see note).

Note: the `helm.sh/chart` label embeds the version (`mychart-0.3.0` vs `model-deployment-0.1.0`), so the diff will show that one line. Confirm that is the ONLY difference; if so, parity is acceptable.

- [ ] **Step 5: Commit**

```bash
git add Model-Deployment/chart
git commit -m "feat(model-deployment): scaffold chart derived from mychart"
```

---

### Task 2: Pattern selector + validation helper

**Files:**
- Modify: `Model-Deployment/chart/values.yaml`
- Modify: `Model-Deployment/chart/templates/_helpers.tpl`
- Modify: `Model-Deployment/chart/templates/deployment.yaml:1`

**Interfaces:**
- Produces: value `deploymentPattern` (default `deploy-code`); helper `model-deployment.validate` (invoked at top of `deployment.yaml`). Later tasks EXTEND `model-deployment.validate`.

- [ ] **Step 1: Write the failing test**

Run:
```bash
helm template r Model-Deployment/chart --set deploymentPattern=bogus 2>&1 | grep -q 'deploymentPattern must be one of' && echo PASS || echo FAIL
```
Expected: `FAIL` (no validation yet; render succeeds).

- [ ] **Step 2: Add the value**

In `Model-Deployment/chart/values.yaml`, add as the first content line (above `replicaCount`):
```yaml
# Deployment pattern: deploy-code | deploy-models
deploymentPattern: deploy-code
```

- [ ] **Step 3: Add the validation helper**

Append to `Model-Deployment/chart/templates/_helpers.tpl`:
```
{{/*
Validate selectable values. Fails rendering with a clear message on bad input.
Extended by later tasks (rolloutStrategy, catalog/environment, modelGate.mode).
*/}}
{{- define "model-deployment.validate" -}}
{{- $allowedPatterns := list "deploy-code" "deploy-models" -}}
{{- if not (has .Values.deploymentPattern $allowedPatterns) -}}
{{- fail (printf "deploymentPattern must be one of [%s], got %q" (join ", " $allowedPatterns) (toString .Values.deploymentPattern)) -}}
{{- end -}}
{{- end -}}
```

- [ ] **Step 4: Invoke the helper so it always runs**

In `Model-Deployment/chart/templates/deployment.yaml`, insert as line 1 (before `apiVersion`):
```
{{- include "model-deployment.validate" . -}}
```

- [ ] **Step 5: Run tests to verify**

Run:
```bash
helm template r Model-Deployment/chart --set deploymentPattern=bogus 2>&1 | grep -q 'deploymentPattern must be one of' && echo REJECT_OK
helm template r Model-Deployment/chart --set deploymentPattern=deploy-models >/dev/null && echo VALID_OK
helm template r Model-Deployment/chart >/dev/null && echo DEFAULT_OK
```
Expected: `REJECT_OK`, `VALID_OK`, `DEFAULT_OK`.

- [ ] **Step 6: Commit**

```bash
git add Model-Deployment/chart/values.yaml Model-Deployment/chart/templates/_helpers.tpl Model-Deployment/chart/templates/deployment.yaml
git commit -m "feat(model-deployment): add deploymentPattern selector + validation helper"
```

---

### Task 3: Model loading (init container, modelStore, catalog) + provenance annotations

**Files:**
- Modify: `Model-Deployment/chart/values.yaml`
- Modify: `Model-Deployment/chart/templates/deployment.yaml`
- Modify: `Model-Deployment/chart/templates/_helpers.tpl` (extend `model-deployment.validate` with catalog/environment check)

**Interfaces:**
- Consumes: `model-deployment.validate` (Task 2).
- Produces: values `modelStore.{catalog,uri,mountPath,pullSecretName,pullCommand}`, `model.{version,pullPolicy}`, `environment`; init container `model-pull`; pod annotations `model.version`, `model.catalog`; volume `model-data` (emptyDir) when `modelStore.uri` set and persistence disabled.

- [ ] **Step 1: Write the failing tests**

Run:
```bash
helm template r Model-Deployment/chart --set modelStore.uri=s3://b/m --set model.version=v1 | grep -q 'name: model-pull' && echo PASS1 || echo FAIL1
helm template r Model-Deployment/chart --set modelStore.uri=s3://b/m --set model.version=v1 | grep -q 'model.version: "v1"' && echo PASS2 || echo FAIL2
helm template r Model-Deployment/chart | grep -q 'name: model-pull' && echo HASINIT || echo NOINIT
helm template r Model-Deployment/chart --set environment=production --set modelStore.catalog=dev 2>&1 | grep -q 'does not match environment' && echo PASS3 || echo FAIL3
```
Expected: `FAIL1`, `FAIL2`, `NOINIT`, `FAIL3`.

- [ ] **Step 2: Add values**

In `Model-Deployment/chart/values.yaml`: change the existing `model:` block and add `modelStore:` + `environment:`.

Replace the existing `model:` block:
```yaml
model:
  name: sample-model
  path: /models/model
  version: ""          # the model version to serve; bump to ship a new model
  pullPolicy: IfNotPresent
```
Add after the `model:` block:
```yaml
# Environment this release targets: dev | staging | production (set per env values file).
environment: ""

# Catalog-segregated model store (§4). When uri is set, an init container pulls
# <uri>/<model.version> into mountPath before the server starts.
modelStore:
  catalog: ""          # dev | staging | prod — must match `environment` (see validation)
  uri: ""              # backend-agnostic base, e.g. s3://ml-dev/model-server
  mountPath: /models   # where the model is placed for the server to read
  pullSecretName: ""   # optional credentials secret (mounted as envFrom on the init container)
  pullCommand: []      # override the pull command for your backend; default is a placeholder
```

- [ ] **Step 3: Extend the validation helper**

In `Model-Deployment/chart/templates/_helpers.tpl`, inside `model-deployment.validate`, add before the final `{{- end -}}`:
```
{{- if and .Values.modelStore.catalog .Values.environment -}}
{{- $catMap := dict "dev" "dev" "staging" "staging" "production" "prod" -}}
{{- $expected := index $catMap .Values.environment -}}
{{- if and $expected (ne .Values.modelStore.catalog $expected) -}}
{{- fail (printf "modelStore.catalog %q does not match environment %q (expected %q)" .Values.modelStore.catalog .Values.environment $expected) -}}
{{- end -}}
{{- end -}}
```

- [ ] **Step 4: Add provenance annotations**

In `Model-Deployment/chart/templates/deployment.yaml`, in `spec.template.metadata.annotations` (after the `checksum/secret` line, before the `{{- with .Values.podAnnotations }}` block), add:
```
        {{- if .Values.model.version }}
        model.version: {{ .Values.model.version | quote }}
        {{- end }}
        {{- if .Values.modelStore.catalog }}
        model.catalog: {{ .Values.modelStore.catalog | quote }}
        {{- end }}
```

- [ ] **Step 5: Add the init container**

In `Model-Deployment/chart/templates/deployment.yaml`, inside `spec.template.spec`, immediately before `      containers:`, add:
```
      {{- if .Values.modelStore.uri }}
      initContainers:
        - name: model-pull
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          {{- if .Values.modelStore.pullCommand }}
          command:
            {{- toYaml .Values.modelStore.pullCommand | nindent 12 }}
          {{- else }}
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -e
              echo "[model-pull] fetching ${MODEL_URI} -> ${MODEL_DEST}"
              if command -v model-pull >/dev/null 2>&1; then
                model-pull "${MODEL_URI}" "${MODEL_DEST}"
              else
                echo "[model-pull] override modelStore.pullCommand for your backend" >&2
              fi
          {{- end }}
          env:
            - name: MODEL_URI
              value: "{{ .Values.modelStore.uri }}/{{ .Values.model.version }}"
            - name: MODEL_DEST
              value: {{ .Values.modelStore.mountPath | quote }}
          {{- if .Values.modelStore.pullSecretName }}
          envFrom:
            - secretRef:
                name: {{ .Values.modelStore.pullSecretName }}
          {{- end }}
          volumeMounts:
            {{- if .Values.persistence.enabled }}
            - name: model-storage
              mountPath: {{ .Values.persistence.mountPath }}
            {{- else }}
            - name: model-data
              mountPath: {{ .Values.modelStore.mountPath }}
            {{- end }}
      {{- end }}
```

- [ ] **Step 6: Mount the model volume into the main container and declare it**

In `deployment.yaml`, change the main container's volumeMounts guard line from:
```
          {{- if or .Values.persistence.enabled .Values.writableTmp.enabled .Values.volumeMounts }}
```
to:
```
          {{- if or .Values.persistence.enabled .Values.writableTmp.enabled .Values.volumeMounts .Values.modelStore.uri }}
```
and inside that block, after the `persistence.enabled` mount, add an `else` branch for the emptyDir:
```
            {{- if .Values.persistence.enabled }}
            - name: model-storage
              mountPath: {{ .Values.persistence.mountPath }}
            {{- else if .Values.modelStore.uri }}
            - name: model-data
              mountPath: {{ .Values.modelStore.mountPath }}
            {{- end }}
```
(replace the existing single `{{- if .Values.persistence.enabled }} ... {{- end }}` mount block with the above).

Change the volumes guard line from:
```
      {{- if or .Values.persistence.enabled .Values.writableTmp.enabled .Values.volumes }}
```
to:
```
      {{- if or .Values.persistence.enabled .Values.writableTmp.enabled .Values.volumes .Values.modelStore.uri }}
```
and add the emptyDir volume after the `persistence.enabled` volume block:
```
        {{- if and .Values.modelStore.uri (not .Values.persistence.enabled) }}
        - name: model-data
          emptyDir: {}
        {{- end }}
```

- [ ] **Step 7: Run tests to verify**

Run:
```bash
helm template r Model-Deployment/chart --set modelStore.uri=s3://b/m --set model.version=v1 | grep -q 'name: model-pull' && echo INIT_OK
helm template r Model-Deployment/chart --set modelStore.uri=s3://b/m --set model.version=v1 | grep -q 'model.version: "v1"' && echo ANNO_OK
helm template r Model-Deployment/chart | grep -q 'name: model-pull' || echo NOINIT_DEFAULT_OK
helm template r Model-Deployment/chart --set environment=production --set modelStore.catalog=dev 2>&1 | grep -q 'does not match environment' && echo CATALOG_REJECT_OK
helm template r Model-Deployment/chart --set environment=production --set modelStore.catalog=prod >/dev/null && echo CATALOG_OK
helm lint Model-Deployment/chart
```
Expected: `INIT_OK`, `ANNO_OK`, `NOINIT_DEFAULT_OK`, `CATALOG_REJECT_OK`, `CATALOG_OK`, lint passes.

- [ ] **Step 8: Commit**

```bash
git add Model-Deployment/chart/values.yaml Model-Deployment/chart/templates/_helpers.tpl Model-Deployment/chart/templates/deployment.yaml
git commit -m "feat(model-deployment): add model-pull init container, modelStore catalog + provenance annotations"
```

---

### Task 4: Validation gate Job (validate|compare, readiness, SLA/load)

**Files:**
- Create: `Model-Deployment/chart/templates/model-gate-job.yaml`
- Modify: `Model-Deployment/chart/values.yaml`
- Modify: `Model-Deployment/chart/templates/_helpers.tpl` (extend `model-deployment.validate` with gate-mode check)

**Interfaces:**
- Consumes: `model-deployment.fullname/labels/selectorLabels/serviceAccountName`, `model-deployment.validate`.
- Produces: values block `modelGate.*`; Job named `<fullname>-gate-<mode>` rendered only when `modelGate.enabled`.

- [ ] **Step 1: Write the failing tests**

Run:
```bash
helm template r Model-Deployment/chart | grep -q 'kind: Job' && echo HASJOB || echo NOJOB
helm template r Model-Deployment/chart --set modelGate.enabled=true --set modelGate.mode=compare | grep -q 'model-deployment.io/gate: "compare"' && echo PASS || echo FAIL
helm template r Model-Deployment/chart --set modelGate.enabled=true --set modelGate.mode=bogus 2>&1 | grep -q 'modelGate.mode must be one of' && echo PASSMODE || echo FAILMODE
```
Expected: `NOJOB`, `FAIL`, `FAILMODE`.

- [ ] **Step 2: Add values**

In `Model-Deployment/chart/values.yaml`, add:
```yaml
# Model validation/comparison gate (§6). Enabled in the gating env per pattern:
# deploy-code => mode: compare in production; deploy-models => mode: validate in staging.
modelGate:
  enabled: false
  mode: ""             # validate | compare
  holdoutUri: ""       # dataset/metrics source for the check
  verdictSink: ""      # where pass/fail + metric deltas are written
  backoffLimit: 0
  command: []          # override to run real checks; default echoes the plan
  readinessChecks: true
  sla:
    medianLatencyMs: 0
    p95LatencyMs: 0
    p99LatencyMs: 0
    minQps: 0
    errorRateMax: 0
  load:
    peakQps: 0
    stress:
      enabled: false
      multiplier: 2
```

- [ ] **Step 3: Extend the validation helper**

In `_helpers.tpl`, inside `model-deployment.validate`, before the final `{{- end -}}`, add:
```
{{- if .Values.modelGate.enabled -}}
{{- $allowedModes := list "validate" "compare" -}}
{{- if not (has .Values.modelGate.mode $allowedModes) -}}
{{- fail (printf "modelGate.mode must be one of [%s] when modelGate.enabled, got %q" (join ", " $allowedModes) (toString .Values.modelGate.mode)) -}}
{{- end -}}
{{- end -}}
```

- [ ] **Step 4: Create the Job template**

Create `Model-Deployment/chart/templates/model-gate-job.yaml`:
```
{{- if .Values.modelGate.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "model-deployment.fullname" . }}-gate-{{ .Values.modelGate.mode }}
  labels:
    {{- include "model-deployment.labels" . | nindent 4 }}
    model-deployment.io/gate: {{ .Values.modelGate.mode | quote }}
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  backoffLimit: {{ .Values.modelGate.backoffLimit }}
  template:
    metadata:
      labels:
        {{- include "model-deployment.selectorLabels" . | nindent 8 }}
    spec:
      restartPolicy: Never
      serviceAccountName: {{ include "model-deployment.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: model-gate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          {{- if .Values.modelGate.command }}
          command:
            {{- toYaml .Values.modelGate.command | nindent 12 }}
          {{- else }}
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -e
              echo "[gate] mode=${GATE_MODE} pattern={{ .Values.deploymentPattern }}"
              {{- if .Values.modelGate.readinessChecks }}
              echo "[gate] readiness checks: config scripts, dependencies, input schema"
              {{- end }}
              echo "[gate] sla median=${SLA_MEDIAN_MS}ms p95=${SLA_P95_MS}ms p99=${SLA_P99_MS}ms minQps=${SLA_MIN_QPS} errMax=${SLA_ERR_MAX}"
              echo "[gate] load peakQps=${LOAD_PEAK_QPS} stress={{ .Values.modelGate.load.stress.enabled }}"
              echo "[gate] override modelGate.command to run real checks against ${HOLDOUT_URI}; verdict -> ${VERDICT_SINK}"
          {{- end }}
          env:
            - name: GATE_MODE
              value: {{ .Values.modelGate.mode | quote }}
            - name: MODEL_VERSION
              value: {{ .Values.model.version | quote }}
            - name: HOLDOUT_URI
              value: {{ .Values.modelGate.holdoutUri | quote }}
            - name: VERDICT_SINK
              value: {{ .Values.modelGate.verdictSink | quote }}
            - name: SLA_MEDIAN_MS
              value: {{ .Values.modelGate.sla.medianLatencyMs | quote }}
            - name: SLA_P95_MS
              value: {{ .Values.modelGate.sla.p95LatencyMs | quote }}
            - name: SLA_P99_MS
              value: {{ .Values.modelGate.sla.p99LatencyMs | quote }}
            - name: SLA_MIN_QPS
              value: {{ .Values.modelGate.sla.minQps | quote }}
            - name: SLA_ERR_MAX
              value: {{ .Values.modelGate.sla.errorRateMax | quote }}
            - name: LOAD_PEAK_QPS
              value: {{ .Values.modelGate.load.peakQps | quote }}
{{- end }}
```

- [ ] **Step 5: Run tests to verify**

Run:
```bash
helm template r Model-Deployment/chart | grep -q 'kind: Job' || echo NOJOB_DEFAULT_OK
helm template r Model-Deployment/chart --set modelGate.enabled=true --set modelGate.mode=compare | grep -q 'model-deployment.io/gate: "compare"' && echo JOB_OK
helm template r Model-Deployment/chart --set modelGate.enabled=true --set modelGate.mode=bogus 2>&1 | grep -q 'modelGate.mode must be one of' && echo MODE_REJECT_OK
helm lint Model-Deployment/chart
```
Expected: `NOJOB_DEFAULT_OK`, `JOB_OK`, `MODE_REJECT_OK`, lint passes.

- [ ] **Step 6: Commit**

```bash
git add Model-Deployment/chart/values.yaml Model-Deployment/chart/templates/_helpers.tpl Model-Deployment/chart/templates/model-gate-job.yaml
git commit -m "feat(model-deployment): add model gate Job with readiness + SLA/load checks"
```

---

### Task 5: Online evaluation CronJob

**Files:**
- Create: `Model-Deployment/chart/templates/model-online-eval-cronjob.yaml`
- Modify: `Model-Deployment/chart/values.yaml`

**Interfaces:**
- Consumes: `model-deployment.fullname/labels/selectorLabels/serviceAccountName`.
- Produces: values block `onlineEval.*`; CronJob `<fullname>-online-eval` rendered only when `onlineEval.enabled`.

- [ ] **Step 1: Write the failing tests**

Run:
```bash
helm template r Model-Deployment/chart | grep -q 'kind: CronJob' && echo HASCRON || echo NOCRON
helm template r Model-Deployment/chart --set onlineEval.enabled=true --set onlineEval.schedule='*/30 * * * *' | grep -q 'kind: CronJob' && echo PASS || echo FAIL
```
Expected: `NOCRON`, `FAIL`.

- [ ] **Step 2: Add values**

In `values.yaml`, add:
```yaml
# Online model evaluation (§6a). Opt-in recurring re-score of the live model.
onlineEval:
  enabled: false
  schedule: "0 * * * *"
  holdoutUri: ""
  driftAction: alert   # alert | trigger-refresh
```

- [ ] **Step 3: Create the CronJob template**

Create `Model-Deployment/chart/templates/model-online-eval-cronjob.yaml`:
```
{{- if .Values.onlineEval.enabled }}
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "model-deployment.fullname" . }}-online-eval
  labels:
    {{- include "model-deployment.labels" . | nindent 4 }}
spec:
  schedule: {{ .Values.onlineEval.schedule | quote }}
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        metadata:
          labels:
            {{- include "model-deployment.selectorLabels" . | nindent 12 }}
        spec:
          restartPolicy: Never
          serviceAccountName: {{ include "model-deployment.serviceAccountName" . }}
          securityContext:
            {{- toYaml .Values.podSecurityContext | nindent 12 }}
          containers:
            - name: online-eval
              image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
              imagePullPolicy: {{ .Values.image.pullPolicy }}
              securityContext:
                {{- toYaml .Values.securityContext | nindent 16 }}
              command: ["/bin/sh", "-c"]
              args:
                - |
                  set -e
                  echo "[online-eval] scoring live model {{ .Values.model.version }} on ${HOLDOUT_URI}"
                  echo "[online-eval] driftAction=${DRIFT_ACTION}"
              env:
                - name: HOLDOUT_URI
                  value: {{ .Values.onlineEval.holdoutUri | quote }}
                - name: DRIFT_ACTION
                  value: {{ .Values.onlineEval.driftAction | quote }}
{{- end }}
```

- [ ] **Step 4: Run tests to verify**

Run:
```bash
helm template r Model-Deployment/chart | grep -q 'kind: CronJob' || echo NOCRON_DEFAULT_OK
helm template r Model-Deployment/chart --set onlineEval.enabled=true | grep -q 'name: r-model-deployment-online-eval' && echo CRON_OK
helm lint Model-Deployment/chart
```
Expected: `NOCRON_DEFAULT_OK`, `CRON_OK`, lint passes.

- [ ] **Step 5: Commit**

```bash
git add Model-Deployment/chart/values.yaml Model-Deployment/chart/templates/model-online-eval-cronjob.yaml
git commit -m "feat(model-deployment): add online-eval CronJob"
```

---

### Task 6: Rollout strategies + mesh-optional traffic routing

**Files:**
- Create: `Model-Deployment/chart/templates/traffic-routing.yaml`
- Modify: `Model-Deployment/chart/values.yaml`
- Modify: `Model-Deployment/chart/templates/_helpers.tpl` (extend `model-deployment.validate` with rolloutStrategy check)

**Interfaces:**
- Consumes: `model-deployment.fullname/labels`, `service.port`.
- Produces: values `rolloutStrategy`, `trafficRouting.{provider,abSplit,gradualSteps}`; routing object rendered only when provider is `istio`/`gateway-api`. `shadow` + `none` fails rendering.

- [ ] **Step 1: Write the failing tests**

Run:
```bash
helm template r Model-Deployment/chart --set rolloutStrategy=bogus 2>&1 | grep -q 'rolloutStrategy must be one of' && echo P1 || echo F1
helm template r Model-Deployment/chart --set rolloutStrategy=shadow 2>&1 | grep -q 'shadow.*requires trafficRouting.provider' && echo P2 || echo F2
helm template r Model-Deployment/chart --set trafficRouting.provider=istio --set rolloutStrategy=ab-testing | grep -q 'kind: VirtualService' && echo P3 || echo F3
helm template r Model-Deployment/chart | grep -qE 'kind: (VirtualService|HTTPRoute)' && echo HASROUTE || echo NOROUTE
```
Expected: `F1`, `F2`, `F3`, `NOROUTE`.

- [ ] **Step 2: Add values**

In `values.yaml`, add:
```yaml
# Real-time rollout strategy (§6b): gradual | ab-testing | shadow
rolloutStrategy: gradual
trafficRouting:
  provider: none       # none | istio | gateway-api
  abSplit: 50          # ab-testing: % of traffic to the challenger (canary)
  gradualSteps:        # gradual: % steps advanced as the gate passes
    - 10
    - 25
    - 50
    - 100
```

- [ ] **Step 3: Extend the validation helper**

In `_helpers.tpl`, inside `model-deployment.validate`, before the final `{{- end -}}`, add:
```
{{- $allowedStrategies := list "gradual" "ab-testing" "shadow" -}}
{{- if not (has .Values.rolloutStrategy $allowedStrategies) -}}
{{- fail (printf "rolloutStrategy must be one of [%s], got %q" (join ", " $allowedStrategies) (toString .Values.rolloutStrategy)) -}}
{{- end -}}
{{- if and (eq .Values.rolloutStrategy "shadow") (eq .Values.trafficRouting.provider "none") -}}
{{- fail "rolloutStrategy 'shadow' requires trafficRouting.provider 'istio' or 'gateway-api' (traffic mirroring is impossible with provider 'none')" -}}
{{- end -}}
```

- [ ] **Step 4: Create the routing template**

Create `Model-Deployment/chart/templates/traffic-routing.yaml`:
```
{{- $challenger := printf "%s-canary" (include "model-deployment.fullname" .) -}}
{{- if eq .Values.trafficRouting.provider "istio" }}
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: {{ include "model-deployment.fullname" . }}
  labels:
    {{- include "model-deployment.labels" . | nindent 4 }}
spec:
  hosts:
    - {{ include "model-deployment.fullname" . }}
  http:
    {{- if eq .Values.rolloutStrategy "shadow" }}
    - route:
        - destination:
            host: {{ include "model-deployment.fullname" . }}
          weight: 100
      mirror:
        host: {{ $challenger }}
      mirrorPercentage:
        value: 100.0
    {{- else if eq .Values.rolloutStrategy "ab-testing" }}
    - route:
        - destination:
            host: {{ include "model-deployment.fullname" . }}
          weight: {{ sub 100 (int .Values.trafficRouting.abSplit) }}
        - destination:
            host: {{ $challenger }}
          weight: {{ int .Values.trafficRouting.abSplit }}
    {{- else }}
    - route:
        - destination:
            host: {{ include "model-deployment.fullname" . }}
          weight: {{ sub 100 (int (last .Values.trafficRouting.gradualSteps)) }}
        - destination:
            host: {{ $challenger }}
          weight: {{ int (last .Values.trafficRouting.gradualSteps) }}
    {{- end }}
{{- else if eq .Values.trafficRouting.provider "gateway-api" }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "model-deployment.fullname" . }}
  labels:
    {{- include "model-deployment.labels" . | nindent 4 }}
spec:
  rules:
    {{- if eq .Values.rolloutStrategy "shadow" }}
    - filters:
        - type: RequestMirror
          requestMirror:
            backendRef:
              name: {{ $challenger }}
              port: {{ .Values.service.port }}
      backendRefs:
        - name: {{ include "model-deployment.fullname" . }}
          port: {{ .Values.service.port }}
          weight: 100
    {{- else if eq .Values.rolloutStrategy "ab-testing" }}
    - backendRefs:
        - name: {{ include "model-deployment.fullname" . }}
          port: {{ .Values.service.port }}
          weight: {{ sub 100 (int .Values.trafficRouting.abSplit) }}
        - name: {{ $challenger }}
          port: {{ .Values.service.port }}
          weight: {{ int .Values.trafficRouting.abSplit }}
    {{- else }}
    - backendRefs:
        - name: {{ include "model-deployment.fullname" . }}
          port: {{ .Values.service.port }}
          weight: {{ sub 100 (int (last .Values.trafficRouting.gradualSteps)) }}
        - name: {{ $challenger }}
          port: {{ .Values.service.port }}
          weight: {{ int (last .Values.trafficRouting.gradualSteps) }}
    {{- end }}
{{- end }}
```

- [ ] **Step 5: Run tests to verify**

Run:
```bash
helm template r Model-Deployment/chart --set rolloutStrategy=bogus 2>&1 | grep -q 'rolloutStrategy must be one of' && echo STRAT_REJECT_OK
helm template r Model-Deployment/chart --set rolloutStrategy=shadow 2>&1 | grep -q 'shadow.*requires trafficRouting.provider' && echo SHADOW_GUARD_OK
helm template r Model-Deployment/chart --set trafficRouting.provider=istio --set rolloutStrategy=ab-testing | grep -q 'weight: 50' && echo AB_OK
helm template r Model-Deployment/chart --set trafficRouting.provider=istio --set rolloutStrategy=shadow | grep -q 'mirror:' && echo SHADOW_OK
helm template r Model-Deployment/chart --set trafficRouting.provider=gateway-api | grep -q 'kind: HTTPRoute' && echo GW_OK
helm template r Model-Deployment/chart | grep -qE 'kind: (VirtualService|HTTPRoute)' || echo NOROUTE_DEFAULT_OK
helm lint Model-Deployment/chart
```
Expected: `STRAT_REJECT_OK`, `SHADOW_GUARD_OK`, `AB_OK`, `SHADOW_OK`, `GW_OK`, `NOROUTE_DEFAULT_OK`, lint passes.

- [ ] **Step 6: Commit**

```bash
git add Model-Deployment/chart/values.yaml Model-Deployment/chart/templates/_helpers.tpl Model-Deployment/chart/templates/traffic-routing.yaml
git commit -m "feat(model-deployment): add rollout strategies + mesh-optional traffic routing"
```

---

### Task 7: Environment values files (dev/staging/production/canary)

**Files:**
- Create: `Model-Deployment/chart/values-dev.yaml`
- Modify: `Model-Deployment/chart/values-staging.yaml`
- Modify: `Model-Deployment/chart/values-production.yaml`
- Modify: `Model-Deployment/chart/values-production-canary.yaml`

**Interfaces:**
- Consumes: all values from Tasks 2–6.
- Produces: per-env catalog/store/SLA/onlineEval settings. `deploymentPattern`, `modelGate.enabled/mode`, and `rolloutStrategy` are set at deploy time by CD (Task 9), NOT hard-coded here.

- [ ] **Step 1: Write the failing tests**

Run:
```bash
test -f Model-Deployment/chart/values-dev.yaml && echo HASDEV || echo NODEV
helm template r Model-Deployment/chart -f Model-Deployment/chart/values-production.yaml | grep -q 'model.catalog: "prod"' && echo PASS || echo FAIL
```
Expected: `NODEV`, `FAIL`.

- [ ] **Step 2: Create `values-dev.yaml`**

```yaml
environment: dev
replicaCount: 1

# Override tag with an immutable image tag or digest in CI/CD.
image:
  repository: ghcr.io/example/model-server
  tag: latest

model:
  name: dev-model
  path: /models/model
  version: ""

# dev catalog: open read/write for developers (access enforced out-of-band).
modelStore:
  catalog: dev
  uri: s3://ml-dev/model-server

ingress:
  enabled: false
```

- [ ] **Step 3: Update `values-staging.yaml`**

Append to `Model-Deployment/chart/values-staging.yaml`:
```yaml
environment: staging

# staging catalog: limited write (admins + CI service principals); read for debugging.
modelStore:
  catalog: staging
  uri: s3://ml-staging/model-server

# Stakeholder SLAs exercised by the gate's load testing in staging (§6a).
modelGate:
  sla:
    medianLatencyMs: 200
    p95LatencyMs: 500
    p99LatencyMs: 800
    minQps: 50
    errorRateMax: 0.01
  load:
    peakQps: 100
    stress:
      enabled: true
      multiplier: 2
```

- [ ] **Step 4: Update `values-production.yaml`**

Append to `Model-Deployment/chart/values-production.yaml`:
```yaml
environment: production

# prod catalog: restricted write (only prod-deployed code / CD service principal).
modelStore:
  catalog: prod
  uri: s3://ml-prod/model-server

# Online evaluation keeps the most accurate model serving as fresh data arrives.
onlineEval:
  enabled: true
  schedule: "0 * * * *"
  holdoutUri: s3://ml-prod/holdout
  driftAction: alert

modelGate:
  sla:
    medianLatencyMs: 150
    p95LatencyMs: 400
    p99LatencyMs: 700
    minQps: 100
    errorRateMax: 0.005
  load:
    peakQps: 300
    stress:
      enabled: true
      multiplier: 3
```

- [ ] **Step 5: Update `values-production-canary.yaml`**

Append to `Model-Deployment/chart/values-production-canary.yaml`:
```yaml
environment: production

modelStore:
  catalog: prod
  uri: s3://ml-prod/model-server
```

- [ ] **Step 6: Run tests to verify**

Run:
```bash
for f in values-dev values-staging values-production values-production-canary; do
  helm lint Model-Deployment/chart -f Model-Deployment/chart/$f.yaml
  helm template r Model-Deployment/chart -f Model-Deployment/chart/$f.yaml >/dev/null && echo "$f RENDER_OK"
done
helm template r Model-Deployment/chart -f Model-Deployment/chart/values-production.yaml | grep -q 'model.catalog: "prod"' && echo PROD_CATALOG_OK
helm template r Model-Deployment/chart -f Model-Deployment/chart/values-production.yaml | grep -q 'kind: CronJob' && echo PROD_CRON_OK
# Catalog/env consistency holds for every env file.
helm template r Model-Deployment/chart -f Model-Deployment/chart/values-dev.yaml | grep -q 'model.catalog: "dev"' && echo DEV_CATALOG_OK
```
Expected: four `RENDER_OK`, `PROD_CATALOG_OK`, `PROD_CRON_OK`, `DEV_CATALOG_OK`, lint passes for all.

- [ ] **Step 7: Commit**

```bash
git add Model-Deployment/chart/values-dev.yaml Model-Deployment/chart/values-staging.yaml Model-Deployment/chart/values-production.yaml Model-Deployment/chart/values-production-canary.yaml
git commit -m "feat(model-deployment): add dev values + catalog/SLA/online-eval per env"
```

---

### Task 8: Extend `verify-render.sh` with the new invariants

**Files:**
- Modify: `Model-Deployment/chart/scripts/verify-render.sh`

**Interfaces:**
- Consumes: the whole chart.
- Produces: a single regression script asserting all spec invariants across dev/staging/production/canary for BOTH patterns.

- [ ] **Step 1: Write the failing test**

Run:
```bash
bash Model-Deployment/chart/scripts/verify-render.sh 2>&1 | tail -1
```
Expected: prints `All assertions passed.` BUT does not yet cover dev or the new invariants (it only checks the inherited four envs and security invariants). This task adds the missing coverage.

- [ ] **Step 2: Rewrite `verify-render.sh`**

Replace the file contents of `Model-Deployment/chart/scripts/verify-render.sh` with:
```bash
#!/usr/bin/env bash
# Lint + render the chart against every environment values file and assert the
# ML-deployment-pattern invariants hold. Usage: scripts/verify-render.sh
set -euo pipefail

command -v helm >/dev/null 2>&1 || { echo "helm not found on PATH" >&2; exit 1; }

CHART="$(cd "$(dirname "$0")/.." && pwd)"
REPO_OVERRIDE="${IMAGE_REPOSITORY:-ghcr.io/example/model-server}"
TAG_OVERRIDE="${IMAGE_TAG:-ci-test}"

ENVS=("values-dev" "values-staging" "values-production" "values-production-canary")

fail() { echo "ASSERTION FAILED: $1" >&2; exit 1; }

render() { helm template render "${CHART}" "$@"; }

for env in "${ENVS[@]}"; do
  [ -f "${CHART}/${env}.yaml" ] || fail "${env}: values file not found"
  base=(--set "image.repository=${REPO_OVERRIDE}" --set "image.tag=${TAG_OVERRIDE}" -f "${CHART}/${env}.yaml")

  for pattern in deploy-code deploy-models; do
    label="${env}/${pattern}"
    args=("${base[@]}" --set "deploymentPattern=${pattern}")

    echo "== lint ${label} =="
    helm lint "${CHART}" "${args[@]}"

    echo "== render ${label} =="
    out="$(render "${args[@]}")"

    # Inherited hardening invariants.
    grep -q 'runAsNonRoot: true'           <<<"$out" || fail "${label}: runAsNonRoot not true"
    grep -q 'readOnlyRootFilesystem: true' <<<"$out" || fail "${label}: rootfs not read-only"
    grep -q 'seccompProfile'               <<<"$out" || fail "${label}: missing seccompProfile"
    grep -q 'checksum/config'              <<<"$out" || fail "${label}: missing checksum annotation"
    grep -q 'ephemeral-storage'            <<<"$out" || fail "${label}: missing ephemeral-storage"
    if grep -q 'deployment.kubernetes.io/timestamp' <<<"$out"; then fail "${label}: timestamp annotation present"; fi

    # New: init container present (all env files set modelStore.uri) + catalog annotation.
    grep -q 'name: model-pull' <<<"$out" || fail "${label}: missing model-pull init container"
    grep -q 'model.catalog:'   <<<"$out" || fail "${label}: missing model.catalog annotation"

    # Render must be deterministic.
    out2="$(render "${args[@]}")"
    [ "$out" = "$out2" ] || fail "${label}: render not deterministic"
  done
done

echo "== negative cases =="
render --set deploymentPattern=bogus 2>&1 | grep -q 'deploymentPattern must be one of' || fail "bad pattern not rejected"
render --set rolloutStrategy=bogus 2>&1 | grep -q 'rolloutStrategy must be one of' || fail "bad strategy not rejected"
render --set rolloutStrategy=shadow 2>&1 | grep -q "shadow.*requires trafficRouting.provider" || fail "shadow+none not rejected"
render --set environment=production --set modelStore.catalog=dev 2>&1 | grep -q 'does not match environment' || fail "catalog/env mismatch not rejected"
render --set modelGate.enabled=true --set modelGate.mode=bogus 2>&1 | grep -q 'modelGate.mode must be one of' || fail "bad gate mode not rejected"

echo "== feature toggles =="
render --set modelGate.enabled=true --set modelGate.mode=compare | grep -q 'model-deployment.io/gate: "compare"' || fail "compare gate did not render"
render --set onlineEval.enabled=true | grep -q 'kind: CronJob' || fail "online-eval CronJob did not render"
render --set trafficRouting.provider=istio | grep -q 'kind: VirtualService' || fail "istio VirtualService did not render"
render --set trafficRouting.provider=gateway-api | grep -q 'kind: HTTPRoute' || fail "gateway-api HTTPRoute did not render"

echo "All assertions passed."
```

- [ ] **Step 3: Make executable and run**

Run:
```bash
chmod +x Model-Deployment/chart/scripts/verify-render.sh
bash Model-Deployment/chart/scripts/verify-render.sh
```
Expected: ends with `All assertions passed.`

- [ ] **Step 4: Commit**

```bash
git add Model-Deployment/chart/scripts/verify-render.sh
git commit -m "test(model-deployment): extend verify-render with pattern + feature invariants"
```

---

### Task 9: CI workflow

**Files:**
- Create: `Model-Deployment/cicd/ci.yml`

**Interfaces:**
- Consumes: `Model-Deployment/chart/scripts/verify-render.sh`.
- Produces: a GitHub Actions workflow that runs the verify script on PRs touching `Model-Deployment/`.

- [ ] **Step 1: Create the workflow**

Create `Model-Deployment/cicd/ci.yml`:
```yaml
name: Model-Deployment CI

on:
  pull_request:
    paths:
      - Model-Deployment/**
  push:
    branches: [master]
    paths:
      - Model-Deployment/**

jobs:
  helm-verify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Set up Helm
        uses: azure/setup-helm@v5
        with:
          version: v3.15.4

      - name: Lint + render + assert invariants (both patterns, all envs)
        run: bash Model-Deployment/chart/scripts/verify-render.sh
```

- [ ] **Step 2: Validate YAML syntax**

Run:
```bash
python3 -c "import yaml,sys; yaml.safe_load(open('Model-Deployment/cicd/ci.yml')); print('YAML_OK')"
```
Expected: `YAML_OK`.

- [ ] **Step 3: Commit**

```bash
git add Model-Deployment/cicd/ci.yml
git commit -m "ci(model-deployment): lint+render verification for both patterns"
```

---

### Task 10: CD pipelines (deploy-code + deploy-models) and deploy script

**Files:**
- Create: `Model-Deployment/cicd/cd-deploy-code.yml`
- Create: `Model-Deployment/cicd/cd-deploy-models.yml`
- Create: `Model-Deployment/deploy/deploy.sh`

**Interfaces:**
- Consumes: the chart + env values files.
- Produces: two manual-dispatch promotion workflows and a shared deploy script invoked by both.

- [ ] **Step 1: Create the deploy script**

Create `Model-Deployment/deploy/deploy.sh`:
```bash
#!/usr/bin/env bash
# Render + apply the model-deployment chart for one environment.
# Required env: DEPLOY_ENVIRONMENT (dev|staging|production), DEPLOYMENT_PATTERN,
# IMAGE_REPOSITORY, IMAGE_TAG, MODEL_VERSION. Optional: ROLLOUT_STRATEGY,
# GATE_ENABLED, GATE_MODE, RELEASE_NAME, KUBE_NAMESPACE.
set -euo pipefail

CHART="$(cd "$(dirname "$0")/../chart" && pwd)"
ENVIRONMENT="${DEPLOY_ENVIRONMENT:?set DEPLOY_ENVIRONMENT}"
PATTERN="${DEPLOYMENT_PATTERN:?set DEPLOYMENT_PATTERN}"
RELEASE_NAME="${RELEASE_NAME:-model-release}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-model-serving}"

case "$ENVIRONMENT" in
  dev)        VALUES="values-dev.yaml" ;;
  staging)    VALUES="values-staging.yaml" ;;
  production) VALUES="values-production.yaml" ;;
  *) echo "unknown DEPLOY_ENVIRONMENT '$ENVIRONMENT'" >&2; exit 1 ;;
esac

args=(
  upgrade --install "$RELEASE_NAME" "$CHART"
  --namespace "$KUBE_NAMESPACE" --create-namespace
  -f "$CHART/$VALUES"
  --set "deploymentPattern=${PATTERN}"
  --set "image.repository=${IMAGE_REPOSITORY:?set IMAGE_REPOSITORY}"
  --set "image.tag=${IMAGE_TAG:?set IMAGE_TAG}"
  --set "model.version=${MODEL_VERSION:?set MODEL_VERSION}"
)
[ -n "${ROLLOUT_STRATEGY:-}" ] && args+=(--set "rolloutStrategy=${ROLLOUT_STRATEGY}")
[ -n "${GATE_ENABLED:-}" ]     && args+=(--set "modelGate.enabled=${GATE_ENABLED}")
[ -n "${GATE_MODE:-}" ]        && args+=(--set "modelGate.mode=${GATE_MODE}")

echo "Deploying ${RELEASE_NAME} (${PATTERN}) to ${ENVIRONMENT}/${KUBE_NAMESPACE}"
helm "${args[@]}"
```

- [ ] **Step 2: Create `cd-deploy-code.yml`**

Create `Model-Deployment/cicd/cd-deploy-code.yml`:
```yaml
name: CD deploy-code

on:
  workflow_dispatch:
    inputs:
      image_repository:
        description: Container image repository
        required: true
        default: ghcr.io/example/model-server
        type: string
      image_tag:
        description: Immutable image tag/digest to promote
        required: true
        type: string
      model_version:
        description: Model version to serve (independent of code)
        required: true
        type: string
      rollout_strategy:
        description: Production rollout strategy
        required: true
        default: gradual
        type: choice
        options: [gradual, ab-testing, shadow]

env:
  CHART_PATH: Model-Deployment/chart
  RELEASE_NAME: model-release
  DEPLOYMENT_PATTERN: deploy-code

jobs:
  dev:
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: actions/checkout@v5
      - uses: azure/setup-helm@v5
        with: { version: v3.15.4 }
      - name: Deploy to dev
        env:
          DEPLOY_ENVIRONMENT: dev
          IMAGE_REPOSITORY: ${{ github.event.inputs.image_repository }}
          IMAGE_TAG: ${{ github.event.inputs.image_tag }}
          MODEL_VERSION: ${{ github.event.inputs.model_version }}
        run: bash Model-Deployment/deploy/deploy.sh
      - name: Smoke test
        run: echo "run dev smoke test here"

  staging:
    needs: dev
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v5
      - uses: azure/setup-helm@v5
        with: { version: v3.15.4 }
      - name: Deploy same image to staging (subset)
        env:
          DEPLOY_ENVIRONMENT: staging
          IMAGE_REPOSITORY: ${{ github.event.inputs.image_repository }}
          IMAGE_TAG: ${{ github.event.inputs.image_tag }}
          MODEL_VERSION: ${{ github.event.inputs.model_version }}
        run: bash Model-Deployment/deploy/deploy.sh
      - name: Integration test on data subset
        run: echo "run staging integration test here"

  production:
    needs: staging
    runs-on: ubuntu-latest
    environment: production   # require manual approval via GitHub environment protection
    steps:
      - uses: actions/checkout@v5
      - uses: azure/setup-helm@v5
        with: { version: v3.15.4 }
      - name: Deploy to production with in-prod compare gate
        env:
          DEPLOY_ENVIRONMENT: production
          IMAGE_REPOSITORY: ${{ github.event.inputs.image_repository }}
          IMAGE_TAG: ${{ github.event.inputs.image_tag }}
          MODEL_VERSION: ${{ github.event.inputs.model_version }}
          ROLLOUT_STRATEGY: ${{ github.event.inputs.rollout_strategy }}
          GATE_ENABLED: "true"
          GATE_MODE: compare
        run: bash Model-Deployment/deploy/deploy.sh
```

- [ ] **Step 3: Create `cd-deploy-models.yml`**

Create `Model-Deployment/cicd/cd-deploy-models.yml`:
```yaml
name: CD deploy-models

on:
  workflow_dispatch:
    inputs:
      image_repository:
        description: Serving image repository (promoted separately via deploy-code)
        required: true
        default: ghcr.io/example/model-server
        type: string
      image_tag:
        description: Current serving image tag (fixed while the model is promoted)
        required: true
        type: string
      model_version:
        description: Model artifact version to promote dev->staging->prod
        required: true
        type: string

env:
  CHART_PATH: Model-Deployment/chart
  RELEASE_NAME: model-release
  DEPLOYMENT_PATTERN: deploy-models

jobs:
  dev:
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: actions/checkout@v5
      - uses: azure/setup-helm@v5
        with: { version: v3.15.4 }
      - name: Stage model in dev
        env:
          DEPLOY_ENVIRONMENT: dev
          IMAGE_REPOSITORY: ${{ github.event.inputs.image_repository }}
          IMAGE_TAG: ${{ github.event.inputs.image_tag }}
          MODEL_VERSION: ${{ github.event.inputs.model_version }}
        run: bash Model-Deployment/deploy/deploy.sh

  staging:
    needs: dev
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v5
      - uses: azure/setup-helm@v5
        with: { version: v3.15.4 }
      - name: Promote model to staging + run validation gate
        env:
          DEPLOY_ENVIRONMENT: staging
          IMAGE_REPOSITORY: ${{ github.event.inputs.image_repository }}
          IMAGE_TAG: ${{ github.event.inputs.image_tag }}
          MODEL_VERSION: ${{ github.event.inputs.model_version }}
          GATE_ENABLED: "true"
          GATE_MODE: validate
        run: bash Model-Deployment/deploy/deploy.sh

  production:
    needs: staging
    runs-on: ubuntu-latest
    environment: production   # manual approval gate
    steps:
      - uses: actions/checkout@v5
      - uses: azure/setup-helm@v5
        with: { version: v3.15.4 }
      - name: Deploy validated model to production
        env:
          DEPLOY_ENVIRONMENT: production
          IMAGE_REPOSITORY: ${{ github.event.inputs.image_repository }}
          IMAGE_TAG: ${{ github.event.inputs.image_tag }}
          MODEL_VERSION: ${{ github.event.inputs.model_version }}
        run: bash Model-Deployment/deploy/deploy.sh
```

- [ ] **Step 4: Validate**

Run:
```bash
chmod +x Model-Deployment/deploy/deploy.sh
bash -n Model-Deployment/deploy/deploy.sh && echo SCRIPT_SYNTAX_OK
for f in cd-deploy-code cd-deploy-models; do
  python3 -c "import yaml; yaml.safe_load(open('Model-Deployment/cicd/$f.yml')); print('$f YAML_OK')"
done
```
Expected: `SCRIPT_SYNTAX_OK`, `cd-deploy-code YAML_OK`, `cd-deploy-models YAML_OK`.

- [ ] **Step 5: Commit**

```bash
git add Model-Deployment/cicd/cd-deploy-code.yml Model-Deployment/cicd/cd-deploy-models.yml Model-Deployment/deploy/deploy.sh
git commit -m "feat(model-deployment): add deploy-code + deploy-models CD pipelines"
```

---

### Task 11: README + NOTES

**Files:**
- Create: `Model-Deployment/README.md`
- Modify: `Model-Deployment/chart/templates/NOTES.txt`

**Interfaces:**
- Consumes: everything above.
- Produces: human documentation of both patterns, catalog segregation, and how to promote.

- [ ] **Step 1: Create `Model-Deployment/README.md`**

```markdown
# Model-Deployment

Self-contained Helm chart + CI/CD implementing two ML deployment patterns over
one chart, selected by `deploymentPattern`.

## Patterns

- **deploy-code** (default): the container image is promoted dev→staging→prod
  unchanged; the model is pulled at runtime by `model.version`, bumped
  independently of code. Validation + comparison vs the running prod model run
  **in production** (canary + `modelGate.mode=compare`).
- **deploy-models**: the *model artifact* (`model.version`) is promoted
  dev→staging→prod; it is **validated in staging** (`modelGate.mode=validate`)
  before prod. Inference/monitoring code rides the deploy-code path separately.
  Use for one-off / expensive-training models.

## Catalog segregation

Each environment reads from its own model-store catalog: `s3://ml-dev/...`,
`s3://ml-staging/...`, `s3://ml-prod/...`. Access posture (open dev,
limited-write staging, restricted-write prod) is enforced out-of-band via the
`modelStore.pullSecretName` service principal; the chart asserts
`modelStore.catalog` matches `environment`.

## Real-time serving

- Pre-deployment testing: `modelGate.readinessChecks` + `modelGate.sla`/`load`
  (latency p95/p99, QPS, peak, stress) run as part of the gate.
- Online evaluation: opt-in prod `onlineEval` CronJob re-scores the live model.
- Rollout strategies: `rolloutStrategy` = gradual | ab-testing | shadow, with
  mesh-optional `trafficRouting.provider` (none | istio | gateway-api).

## Verify

```bash
bash chart/scripts/verify-render.sh
```

## Promote

Use `cicd/cd-deploy-code.yml` or `cicd/cd-deploy-models.yml` (manual dispatch);
both call `deploy/deploy.sh`.
```

- [ ] **Step 2: Append to `NOTES.txt`**

Append to `Model-Deployment/chart/templates/NOTES.txt`:
```
{{ if .Values.modelStore.uri }}
Model: pulling version "{{ .Values.model.version }}" from {{ .Values.modelStore.uri }} (catalog: {{ .Values.modelStore.catalog }}).
{{- end }}
Pattern: {{ .Values.deploymentPattern }} | rollout: {{ .Values.rolloutStrategy }}{{ if .Values.modelGate.enabled }} | gate: {{ .Values.modelGate.mode }}{{ end }}.
```

- [ ] **Step 3: Verify render still clean**

Run:
```bash
helm template r Model-Deployment/chart --set modelStore.uri=s3://b/m --set model.version=v1 --set modelStore.catalog=dev --set environment=dev | grep -q 'model-deployment' && echo OK
bash Model-Deployment/chart/scripts/verify-render.sh | tail -1
```
Expected: `OK`, then `All assertions passed.`

- [ ] **Step 4: Commit**

```bash
git add Model-Deployment/README.md Model-Deployment/chart/templates/NOTES.txt
git commit -m "docs(model-deployment): add README + NOTES for both patterns"
```

---

## Final verification

- [ ] Run the full suite:
```bash
bash Model-Deployment/chart/scripts/verify-render.sh
```
Expected: `All assertions passed.`
- [ ] Confirm `Helm-Chart/mychart` is unchanged: `git diff --stat master -- Helm-Chart/mychart` shows nothing from this branch's commits.
