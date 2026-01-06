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

echo "[INFO] Verifying connectivity to cluster (kubeconfig must already be set)"
kubectl cluster-info

echo "[INFO] Nodes"
kubectl get nodes -o wide

echo "[INFO] System pods (ready/unready)"
kubectl get pods -A -o wide

if kubectl get deployment aws-load-balancer-controller -n kube-system >/dev/null 2>&1; then
  echo "[INFO] ALB controller deployment"
  kubectl get deployment aws-load-balancer-controller -n kube-system -o wide
  kubectl get sa aws-load-balancer-controller -n kube-system \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}' || true
fi

if kubectl get deployment external-dns -n kube-system >/dev/null 2>&1; then
  echo "[INFO] external-dns deployment"
  kubectl get deployment external-dns -n kube-system -o wide
  kubectl get sa external-dns -n kube-system \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}' || true
fi

if kubectl get deployment cert-manager -n cert-manager >/dev/null 2>&1; then
  echo "[INFO] cert-manager deployment"
  kubectl get deployment -n cert-manager -o wide
  kubectl get sa cert-manager -n cert-manager \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}' || true
fi

if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
  echo "[INFO] metrics-server deployment"
  kubectl get deployment metrics-server -n kube-system -o wide
fi

echo "[INFO] Verifying ALB controller webhooks"
kubectl get validatingwebhookconfiguration | grep -i alb || true

echo "[INFO] Cluster verification complete"
