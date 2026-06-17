#!/usr/bin/env bash
# Launch the model-deployment chart on a local minikube cluster and test it
# end to end: render checks, install with runnable images, verify the serving
# pod + provenance annotations, run `helm test`, and exercise a scheduled
# CronJob. Idempotent; safe to re-run.
#
# Usage (works from any directory — paths resolve relative to this script):
#   Model-Deployment/test.sh            full flow (cluster + install + tests)
#   Model-Deployment/test.sh --render   offline render/lint checks only (no cluster)
#   Model-Deployment/test.sh --cleanup  uninstall release + delete the cluster
#
# Env overrides: NS (model-demo), RELEASE (demo), MODEL_VERSION (2026-06-01).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHART="$SCRIPT_DIR/chart"
NS="${NS:-model-demo}"
RELEASE="${RELEASE:-demo}"
MODEL_VERSION="${MODEL_VERSION:-2026-06-01}"

log()  { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 1; }; }

render_checks() {
  need helm
  log "Render: scheduled CronJobs from values-dev.yaml"
  helm template "$RELEASE" "$CHART" -f "$CHART/values-dev.yaml" | grep -E 'kind: CronJob|schedule:'
  log "verify-render.sh (both patterns x all envs)"
  bash "$CHART/scripts/verify-render.sh"
}

cleanup() {
  log "Cleanup"
  helm uninstall "$RELEASE" -n "$NS" 2>/dev/null || true
  command -v minikube >/dev/null 2>&1 && minikube delete || true
  command -v colima  >/dev/null 2>&1 && colima stop || true
}

case "${1:-}" in
  --render)  render_checks; exit 0 ;;
  --cleanup) cleanup; exit 0 ;;
  "" )       ;;
  * )        echo "unknown option: $1 (use --render or --cleanup)" >&2; exit 1 ;;
esac

need helm; need kubectl; need minikube

# 1. Offline render checks first — fail fast before touching a cluster.
render_checks

# 2. Bring up a local cluster (Colima provides the docker runtime on macOS).
log "Starting local cluster"
if command -v colima >/dev/null 2>&1; then colima status >/dev/null 2>&1 || colima start; fi
minikube status >/dev/null 2>&1 || minikube start --driver=docker

# 3. Overlay: a runnable image + a fast (every-minute) scheduled job, so the
#    serving pod goes Ready and a CronJob is observable. The real values-dev.yaml
#    jobs point at a training image and run on hour boundaries.
OVERLAY="$(mktemp -t cron-test.XXXXXX).yaml"
trap 'rm -f "$OVERLAY"' EXIT
cat > "$OVERLAY" <<'YAML'
environment: dev
modelStore:
  catalog: dev
  uri: ""                 # no model-pull init container — keeps the demo simple
image:
  repository: busybox
  tag: "1.36"
container:
  command: ["/bin/sh","-c"]
  args:
    - mkdir -p /tmp/www && printf ok > /tmp/www/health && printf ok > /tmp/www/ready && httpd -f -p 8000 -h /tmp/www
scheduledJobs:
  - name: demo-trainer
    schedule: "* * * * *"
    image: busybox:1.36
    command: ["/bin/sh","-c"]
    args: ["echo \"[trainer] $(date) training run\"; sleep 3; echo done"]
YAML

# 4. Install / upgrade.
log "helm upgrade --install"
helm upgrade --install "$RELEASE" "$CHART" \
  -n "$NS" --create-namespace \
  -f "$CHART/values-dev.yaml" -f "$OVERLAY" \
  --set model.version="$MODEL_VERSION"
kubectl rollout status deploy/"$RELEASE"-model-deployment -n "$NS" --timeout=180s

# 5. Verify the serving deployment + provenance annotations.
log "Serving deployment"
kubectl get pods,svc -n "$NS"
POD=$(kubectl get pod -n "$NS" \
  -l app.kubernetes.io/instance="$RELEASE",app.kubernetes.io/name=model-deployment \
  -o jsonpath='{.items[0].metadata.name}')
echo "model.version / model.catalog: $(kubectl get pod -n "$NS" "$POD" \
  -o jsonpath='{.metadata.annotations.model\.version}{"  "}{.metadata.annotations.model\.catalog}')"

# 6. Connectivity test (templates/tests/test-connection.yaml).
log "helm test"
helm test "$RELEASE" -n "$NS"

# 7. Exercise a scheduled CronJob without waiting for the schedule.
log "Scheduled CronJob"
kubectl get cronjob -n "$NS"
kubectl delete job adhoc -n "$NS" 2>/dev/null || true
kubectl create job --from=cronjob/"$RELEASE"-model-deployment-demo-trainer adhoc -n "$NS"
kubectl wait --for=condition=complete job/adhoc -n "$NS" --timeout=120s
kubectl logs -n "$NS" job/adhoc

log "All checks passed. Tear down with: $0 --cleanup"
