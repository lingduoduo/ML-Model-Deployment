#!/usr/bin/env bash
# Lint + render the chart against every environment values file and assert
# the optimization invariants hold. Usage: scripts/verify-render.sh
set -euo pipefail

command -v helm >/dev/null 2>&1 || { echo "helm not found on PATH" >&2; exit 1; }

CHART="$(cd "$(dirname "$0")/.." && pwd)"
REPO_OVERRIDE="${IMAGE_REPOSITORY:-ghcr.io/example/model-server}"
TAG_OVERRIDE="${IMAGE_TAG:-ci-test}"

ENVS=("" "values-staging" "values-production" "values-production-canary")

fail() { echo "ASSERTION FAILED: $1" >&2; exit 1; }

for env in "${ENVS[@]}"; do
  label="${env:-base}"
  args=(--set "image.repository=${REPO_OVERRIDE}" --set "image.tag=${TAG_OVERRIDE}")
  if [ -n "$env" ]; then
    [ -f "${CHART}/${env}.yaml" ] || fail "${label}: values file ${env}.yaml not found"
    args+=(-f "${CHART}/${env}.yaml")
  fi

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
  if grep -q 'deployment.kubernetes.io/timestamp' <<<"$out"; then fail "${label}: timestamp annotation still present"; fi

  # Render must be deterministic (no churn).
  out2="$(helm template render "${CHART}" "${args[@]}")"
  [ "$out" = "$out2" ] || fail "${label}: render not deterministic"
done

echo "All assertions passed."
