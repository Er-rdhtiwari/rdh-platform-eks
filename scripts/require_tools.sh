#!/usr/bin/env bash
set -euo pipefail

REQUIRED_TOOLS=(aws terraform kubectl helm jq envsubst)

check_tool() {
  local bin=$1
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[ERROR] $bin not found in PATH. Please install before continuing." >&2
    exit 1
  fi
  case "$bin" in
    terraform) $bin version | head -n 1;;
    aws) $bin --version;;
    kubectl) $bin version --client --short;;
    helm) $bin version --short;;
    jq) $bin --version;;
    envsubst) $bin --version || echo "envsubst present";;
    *) $bin --version;;
  esac
}

for tool in "${REQUIRED_TOOLS[@]}"; do
  check_tool "$tool"
done

echo "All required tools are available."
