#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.env"
  set +a
fi
cd "${REPO_ROOT}"

AWS_REGION=${AWS_REGION:-ap-south-1}
ENVIRONMENT=${ENVIRONMENT:-dev}
TF_DIR=${TF_DIR:-terraform/env}

CLUSTER_NAME=${CLUSTER_NAME:-$(terraform -chdir="$TF_DIR" output -raw cluster_name 2>/dev/null || true)}
if [[ -z "${CLUSTER_NAME}" ]]; then
  echo "[ERROR] cluster_name not found. Run Terraform apply first or set CLUSTER_NAME env var." >&2
  exit 1
fi

ALIAS="${CLUSTER_NAME}-${ENVIRONMENT}"
echo "Updating kubeconfig for cluster ${CLUSTER_NAME} in ${AWS_REGION} (alias: ${ALIAS})"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" --alias "${ALIAS}"
