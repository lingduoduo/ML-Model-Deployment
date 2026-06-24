# Spec: Consolidate Helm Charts into One & Align Scheduled Jobs to a Real Repo

## Objective

Unify the repo's two overlapping Helm charts into a single canonical chart and
realign the example scheduled jobs to a real codebase (the one genuine defect:
fictional `/opt/optimus2` job paths that match no repo).

**Why:** The repo currently maintains two charts that duplicate ~10 templates:

- `Model-Deployment/chart` — the feature-rich descendant (model init container,
  `scheduledJobs`, `modelGate`, `onlineEval`, `trafficRouting`, value validation).
- `Helm-Chart/mychart` — the hardened base it was "derived from without modifying."

Keeping both means every hardening fix must be applied twice. The `scheduledJobs`
examples also reference a fictional `/opt/optimus2/...` layout that matches no
real repo, so they can't be run or trusted as a reference.

**Correction to earlier exploration:** two "bugs" initially reported are NOT bugs
and must be left untouched:
- Readiness probe `path: /health` is **intentional** — `values.yaml:170` documents
  `recsys-serve exposes /health but not /ready; reuse /health for readiness`.
  Changing it to `/ready` would break readiness against the real serving app.
- Container/service **port is already a consistent `8000`** across every
  Model-Deployment values file. The 8000-vs-8080 difference existed only against
  mychart, which is being deleted. No in-chart change needed.

**Users:** Engineers deploying ML model services from this repo via Helm, and
maintainers who currently pay a double-maintenance tax on the two charts.

**Success looks like:** One chart (`Model-Deployment/chart`) is canonical;
`Helm-Chart/mychart` is removed (its deploy tooling repointed, not orphaned);
the example CronJob runs a real `adp-recommender-system` job; and no
`/opt/optimus2` references remain. `verify-render.sh` passes for both deployment
patterns across all env files.

## Decisions (confirmed with user)

1. **Merge into one chart.** `Model-Deployment/chart` becomes the single canonical
   chart. `Helm-Chart/mychart` (the chart) is removed. This intentionally
   supersedes the CLAUDE.md note that Model-Deployment is "derived from mychart
   without modifying it" — that note will be updated.
2. **Align args to `adp-recommender-system`** (the `Recsys-Modeling-Pipeline`
   repo). Image built from that project: WORKDIR `/app`, package
   `recsys_framework`, container port `8000`, invoked via the registry
   (`python -m recsys_framework.training_jobs <job>` / `recsys-train <job>`).
3. **Single realistic example.** Replace the four fictional `/opt/optimus2` dev
   CronJobs with one (at most two) clean, runnable example job(s) against
   `adp-recommender-system`, rather than mapping all four placeholders.

## Scope

### In scope
- Remove `Helm-Chart/mychart` chart; make `Model-Deployment/chart` canonical.
- Repoint `Helm-Chart/deploy/*.sh` + `Helm-Chart/mychart/scripts/` consumers at
  the canonical chart, OR relocate the deploy tooling — see Open Questions.
- Replace `values-dev.yaml` `scheduledJobs` with a real `adp-recommender-system`
  example (single job).
- Update `CLAUDE.md`, root `README.md`, and `Helm-Chart/*.md` docs to describe
  the single-chart reality.
- Optional genuine bug-hunt pass over the canonical chart (the two reported bugs
  were false; if a real defect surfaces, fix it — otherwise "fix bugs" reduces to
  the args realignment).

### Out of scope
- Building/publishing the `adp-recommender-system` image (we reference it by name).
- Implementing real backends for the documented placeholder commands
  (`model-pull`, `model-gate`, `online-eval`) — those stay as intentional,
  documented placeholders.
- Any change to `LLM-Inference-vLLM`, `Kubernetes/`, `Docker/`, `Xinference/`,
  `OpenClaw/`.
- Adding scheduled jobs to staging/production (dev-only, as today).

## Tech Stack
- Helm 3 (chart `apiVersion: v2`), Kubernetes manifests (`batch/v1` CronJob,
  `apps/v1` Deployment).
- Bash verification/deploy scripts.
- Reference workload image: `adp-recommender-system` (Python 3, `recsys_framework`).

## Commands
```bash
# Primary regression gate — lint + render every env file for BOTH patterns:
bash Model-Deployment/chart/scripts/verify-render.sh        # => All assertions passed.

# Render a single env (dev, where the new example job lives):
helm template demo Model-Deployment/chart -f Model-Deployment/chart/values-dev.yaml

# Confirm the realigned CronJob renders with the right command/args/port:
helm template demo Model-Deployment/chart -f Model-Deployment/chart/values-dev.yaml \
  | grep -A30 'kind: CronJob'

# Dry-run install:
helm install demo Model-Deployment/chart -f Model-Deployment/chart/values-dev.yaml --dry-run=client

# Offline full check (render + lint, no cluster):
Model-Deployment/test.sh --render

# After mychart removal, confirm deploy tooling still resolves a chart:
./Helm-Chart/deploy/validate-deployment.sh
```

## Project Structure
```
Model-Deployment/chart/              → CANONICAL chart (unchanged location)
  templates/                         → 18 templates (deployment, scheduled-jobs, gate, eval, routing, ...)
  values.yaml                        → defaults UNCHANGED (port 8000, probe /health both already correct)
  values-dev.yaml                    → dev: scheduledJobs realigned to adp-recommender-system
  values-staging/production*.yaml    → unchanged (probe/port already correct)
  scripts/verify-render.sh           → regression gate (extend if assertions added)

Helm-Chart/
  mychart/                           → REMOVED (chart templates + values + scripts)
  deploy/*.sh                        → repointed at Model-Deployment/chart (see Open Questions)

CLAUDE.md                            → updated: single canonical chart
SPEC.md                             → this file (committed)
```

## Code Style

Scheduled-job entries are plain values-file data consumed by
`templates/scheduled-jobs.yaml` (`range $job := .Values.scheduledJobs`). The
realigned example must use the real invocation contract — registry module, `/app`
PYTHONPATH, no `/opt/optimus2`, no `/opt/anaconda`:

```yaml
# values-dev.yaml — single realistic example against adp-recommender-system.
# Image is built from Recsys-Modeling-Pipeline/adp-recommender-system
# (WORKDIR /app, package recsys_framework, registry CLI). Pick the best model
# from the experiment store every 8 hours — the closest real analogue of the
# old "model-accuracy-check" job.
scheduledJobs:
  - name: select-best-model
    schedule: "0 */8 * * *"
    image: ghcr.io/example/adp-recommender-system:dev
    command: ["python", "-m"]
    args: ["recsys_framework.serving.select_best_model"]
    env:
      - name: PYTHONPATH
        value: /app
```

Conventions:
- No absolute fictional paths (`/opt/optimus2`, `/opt/anaconda`). Use the image's
  real `/app` WORKDIR and the installed `recsys_framework` package.
- Module invocation via `python -m <module>` (or `recsys-train <job>`), not a
  bare script path.
- Container/service port stays `8000` (already consistent — do not change).
- Readiness AND liveness probe path stay `/health` (intentional; the serving app
  exposes only `/health`). Do NOT "fix" readiness to `/ready`.
- Guard every optional feature behind its enabling value (preserve backward-safe
  default rendering — see CLAUDE.md "Backward-safe defaults").

## Testing Strategy
- **Primary gate:** `Model-Deployment/chart/scripts/verify-render.sh` — helm
  template + grep assertions across both patterns × all envs, including negative
  cases. Must end with `All assertions passed.`
- **Add assertions** for: the realigned CronJob renders the `recsys_framework`
  module + `/app` PYTHONPATH and the full render contains no `/opt/optimus2` and
  no `/opt/anaconda`. (Do NOT assert `/ready` or a port change — those are not
  part of this work.)
- **Render check:** `Model-Deployment/test.sh --render` (offline lint + render).
- **No unit-test framework exists** — render assertions are the regression gate.
- **Manual:** `helm template ... | grep -A30 CronJob` to eyeball the example job.

## Boundaries
- **Always:** run `verify-render.sh` (both patterns, all envs) before considering
  any task done; preserve backward-safe default rendering; keep commit → feature
  branch → PR workflow with the `Co-Authored-By` trailer; keep the canonical
  chart's behavior for `deployment.yaml`'s validator (one accumulator define).
- **Ask first:** removing/relocating `Helm-Chart/deploy/` tooling vs. repointing
  it; deleting the `Helm-Chart/` docs (`OPTIMIZATION.md`, `QUICK_REFERENCE.md`,
  etc.) that describe mychart; changing default port `8000` to anything else;
  bumping chart `version`.
- **Never:** hand-edit `CHANGELOG.md` (auto-generated); commit secrets; delete
  `verify-render.sh` assertions to make them pass; introduce a second validator
  define; modify the unrelated modules listed in Out of Scope.

## Success Criteria
1. `Helm-Chart/mychart/` chart directory no longer exists; no template/values
   duplication remains between two charts.
2. `Helm-Chart/deploy/*.sh` and any `mychart/scripts` references resolve to
   `Model-Deployment/chart` (or relocated tooling) — `validate-deployment.sh`
   runs without "chart not found".
3. `grep -r "/opt/optimus2" Model-Deployment/` returns nothing; `grep -r
   "/opt/anaconda" Model-Deployment/` returns nothing.
4. `helm template demo Model-Deployment/chart -f .../values-dev.yaml` renders a
   CronJob whose args reference `recsys_framework` and whose `PYTHONPATH` is
   `/app`.
5. Probe paths (`/health`) and port (`8000`) in the canonical chart are
   unchanged from before this work.
6. `verify-render.sh` ends with `All assertions passed.` for both patterns × all
   envs, including the newly added assertions.
7. `CLAUDE.md`, root `README.md`, and `Helm-Chart/*.md` describe one canonical
   chart and no longer claim mychart must be left unmodified.

## Resolved Decisions (formerly open questions)
1. **Deploy tooling:** repoint `Helm-Chart/deploy/*.sh` at `Model-Deployment/chart`
   **in place** (smallest diff). Affected: `run-local-deploy.sh`,
   `validate-deployment.sh`, `deploy_with_helm.sh`.
2. **mychart docs:** **update** `Helm-Chart/{README,OPTIMIZATION,QUICK_REFERENCE,
   DEPLOYMENT_SUMMARY}.md` + root `README.md` to point at the canonical chart;
   do not delete.
3. **Example jobs:** ship **one** (`select-best-model`).
4. **Chart version:** **keep** `Model-Deployment/chart` at `0.1.0` (no bump).

## Open Questions
- **Historical superpowers docs.** `docs/superpowers/plans/*` and `specs/*`
  (dated 2026-06-15/06-17) reference `mychart` as a record of past work — one plan
  even asserts "Confirm `Helm-Chart/mychart` is unchanged." These are historical
  artifacts, not live instructions. Proposal: **leave them as-is** (don't rewrite
  history); only live docs (CLAUDE.md, READMEs, deploy scripts) get updated.
  Flag if you'd rather annotate them.

## Implementation Plan (approved)

Branch: `refactor/consolidate-helm-charts` (off `master`).

- **Task 1 — Realign `values-dev.yaml` scheduledJobs.** Replace the four
  `/opt/optimus2` CronJobs with one runnable `select-best-model` job
  (`python -m recsys_framework.serving.select_best_model`, `PYTHONPATH=/app`,
  image `ghcr.io/example/adp-recommender-system:dev`, schedule `0 */8 * * *`).
  Rewrite the section comment. Verify: render shows module + `/app`, no optimus2.
- **Task 2 — Add assertions to `scripts/verify-render.sh`.** Dev render contains
  `recsys_framework.serving.select_best_model`; all-env renders contain no
  `/opt/optimus2` and no `/opt/anaconda`.
- **Task 3 — Remove `Helm-Chart/mychart`; repoint deploy tooling.** Delete the
  chart dir. Repoint `CHART_PATH` default → `Model-Deployment/chart` in
  `deploy_with_helm.sh:11`, `validate-deployment.sh:7`, `run-local-deploy.sh:8`;
  fix label selector `name=mychart` → `name=model-deployment` in
  `deploy_with_helm.sh:82`.
- **Task 4 — Update live docs.** `CLAUDE.md` (one canonical chart; drop the
  "derived without modifying mychart" claim + `## Helm-Chart/mychart` block),
  root `README.md:13`, `Helm-Chart/{README,OPTIMIZATION,QUICK_REFERENCE,
  DEPLOYMENT_SUMMARY}.md`. Leave `docs/superpowers/*` untouched.
- **Task 5 — Full gate.** `bash Model-Deployment/chart/scripts/verify-render.sh`
  → `All assertions passed.`
