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

echo "[INFO] Exported variables from ${ENV_FILE}. Current values:"
grep -v '^[[:space:]]*#' "${ENV_FILE}" | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' | while IFS='=' read -r key _; do
  val="${!key-}"
  if [[ -z "${val}" ]]; then
    echo "  ${key}=<empty>"
  else
    echo "  ${key}=${val}"
  fi
done
