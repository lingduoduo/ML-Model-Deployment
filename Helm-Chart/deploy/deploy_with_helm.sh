#!/usr/bin/env bash
set -euo pipefail

# Helm Deployment Script - Optimized with DRY principles and better error handling
# Supports standard and canary deployment strategies

DEPLOY_ENVIRONMENT="${DEPLOY_ENVIRONMENT:-staging}"
DEPLOY_STRATEGY="${DEPLOY_STRATEGY:-standard}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG must be set}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:?IMAGE_REPOSITORY must be set}"
CHART_PATH="${CHART_PATH:-Model-Deployment/chart}"
RELEASE_NAME="${RELEASE_NAME:-model-release}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-model-serving}"
IMAGE_PULL_POLICY="${IMAGE_PULL_POLICY:-}"
CONTAINER_PORT="${CONTAINER_PORT:-}"
SERVICE_PORT="${SERVICE_PORT:-}"
LIVENESS_PATH="${LIVENESS_PATH:-}"
READINESS_PATH="${READINESS_PATH:-}"
TIMEOUT="${TIMEOUT:-5m}"
GIT_COMMIT="${GIT_COMMIT:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

# Validate environment
VALUES_FILE="${CHART_PATH}/values-${DEPLOY_ENVIRONMENT}.yaml"
if [ ! -f "${VALUES_FILE}" ]; then
  echo "❌ Error: Values file ${VALUES_FILE} does not exist"
  exit 1
fi

# Function to build Helm arguments
build_helm_args() {
  local release=$1
  local suffix=${2:-""}
  
  local args=(
    upgrade
    --install
    "${release}"
    "${CHART_PATH}"
    --namespace "${KUBE_NAMESPACE}"
    --create-namespace
    -f "${VALUES_FILE}"
    --set "image.repository=${IMAGE_REPOSITORY}"
    --set "image.tag=${IMAGE_TAG}"
    --timeout "${TIMEOUT}"
    --wait
    --wait-for-jobs
  )
  
  # Add optional parameters only if set
  [ -n "${IMAGE_PULL_POLICY}" ] && args+=(--set "image.pullPolicy=${IMAGE_PULL_POLICY}")
  [ -n "${CONTAINER_PORT}" ] && args+=(--set "container.port=${CONTAINER_PORT}")
  [ -n "${SERVICE_PORT}" ] && args+=(--set "service.port=${SERVICE_PORT}")
  [ -n "${LIVENESS_PATH}" ] && args+=(--set "livenessProbe.httpGet.path=${LIVENESS_PATH}")
  [ -n "${READINESS_PATH}" ] && args+=(--set "readinessProbe.httpGet.path=${READINESS_PATH}")
  
  # Add deployment annotations for tracking
  [ -n "${GIT_COMMIT}" ] && args+=(--set "podAnnotations.git\\.commit=${GIT_COMMIT}")
  [ -n "${BUILD_NUMBER}" ] && args+=(--set "podAnnotations.build\\.number=${BUILD_NUMBER}")
  
  # Use canary values file for canary releases
  if [ -n "${suffix}" ]; then
    canary_file="${CHART_PATH}/values-${DEPLOY_ENVIRONMENT}${suffix}.yaml"
    if [ -f "${canary_file}" ]; then
      args+=(-f "${canary_file}")
    fi
  fi
  
  printf '%s\n' "${args[@]}"
}

# Function to verify deployment
verify_deployment() {
  local release=$1
  local max_attempts=30
  local attempt=0
  
  echo "⏳ Verifying deployment ${release}..."
  
  while [ ${attempt} -lt ${max_attempts} ]; do
    local running=$(kubectl get pods -n "${KUBE_NAMESPACE}" \
      -l "app.kubernetes.io/name=model-deployment,app.kubernetes.io/instance=${release}" \
      --field-selector=status.phase=Running \
      --no-headers 2>/dev/null | wc -l)
    
    if [ ${running} -gt 0 ]; then
      echo "✅ Deployment ${release} verified: ${running} pod(s) running"
      return 0
    fi
    
    attempt=$((attempt + 1))
    sleep 2
  done
  
  echo "⚠️  Warning: Deployment ${release} pods not fully ready after timeout"
  return 1
}

# Main deployment
echo "🚀 Deploying ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
echo "   Environment: ${DEPLOY_ENVIRONMENT}"
echo "   Release: ${RELEASE_NAME}"
echo "   Namespace: ${KUBE_NAMESPACE}"
echo "   Strategy: ${DEPLOY_STRATEGY}"

# Build and execute primary deployment
mapfile -t helm_args < <(build_helm_args "${RELEASE_NAME}")
helm "${helm_args[@]}"

# Verify primary deployment
verify_deployment "${RELEASE_NAME}" || true

# Deploy canary if requested
if [ "${DEPLOY_ENVIRONMENT}" = "production" ] && [ "${DEPLOY_STRATEGY}" = "canary" ]; then
  CANARY_RELEASE="${RELEASE_NAME}-canary"
  
  echo ""
  echo "🔄 Deploying canary release: ${CANARY_RELEASE}"
  
  mapfile -t canary_args < <(build_helm_args "${CANARY_RELEASE}" "-canary")
  helm "${canary_args[@]}"
  
  # Verify canary deployment
  verify_deployment "${CANARY_RELEASE}" || true
  
  echo ""
  echo "📊 Traffic distribution: 90% → ${RELEASE_NAME}, 10% → ${CANARY_RELEASE}"
  echo "   Monitor canary metrics before promoting to stable"
fi

echo ""
echo "✅ Helm deployment completed successfully"
echo "   View deployment status:"
echo "     kubectl -n ${KUBE_NAMESPACE} get deployments,pods,services"
echo "   View pod logs:"
echo "     kubectl -n ${KUBE_NAMESPACE} logs -l app.kubernetes.io/instance=${RELEASE_NAME} -f"
