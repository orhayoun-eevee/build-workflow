#!/usr/bin/env bash
# Orchestrator for validation layers - runs all layers sequentially with fast-fail.
# Requires bash 4+ (associative arrays). Runs inside the Docker image (bash 5+).
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
SNAPSHOTS_DIR="${SNAPSHOTS_DIR:-${CHART_PATH}/tests/snapshots}"
TARGET_BRANCH="${TARGET_BRANCH:-main}"
CONFIGS_DIR="${CONFIGS_DIR:-${SCRIPT_DIR}/../configs}"
RUN_SYNTAX="${RUN_SYNTAX:-true}"
RUN_SCHEMA="${RUN_SCHEMA:-true}"
RUN_METADATA="${RUN_METADATA:-true}"
RUN_TESTS="${RUN_TESTS:-true}"
RUN_POLICY="${RUN_POLICY:-true}"

# Create shared temp directory for rendered manifests (avoids duplicate rendering)
RENDERED_DIR=$(mktemp -d)
trap 'rm -rf "${RENDERED_DIR}"' EXIT

# Export for child scripts
export CHART_PATH KUBERNETES_VERSION SCENARIOS_DIR SNAPSHOTS_DIR TARGET_BRANCH CONFIGS_DIR RENDERED_DIR RUN_VERSION_CHECK

# Track results for summary
declare -A DURATIONS
declare -A RESULTS
LAYERS_RUN=()

# Run a single layer with timing
run_layer() {
    local layer_id="$1"
    local layer_name="$2"
    local script_name="$3"

    info "========================================="
    info "Running ${layer_name}"
    info "========================================="

    local start_time
    start_time=$(date +%s)

    if "${SCRIPT_DIR}/${script_name}"; then
        local duration=$(( $(date +%s) - start_time ))
        DURATIONS[$layer_id]=$duration
        LAYERS_RUN+=("$layer_id")
        success "${layer_name} completed in ${duration}s"
        return 0
    else
        local duration=$(( $(date +%s) - start_time ))
        DURATIONS[$layer_id]=$duration
        LAYERS_RUN+=("$layer_id")
        error "${layer_name} failed after ${duration}s"
        return 1
    fi
}

run_or_skip_layer() {
    local layer_id="$1"
    local layer_name="$2"
    local script_name="$3"
    local enabled="$4"

    local enabled_lower
    enabled_lower=$(echo "${enabled}" | tr '[:upper:]' '[:lower:]')

    if [[ "${enabled_lower}" == "true" ]]; then
        run_layer "${layer_id}" "${layer_name}" "${script_name}" || return 1
        RESULTS[$layer_id]="PASS"
    else
        info "========================================="
        info "Skipping ${layer_name} (disabled)"
        info "========================================="
        DURATIONS[$layer_id]=0
        RESULTS[$layer_id]="SKIPPED"
        LAYERS_RUN+=("$layer_id")
    fi
}

# Pipeline header
info "Starting Helm validation pipeline"
info "Chart: ${CHART_PATH}"
info "Kubernetes version: ${KUBERNETES_VERSION}"

# Run layers sequentially with fast-fail
run_or_skip_layer "L1" "Layer 1: Syntax & Structure" "validate-syntax.sh" "${RUN_SYNTAX}"   || { error "Stopped at Layer 1"; exit 1; }
run_or_skip_layer "L2" "Layer 2: Schema Validation"  "validate-schema.sh" "${RUN_SCHEMA}"   || { error "Stopped at Layer 2"; exit 1; }
run_or_skip_layer "L3" "Layer 3: Metadata & Version" "validate-metadata.sh" "${RUN_METADATA}" || { error "Stopped at Layer 3"; exit 1; }
run_or_skip_layer "L4" "Layer 4: Tests & Snapshots"  "validate-tests.sh" "${RUN_TESTS}"    || { error "Stopped at Layer 4"; exit 1; }
run_or_skip_layer "L5" "Layer 5: Policy Enforcement" "validate-policy.sh" "${RUN_POLICY}"   || { error "Stopped at Layer 5"; exit 1; }

# Summary (only reached when all layers pass)
info "========================================="
info "Validation Summary"
info "========================================="

TOTAL_DURATION=0
for layer in "${LAYERS_RUN[@]}"; do
    if [[ "${RESULTS[$layer]}" == "SKIPPED" ]]; then
        warn "${layer}: SKIPPED"
    else
        success "${layer}: PASS (${DURATIONS[$layer]}s)"
        TOTAL_DURATION=$((TOTAL_DURATION + DURATIONS[$layer]))
    fi
done

info "========================================="
success "All validation layers passed!"
info "Total duration: ${TOTAL_DURATION}s"
info "Kubernetes version: ${KUBERNETES_VERSION}"
info "========================================="
