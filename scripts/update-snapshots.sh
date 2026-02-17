#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

: "${CHART_PATH:?CHART_PATH is required}"
: "${KUBERNETES_VERSION:?KUBERNETES_VERSION is required}"

SCENARIOS_DIR="${SCENARIOS_DIR:-tests/scenarios}"
SNAPSHOTS_DIR="${SNAPSHOTS_DIR:-tests/snapshots}"

check_command helm || exit 1

mkdir -p "${SNAPSHOTS_DIR}"
shopt -s nullglob
scenarios=("${SCENARIOS_DIR}"/*.yaml "${SCENARIOS_DIR}"/*.yml)
if [[ ${#scenarios[@]} -eq 0 ]]; then
    error "No scenarios found in ${SCENARIOS_DIR}"
    exit 1
fi

info "Regenerating snapshots from ${SCENARIOS_DIR}"
for scenario in "${scenarios[@]}"; do
    scenario_name="$(basename "${scenario}")"
    scenario_name="${scenario_name%.yaml}"
    scenario_name="${scenario_name%.yml}"

    info "Updating snapshot: ${scenario_name}"
    helm template test-release "${CHART_PATH}" \
        --values "${scenario}" \
        --kube-version "${KUBERNETES_VERSION}" \
        > "${SNAPSHOTS_DIR}/${scenario_name}.yaml"
done

success "Snapshots updated in ${SNAPSHOTS_DIR}"
