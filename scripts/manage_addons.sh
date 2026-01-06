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

ACTION=${1:-install}
AWS_REGION=${AWS_REGION:-ap-south-1}
TF_DIR=${TF_DIR:-terraform/env}

ALB_CHART_VERSION=${ALB_CHART_VERSION:-1.7.2}
EXTERNAL_DNS_CHART_VERSION=${EXTERNAL_DNS_CHART_VERSION:-1.14.5}
CERT_MANAGER_CHART_VERSION=${CERT_MANAGER_CHART_VERSION:-1.14.4}
METRICS_SERVER_CHART_VERSION=${METRICS_SERVER_CHART_VERSION:-3.11.0}

if ! command -v jq >/dev/null 2>&1; then
  echo "[ERROR] jq is required" >&2
  exit 1
fi

outputs=$(terraform -chdir="$TF_DIR" output -json)
cluster_name=$(echo "$outputs" | jq -r '.cluster_name.value')
vpc_id=$(echo "$outputs" | jq -r '.vpc_id.value')
alb_role_arn=$(echo "$outputs" | jq -r '.alb_controller_role_arn.value')
ext_dns_role_arn=$(echo "$outputs" | jq -r '.external_dns_role_arn.value // empty')
cert_manager_role_arn=$(echo "$outputs" | jq -r '.cert_manager_role_arn.value // empty')
poc_domain=$(echo "$outputs" | jq -r '.poc_domain.value')
poc_zone_id=$(echo "$outputs" | jq -r '.poc_hosted_zone_id.value')
enable_cert_from_tf=$(echo "$outputs" | jq -r '.enable_cert_manager.value // "true"')
enable_extdns_from_tf=$(echo "$outputs" | jq -r '.enable_external_dns.value // "true"')
enable_metrics_from_tf=$(echo "$outputs" | jq -r '.enable_metrics_server.value // "true"')

ENABLE_CERT_MANAGER=${ENABLE_CERT_MANAGER:-$enable_cert_from_tf}
ENABLE_EXTERNAL_DNS=${ENABLE_EXTERNAL_DNS:-$enable_extdns_from_tf}
ENABLE_METRICS_SERVER=${ENABLE_METRICS_SERVER:-$enable_metrics_from_tf}
ENABLE_CERT_MANAGER=$(echo "$ENABLE_CERT_MANAGER" | tr '[:upper:]' '[:lower:]')
ENABLE_EXTERNAL_DNS=$(echo "$ENABLE_EXTERNAL_DNS" | tr '[:upper:]' '[:lower:]')
ENABLE_METRICS_SERVER=$(echo "$ENABLE_METRICS_SERVER" | tr '[:upper:]' '[:lower:]')

if [[ -z "$cluster_name" ]]; then
  echo "[ERROR] cluster_name output not found; run Terraform apply first." >&2
  exit 1
fi
if [[ "$ENABLE_EXTERNAL_DNS" == "true" && -z "$poc_zone_id" ]]; then
  echo "[ERROR] external-dns enabled but poc_hosted_zone_id output is empty." >&2
  exit 1
fi
if [[ "$ENABLE_CERT_MANAGER" == "true" && -z "$poc_zone_id" ]]; then
  echo "[ERROR] cert-manager enabled but poc_hosted_zone_id output is empty." >&2
  exit 1
fi

DRY_RUN=""
case "$ACTION" in
  install|upgrade) DRY_RUN="" ;;
  plan) DRY_RUN="--dry-run --debug" ;;
  uninstall) ;; 
  *) echo "[ERROR] ACTION must be install|upgrade|plan|uninstall" >&2; exit 1 ;;
esac

helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ >/dev/null
helm repo add jetstack https://charts.jetstack.io >/dev/null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update >/dev/null

install_alb() {
  echo "[INFO] ${ACTION^} aws-load-balancer-controller"
  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace kube-system \
    --set clusterName="$cluster_name" \
    --set region="$AWS_REGION" \
    --set vpcId="$vpc_id" \
    --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="$alb_role_arn" \
    --set serviceAccount.create=true \
    --set serviceAccount.name="aws-load-balancer-controller" \
    --version "$ALB_CHART_VERSION" \
    --wait --timeout 10m $DRY_RUN
}

install_external_dns() {
  if [[ "$ENABLE_EXTERNAL_DNS" != "true" ]]; then
    echo "[INFO] external-dns disabled; skipping"
    return
  fi
  echo "[INFO] ${ACTION^} external-dns"
  helm upgrade --install external-dns external-dns/external-dns \
    --namespace kube-system \
    --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="$ext_dns_role_arn" \
    --set serviceAccount.create=true \
    --set serviceAccount.name="external-dns" \
    --set domainFilters="{$poc_domain}" \
    --set zoneIdFilters="{$poc_zone_id}" \
    --set policy="sync" \
    --set txtOwnerId="$cluster_name" \
    --version "$EXTERNAL_DNS_CHART_VERSION" \
    --wait --timeout 10m $DRY_RUN
}

install_cert_manager() {
  if [[ "$ENABLE_CERT_MANAGER" != "true" ]]; then
    echo "[INFO] cert-manager disabled; skipping"
    return
  fi
  echo "[INFO] ${ACTION^} cert-manager"
  kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --set installCRDs=true \
    --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="$cert_manager_role_arn" \
    --set serviceAccount.create=true \
    --set serviceAccount.name="cert-manager" \
    --version "$CERT_MANAGER_CHART_VERSION" \
    --wait --timeout 10m $DRY_RUN
}

install_metrics_server() {
  if [[ "$ENABLE_METRICS_SERVER" != "true" ]]; then
    echo "[INFO] metrics-server disabled; skipping"
    return
  fi
  echo "[INFO] ${ACTION^} metrics-server"
  helm upgrade --install metrics-server metrics-server/metrics-server \
    --namespace kube-system \
    --version "$METRICS_SERVER_CHART_VERSION" \
    --wait --timeout 5m $DRY_RUN
}

uninstall_all() {
  echo "[INFO] Uninstalling add-ons"
  helm uninstall aws-load-balancer-controller --namespace kube-system || true
  helm uninstall external-dns --namespace kube-system || true
  helm uninstall cert-manager --namespace cert-manager || true
  helm uninstall metrics-server --namespace kube-system || true
}

case "$ACTION" in
  uninstall)
    uninstall_all
    ;;
  install|upgrade|plan)
    install_alb
    install_external_dns
    install_cert_manager
    install_metrics_server
    ;;
esac

echo "[INFO] Add-on action '$ACTION' complete"
