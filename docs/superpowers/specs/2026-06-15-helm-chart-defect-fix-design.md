# Helm Chart Defect-Fix Pass — Design

**Date:** 2026-06-15
**Scope:** Correctness-only cleanup of `Helm-Chart/mychart`. No resource retuning, no
documentation consolidation. The chart is already feature-complete (PDB, HPA, probes,
canary, per-env security overlays); this pass fixes concrete defects found in the
templates and values.

## Context

`helm lint` and `helm template` pass today, so none of these defects surface as hard
errors — they are silent. That is precisely why they are worth fixing.

## Fixes

### 1. Remove duplicate keys in `mychart/values.yaml`

Lines 142–153 declare `nodeSelector`, `affinity`, `tolerations` twice and
`volumes` / `volumeMounts` twice. The YAML parser silently keeps the last
occurrence. Collapse to a single clean block.

- **Risk:** none. Both copies are identical empty defaults (`{}` / `[]`); the
  last-wins value is unchanged.

### 2. Fix the deploy-timestamp annotation in `mychart/templates/deployment.yaml`

Current template (lines 16–23) injects:

```yaml
deployment.kubernetes.io/timestamp: {{ now | date "..." | quote }}
```

Two real problems:

1. **Reserved prefix.** `deployment.kubernetes.io/` belongs to the Deployment
   controller. Custom annotations must not use it.
2. **Non-deterministic render.** `now` changes on every render, so `helm template` /
   `helm diff` produce different output each time. This causes permanent drift in
   GitOps/ArgoCD and forces a pod rollout on every `helm upgrade` even when nothing
   else changed.

**Fix:**

- Rename the key to a non-reserved namespace: `mychart.io/deploy-timestamp`.
- Gate it behind a new value `deployTimestamp.enabled` (default `false`) so the
  default render is deterministic and rollouts only occur on real changes. Operators
  who want the previous force-rollout behavior can opt in.

**Risk:** behavior change (acknowledged and approved). Default behavior becomes
deterministic; the timestamp annotation no longer appears unless opted in.

### 3. Add `capabilities.drop: [ALL]` to base `securityContext`

`mychart/values.yaml` base `securityContext` (lines 31–33) lacks
`capabilities.drop`, which the production overlay already sets. Add it to the base.

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false
  capabilities:
    drop:
      - ALL
```

`runAsNonRoot: false` is left unchanged — flipping it depends on the container image
and is out of scope for a low-risk pass.

- **Risk:** minimal. Dropping all Linux capabilities is safe for a typical model
  server (no raw sockets / privileged syscalls).

## Verification

For each of the four values files (default, `values-staging.yaml`,
`values-production.yaml`, `values-production-canary.yaml`):

1. `helm lint` passes.
2. `helm template` renders successfully.
3. Diff rendered output before/after and confirm the only changes are:
   - no spurious key duplication differences,
   - the timestamp annotation removed by default (item 2),
   - `capabilities.drop: [ALL]` present on the container securityContext (item 3).

## Out of scope

- Resource request/limit and HPA retuning.
- Consolidating the four optimization markdown docs.
- Flipping `runAsNonRoot` in base or non-production overlays.
- Adding `checksum/config` rollout annotations (potential future enhancement).
