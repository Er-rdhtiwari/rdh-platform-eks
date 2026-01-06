#!/usr/bin/env bash
# Load environment variables from .env (or a provided path) for local/Jenkins use.
set -euo pipefail

ENV_FILE="${1:-.env}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[ERROR] Env file '${ENV_FILE}' not found. Create it from .env.example." >&2
  exit 1
fi

echo "[INFO] Loading environment variables from ${ENV_FILE}"
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

# Map friendly names to Terraform variable overrides for bootstrap/backend use
if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
  export TF_VAR_remote_state_bucket_name="${TF_STATE_BUCKET}"
fi
if [[ -n "${TF_LOCK_TABLE:-}" ]]; then
  export TF_VAR_dynamodb_table_name="${TF_LOCK_TABLE}"
fi

echo "[INFO] Exported variables from ${ENV_FILE}. Current values:"
grep -v '^[[:space:]]*#' "${ENV_FILE}" | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' | while IFS='=' read -r key _; do
  val="${!key-}"
  if [[ -z "${val}" ]]; then
    echo "  ${key}=<empty>"
  else
    echo "  ${key}=${val}"
  fi
done

echo "[INFO] Terraform variable overrides set:"
echo "  TF_VAR_remote_state_bucket_name=${TF_VAR_remote_state_bucket_name-<unset>}"
echo "  TF_VAR_dynamodb_table_name=${TF_VAR_dynamodb_table_name-<unset>}"

# Write bootstrap override tfvars so Terraform picks up the desired state bucket/table
if [[ -n "${TF_STATE_BUCKET:-}" && -n "${TF_LOCK_TABLE:-}" ]]; then
  BOOTSTRAP_TFVARS="terraform/bootstrap/override.auto.tfvars"
  cat > "${BOOTSTRAP_TFVARS}" <<EOF
remote_state_bucket_name = "${TF_STATE_BUCKET}"
dynamodb_table_name      = "${TF_LOCK_TABLE}"
EOF
  echo "[INFO] Wrote ${BOOTSTRAP_TFVARS} for bootstrap."
else
  echo "[WARN] TF_STATE_BUCKET or TF_LOCK_TABLE not set; bootstrap tfvars not written."
fi
