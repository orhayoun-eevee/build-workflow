#!/usr/bin/env bash
# Run a kind-backed Helm install smoke using the chart's minimal scenario values.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

: "${CHART_PATH:?CHART_PATH is required}"
: "${VALUES_FILE:?VALUES_FILE is required}"
: "${SMOKE_RELEASE_NAME:?SMOKE_RELEASE_NAME is required}"
: "${SMOKE_NAMESPACE:?SMOKE_NAMESPACE is required}"

if [[ ! -f "${CHART_PATH}/Chart.yaml" ]]; then
	error "Chart.yaml not found in ${CHART_PATH}"
	exit 1
fi

if [[ ! -f "${VALUES_FILE}" ]]; then
	error "Values file not found: ${VALUES_FILE}"
	exit 1
fi

check_command helm || exit 1
check_command kubectl || exit 1

info "Resolving chart dependencies for ${CHART_PATH}"
helm dependency build "${CHART_PATH}"

info "Installing ${CHART_PATH} with ${VALUES_FILE}"
helm install "${SMOKE_RELEASE_NAME}" "${CHART_PATH}" \
	--namespace "${SMOKE_NAMESPACE}" \
	--create-namespace \
	--values "${VALUES_FILE}"

info "Captured installed resources"
kubectl get all -n "${SMOKE_NAMESPACE}" || true
kubectl get pvc -n "${SMOKE_NAMESPACE}" || true

success "Install smoke completed successfully"
