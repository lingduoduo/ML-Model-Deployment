#!/usr/bin/env bash
# Lint + render the chart against every environment values file and assert the
# ML-deployment-pattern invariants hold. Usage: scripts/verify-render.sh
set -euo pipefail

command -v helm >/dev/null 2>&1 || { echo "helm not found on PATH" >&2; exit 1; }

CHART="$(cd "$(dirname "$0")/.." && pwd)"
REPO_OVERRIDE="${IMAGE_REPOSITORY:-ghcr.io/example/model-server}"
TAG_OVERRIDE="${IMAGE_TAG:-ci-test}"

# Baseline for negative cases and feature toggles: use a known-good dev environment
GOOD=(--set "image.repository=${REPO_OVERRIDE}" --set "image.tag=${TAG_OVERRIDE}" -f "${CHART}/values-dev.yaml")

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

    # Scheduled jobs must target real adp-recommender-system modules, never the
    # retired /opt/optimus2 + /opt/anaconda placeholders.
    if grep -q '/opt/optimus2' <<<"$out"; then fail "${label}: stale /opt/optimus2 path"; fi
    if grep -q '/opt/anaconda' <<<"$out"; then fail "${label}: stale /opt/anaconda path"; fi
    if [ "$env" = "values-dev" ]; then
      grep -q 'recsys_framework.serving.select_best_model' <<<"$out" \
        || fail "${label}: dev scheduledJobs missing select_best_model module"
    fi

    # Render must be deterministic.
    out2="$(render "${args[@]}")"
    [ "$out" = "$out2" ] || fail "${label}: render not deterministic"
  done
done

echo "== negative cases =="
(set +o pipefail; render "${GOOD[@]}" --set deploymentPattern=bogus 2>&1 | grep -q 'deploymentPattern must be one of') || fail "bad pattern not rejected"
(set +o pipefail; render "${GOOD[@]}" --set rolloutStrategy=bogus 2>&1 | grep -q 'rolloutStrategy must be one of') || fail "bad strategy not rejected"
(set +o pipefail; render "${GOOD[@]}" --set rolloutStrategy=shadow 2>&1 | grep -q "shadow.*requires trafficRouting.provider") || fail "shadow+none not rejected"
(set +o pipefail; render "${GOOD[@]}" --set environment=production --set modelStore.catalog=dev 2>&1 | grep -q 'does not match environment') || fail "catalog/env mismatch not rejected"
(set +o pipefail; render "${GOOD[@]}" --set modelGate.enabled=true --set modelGate.mode=bogus 2>&1 | grep -q 'modelGate.mode must be one of') || fail "bad gate mode not rejected"

echo "== feature toggles =="
(set +o pipefail; render "${GOOD[@]}" --set modelGate.enabled=true --set modelGate.mode=compare | grep -q 'model-deployment.io/gate: "compare"') || fail "compare gate did not render"
(set +o pipefail; render "${GOOD[@]}" --set onlineEval.enabled=true | grep -q 'kind: CronJob') || fail "online-eval CronJob did not render"
(set +o pipefail; render "${GOOD[@]}" --set trafficRouting.provider=istio | grep -q 'kind: VirtualService') || fail "istio VirtualService did not render"
(set +o pipefail; render "${GOOD[@]}" --set trafficRouting.provider=gateway-api | grep -q 'kind: HTTPRoute') || fail "gateway-api HTTPRoute did not render"

echo "All assertions passed."
