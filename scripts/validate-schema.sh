#!/usr/bin/env bash
# Layer 2: Kubernetes Schema validation
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

# Required environment variables
: "${CHART_PATH:?CHART_PATH is required}"
: "${KUBERNETES_VERSION:?KUBERNETES_VERSION is required}"

# Optional with defaults
SCENARIOS_DIR="${SCENARIOS_DIR:-${CHART_PATH}/tests/scenarios}"

info "Layer 2: Kubernetes Schema validation"

# Check required commands
check_command helm || exit 1
check_command kubeconform || exit 1

# Check if scenarios directory exists
if [[ ! -d "${SCENARIOS_DIR}" ]]; then
    error "Scenarios directory not found: ${SCENARIOS_DIR}"
    exit 1
fi

# Count scenarios
scenario_count=$(find "${SCENARIOS_DIR}" -name "*.yaml" -o -name "*.yml" | wc -l)
if [[ $scenario_count -eq 0 ]]; then
    error "No scenario files found in ${SCENARIOS_DIR}"
    exit 1
fi

info "Found ${scenario_count} scenario(s) to validate"

# Use shared RENDERED_DIR if available (set by orchestrator), otherwise create temp dir
if [[ -z "${RENDERED_DIR:-}" ]]; then
    RENDERED_DIR=$(mktemp -d)
    trap 'rm -rf "${RENDERED_DIR}"' EXIT
fi

# Validate each scenario
FAILED=false

for scenario in "${SCENARIOS_DIR}"/*.yaml "${SCENARIOS_DIR}"/*.yml; do
    [[ ! -f "$scenario" ]] && continue
    
    scenario_name=$(basename "${scenario}" .yaml)
    scenario_name=$(basename "${scenario_name}" .yml)
    
    info "Validating scenario: ${scenario_name}"
    
    # Render manifests
    rendered_file="${RENDERED_DIR}/rendered-${scenario_name}.yaml"
    if ! helm template test-release "${CHART_PATH}" \
        --values "${scenario}" \
        --kube-version "${KUBERNETES_VERSION}" \
        > "${rendered_file}"; then
        error "Failed to render scenario: ${scenario_name}"
        FAILED=true
        continue
    fi
    
    # Validate with kubeconform
    if kubeconform \
        -kubernetes-version "${KUBERNETES_VERSION}" \
        -strict \
        -summary \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        "${rendered_file}"; then
        success "Scenario '${scenario_name}' passed kubeconform validation"
    else
        error "Scenario '${scenario_name}' failed kubeconform validation"
        FAILED=true
    fi
done

if [[ "${FAILED}" == "true" ]]; then
    error "Layer 2 validation failed for one or more scenarios"
    exit 1
fi

success "Layer 2 validation completed successfully"
