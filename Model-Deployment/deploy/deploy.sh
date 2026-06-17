#!/usr/bin/env bash
# Render + apply the model-deployment chart for one environment.
# Required env: DEPLOY_ENVIRONMENT (dev|staging|production), DEPLOYMENT_PATTERN,
# IMAGE_REPOSITORY, IMAGE_TAG, MODEL_VERSION. Optional: ROLLOUT_STRATEGY,
# GATE_ENABLED, GATE_MODE, RELEASE_NAME, KUBE_NAMESPACE, DEPLOY_VARIANT.
# DEPLOY_VARIANT: standard (default) | canary. When DEPLOY_VARIANT=canary and
# DEPLOY_ENVIRONMENT=production, deploys values-production-canary.yaml as a
# separate release named <RELEASE_NAME>-canary.
set -euo pipefail

CHART="$(cd "$(dirname "$0")/../chart" && pwd)"
ENVIRONMENT="${DEPLOY_ENVIRONMENT:?set DEPLOY_ENVIRONMENT}"
PATTERN="${DEPLOYMENT_PATTERN:?set DEPLOYMENT_PATTERN}"
RELEASE_NAME="${RELEASE_NAME:-model-release}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-model-serving}"
DEPLOY_VARIANT="${DEPLOY_VARIANT:-standard}"

case "$ENVIRONMENT" in
  dev)        VALUES="values-dev.yaml" ;;
  staging)    VALUES="values-staging.yaml" ;;
  production)
    if [ "$DEPLOY_VARIANT" = "canary" ]; then
      VALUES="values-production-canary.yaml"
      RELEASE_NAME="${RELEASE_NAME}-canary"
    else
      VALUES="values-production.yaml"
    fi
    ;;
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
