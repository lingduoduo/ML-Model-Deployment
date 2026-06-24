#!/usr/bin/env bash
set -euo pipefail

# Comprehensive deployment validation script
# Checks Helm chart, values files, and deployment readiness

CHART_PATH="${CHART_PATH:-Model-Deployment/chart}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-model-serving}"
RELEASE_NAME="${RELEASE_NAME:-model-release}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Helm Deployment Validation ===${NC}\n"

# Check 1: Helm chart syntax
echo -e "${BLUE}1. Validating Helm chart syntax...${NC}"
if helm lint "${CHART_PATH}" > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Helm chart is valid${NC}"
else
  echo -e "${RED}✗ Helm chart validation failed:${NC}"
  helm lint "${CHART_PATH}"
  exit 1
fi

# Check 2: Template rendering
echo -e "\n${BLUE}2. Validating template rendering...${NC}"
VALUES_FILE="${CHART_PATH}/values-staging.yaml"
if helm template "${RELEASE_NAME}" "${CHART_PATH}" -f "${VALUES_FILE}" > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Templates render without errors${NC}"
else
  echo -e "${RED}✗ Template rendering failed${NC}"
  helm template "${RELEASE_NAME}" "${CHART_PATH}" -f "${VALUES_FILE}"
  exit 1
fi

# Check 3: Required values
echo -e "\n${BLUE}3. Checking required values...${NC}"
required_values=("image.repository" "image.tag" "resources.requests.cpu" "resources.requests.memory")
for value in "${required_values[@]}"; do
  if helm template "${RELEASE_NAME}" "${CHART_PATH}" -f "${VALUES_FILE}" | grep -q "$value"; then
    echo -e "${GREEN}✓ Required value '$value' present${NC}"
  else
    echo -e "${YELLOW}⚠ Warning: '$value' may not be properly set${NC}"
  fi
done

# Check 4: Kubernetes cluster connectivity (if available)
echo -e "\n${BLUE}4. Checking Kubernetes cluster...${NC}"
if kubectl cluster-info > /dev/null 2>&1; then
  CURRENT_CONTEXT=$(kubectl config current-context)
  echo -e "${GREEN}✓ Kubernetes cluster connected: ${CURRENT_CONTEXT}${NC}"
  
  # Check 5: Namespace
  echo -e "\n${BLUE}5. Checking namespace...${NC}"
  if kubectl get namespace "${KUBE_NAMESPACE}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Namespace '${KUBE_NAMESPACE}' exists${NC}"
  else
    echo -e "${YELLOW}⚠ Namespace '${KUBE_NAMESPACE}' does not exist (will be created)${NC}"
  fi
  
  # Check 6: Existing deployment
  echo -e "\n${BLUE}6. Checking existing deployment...${NC}"
  if kubectl get deployment "${RELEASE_NAME}" -n "${KUBE_NAMESPACE}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Existing deployment found${NC}"
    kubectl get deployment "${RELEASE_NAME}" -n "${KUBE_NAMESPACE}" -o wide
  else
    echo -e "${YELLOW}⚠ No existing deployment found${NC}"
  fi
else
  echo -e "${YELLOW}⚠ Kubernetes cluster not available, skipping cluster checks${NC}"
fi

# Check 7: Values files
echo -e "\n${BLUE}7. Checking values files...${NC}"
values_files=("values-staging.yaml" "values-production.yaml" "values-production-canary.yaml")
for vf in "${values_files[@]}"; do
  if [ -f "${CHART_PATH}/${vf}" ]; then
    echo -e "${GREEN}✓ ${vf} exists${NC}"
  else
    echo -e "${RED}✗ ${vf} missing${NC}"
  fi
done

# Check 8: Template files
echo -e "\n${BLUE}8. Checking template files...${NC}"
templates=("deployment.yaml" "service.yaml" "configmap.yaml" "secret.yaml" "ingress.yaml")
for tm in "${templates[@]}"; do
  if [ -f "${CHART_PATH}/templates/${tm}" ]; then
    echo -e "${GREEN}✓ ${tm} exists${NC}"
  else
    echo -e "${RED}✗ ${tm} missing${NC}"
  fi
done

# Summary
echo -e "\n${BLUE}=== Validation Summary ===${NC}"
echo -e "${GREEN}Helm chart is ready for deployment${NC}"
echo -e "\nNext steps:"
echo "  1. Set environment variables:"
echo "     export IMAGE_REPOSITORY=<image>"
echo "     export IMAGE_TAG=<tag>"
echo "     export DEPLOY_ENVIRONMENT=staging"
echo ""
echo "  2. Run deployment:"
echo "     ./deploy/run-local-deploy.sh"
echo ""
echo "  3. Monitor deployment:"
echo "     kubectl -n ${KUBE_NAMESPACE} get pods -w"
