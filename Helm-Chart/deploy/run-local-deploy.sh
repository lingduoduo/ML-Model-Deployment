#!/usr/bin/env bash
set -euo pipefail

DEPLOY_ENVIRONMENT="${DEPLOY_ENVIRONMENT:-staging}"
DEPLOY_STRATEGY="${DEPLOY_STRATEGY:-standard}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:?IMAGE_REPOSITORY must be set}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CHART_PATH="${CHART_PATH:-Model-Deployment/chart}"
RELEASE_NAME="${RELEASE_NAME:-model-release}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-model-serving}"
CONTAINER_PORT="${CONTAINER_PORT:-8000}"
SERVICE_PORT="${SERVICE_PORT:-8000}"
LIVENESS_PATH="${LIVENESS_PATH:-/health}"
READINESS_PATH="${READINESS_PATH:-/health}"

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${CURRENT_CONTEXT}" = "minikube" ]; then
  IMAGE_PULL_POLICY="${IMAGE_PULL_POLICY:-Never}"
else
  IMAGE_PULL_POLICY="${IMAGE_PULL_POLICY:-IfNotPresent}"
fi

export DEPLOY_ENVIRONMENT
export DEPLOY_STRATEGY
export IMAGE_REPOSITORY
export IMAGE_TAG
export CHART_PATH
export RELEASE_NAME
export KUBE_NAMESPACE
export IMAGE_PULL_POLICY
export CONTAINER_PORT
export SERVICE_PORT
export LIVENESS_PATH
export READINESS_PATH

echo "Deploying image ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
echo "Target release: ${RELEASE_NAME}"
echo "Target namespace: ${KUBE_NAMESPACE}"
echo "Kubernetes context: ${CURRENT_CONTEXT:-unknown}"
echo "Image pull policy: ${IMAGE_PULL_POLICY}"
echo "Service port: ${SERVICE_PORT}"
echo "Health path: ${LIVENESS_PATH}"

if [ "${CURRENT_CONTEXT}" = "minikube" ]; then
  echo "Minikube detected."
  echo "Make sure the image exists in Minikube before deploying:"
  echo "  eval \$(minikube docker-env)"
  echo "  docker build -t ${IMAGE_REPOSITORY}:${IMAGE_TAG} <app-repo>"
  echo "  or: minikube image load ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
fi

bash "${SCRIPT_DIR}/deploy_with_helm.sh"
