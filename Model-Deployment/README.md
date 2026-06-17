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
