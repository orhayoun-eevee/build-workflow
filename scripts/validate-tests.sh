#!/usr/bin/env bash
# Layer 4: Unit & Regression Testing
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Required environment variables
: "${CHART_PATH:?CHART_PATH is required}"
: "${KUBERNETES_VERSION:?KUBERNETES_VERSION is required}"

# Optional with defaults
SCENARIOS_DIR="${SCENARIOS_DIR:-${CHART_PATH}/tests/scenarios}"
SNAPSHOTS_DIR="${SNAPSHOTS_DIR:-${CHART_PATH}/tests/snapshots}"

info "Layer 4: Unit & Regression Testing"

# Check required commands
check_command helm || exit 1

# Step 1: helm-unittest
if [[ -d "${CHART_PATH}/tests" ]] && find "${CHART_PATH}/tests" -name "*_test.yaml" -o -name "*_test.yml" | grep -q .; then
    info "Step 1/3: Running helm-unittest"
    
    if helm unittest "${CHART_PATH}" --color; then
        success "helm-unittest passed"
    else
        error "helm-unittest failed"
        exit 1
    fi
else
    info "Step 1/3: No unit tests found in ${CHART_PATH}/tests (skipping)"
fi

# Step 2: Scenario snapshot tests
if [[ -d "${SCENARIOS_DIR}" ]]; then
    info "Step 2/3: Running scenario snapshot tests"
    
    # Use shared RENDERED_DIR if available (set by orchestrator), otherwise create temp dir
    if [[ -z "${RENDERED_DIR:-}" ]]; then
        TEMP_DIR=$(mktemp -d)
        trap 'rm -rf "${TEMP_DIR}"' EXIT
    else
        TEMP_DIR="${RENDERED_DIR}"
    fi
    
    SNAPSHOT_FAILED=false
    
    for scenario in "${SCENARIOS_DIR}"/*.yaml "${SCENARIOS_DIR}"/*.yml; do
        [[ ! -f "$scenario" ]] && continue
        
        scenario_name=$(basename "${scenario}" .yaml)
        scenario_name=$(basename "${scenario_name}" .yml)
        
        snapshot_file="${SNAPSHOTS_DIR}/${scenario_name}.yaml"
        rendered_file="${TEMP_DIR}/rendered-${scenario_name}.yaml"
        diff_file="${TEMP_DIR}/snapshot-diff-${scenario_name}.txt"
        
        info "Checking snapshot for scenario: ${scenario_name}"
        
        # Render current output if not already rendered by Layer 2
        if [[ ! -f "${rendered_file}" ]]; then
            if ! helm template test-release "${CHART_PATH}" \
                --values "${scenario}" \
                --kube-version "${KUBERNETES_VERSION}" \
                > "${rendered_file}"; then
                error "Failed to render scenario: ${scenario_name}"
                SNAPSHOT_FAILED=true
                continue
            fi
        fi
        
        # Compare with committed snapshot
        if [[ ! -f "${snapshot_file}" ]]; then
            error "Snapshot file missing: ${snapshot_file}"
            error "Run 'make snapshot-update' to generate it"
            SNAPSHOT_FAILED=true
            continue
        fi
        
        if ! diff -u "${snapshot_file}" "${rendered_file}" > "${diff_file}" 2>&1; then
            error "Snapshot drift detected for scenario: ${scenario_name}"
            cat "${diff_file}"
            error "Run 'make snapshot-update' to update snapshots, then review the diff"
            SNAPSHOT_FAILED=true
        else
            success "Snapshot '${scenario_name}' matches"
        fi
    done
    
    if [[ "${SNAPSHOT_FAILED}" == "true" ]]; then
        error "Snapshot validation failed"
        exit 1
    fi
else
    info "Step 2/3: No scenarios directory found (skipping snapshot tests)"
fi

# Step 3: Schema fail-case tests
FAIL_CASES_DIR="${CHART_PATH}/tests/schema-fail-cases"
if [[ -d "${FAIL_CASES_DIR}" ]] && find "${FAIL_CASES_DIR}" -name "*.yaml" -o -name "*.yml" | grep -q .; then
    info "Step 3/3: Running schema fail-case tests"
    
    FAIL_CASE_FAILED=false
    
    for fail_case in "${FAIL_CASES_DIR}"/*.yaml "${FAIL_CASES_DIR}"/*.yml; do
        [[ ! -f "$fail_case" ]] && continue
        
        fail_case_name=$(basename "${fail_case}")
        
        info "Testing fail-case: ${fail_case_name}"
        
        # This should fail - if it succeeds, that's a problem
        if helm lint "${CHART_PATH}" --values "${fail_case}" 2>/dev/null; then
            error "Schema fail case should have failed but passed: ${fail_case_name}"
            FAIL_CASE_FAILED=true
        else
            success "Fail-case '${fail_case_name}' correctly rejected"
        fi
    done
    
    if [[ "${FAIL_CASE_FAILED}" == "true" ]]; then
        error "Schema fail-case validation failed"
        exit 1
    fi
else
    info "Step 3/3: No schema fail-cases found (skipping)"
fi

success "Layer 4 validation completed successfully"
