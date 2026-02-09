#!/usr/bin/env bash
# Layer 1: Syntax & Structure validation
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Required environment variables
: "${CHART_PATH:?CHART_PATH is required}"

# Optional with defaults
CONFIGS_DIR="${CONFIGS_DIR:-${SCRIPT_DIR}/../configs}"

info "Layer 1: Syntax & Structure validation"

# Check required commands
check_command yamllint || exit 1
check_command helm || exit 1

# Step 1: yamllint on values.yaml and Chart.yaml
info "Step 1/2: Running yamllint on values.yaml and Chart.yaml"

if [[ -f "${CHART_PATH}/values.yaml" ]]; then
    if yamllint -c "${CONFIGS_DIR}/yamllint.yaml" "${CHART_PATH}/values.yaml"; then
        success "yamllint passed for values.yaml"
    else
        error "yamllint failed for values.yaml"
        exit 1
    fi
else
    warn "values.yaml not found in ${CHART_PATH}"
fi

if [[ -f "${CHART_PATH}/Chart.yaml" ]]; then
    if yamllint -c "${CONFIGS_DIR}/yamllint.yaml" "${CHART_PATH}/Chart.yaml"; then
        success "yamllint passed for Chart.yaml"
    else
        error "yamllint failed for Chart.yaml"
        exit 1
    fi
else
    error "Chart.yaml not found in ${CHART_PATH}"
    exit 1
fi

# Step 2: helm lint --strict (includes values.schema.json validation if present)
info "Step 2/2: Running helm lint --strict"

if helm lint "${CHART_PATH}" --strict; then
    success "helm lint --strict passed"
else
    error "helm lint --strict failed"
    exit 1
fi

success "Layer 1 validation completed successfully"
