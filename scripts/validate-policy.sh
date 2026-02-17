#!/usr/bin/env bash
# Layer 5: Policy Enforcement
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

# Required environment variables
: "${CHART_PATH:?CHART_PATH is required}"
: "${KUBERNETES_VERSION:?KUBERNETES_VERSION is required}"

# Optional with defaults
CONFIGS_DIR="${CONFIGS_DIR:-${SCRIPT_DIR}/../configs}"
CHECKOV_EXTRA_ARGS="${CHECKOV_EXTRA_ARGS:-}"

info "Layer 5: Policy Enforcement"

# Check required commands
check_command checkov || exit 1
check_command kube-linter || exit 1

# We need rendered manifests from the full.yaml scenario
SCENARIOS_DIR="${SCENARIOS_DIR:-${CHART_PATH}/tests/scenarios}"
FULL_SCENARIO="${SCENARIOS_DIR}/full.yaml"

if [[ ! -f "${FULL_SCENARIO}" ]]; then
	error "full.yaml scenario not found at ${FULL_SCENARIO}"
	error "Layer 5 requires a full.yaml scenario that enables all features"
	error "Hint: SCENARIOS_DIR=${SCENARIOS_DIR}"
	exit 1
fi

# Use shared RENDERED_DIR if available, otherwise use /tmp
if [[ -n "${RENDERED_DIR:-}" ]]; then
	RENDERED_FILE="${RENDERED_DIR}/rendered-full.yaml"
else
	RENDERED_FILE="/tmp/rendered-full.yaml"
fi

# Render if not already rendered by Layer 2
if [[ ! -f "${RENDERED_FILE}" ]]; then
	info "Rendering full.yaml scenario for policy scanning"

	if ! helm template test-release "${CHART_PATH}" \
		--values "${FULL_SCENARIO}" \
		--kube-version "${KUBERNETES_VERSION}" \
		>"${RENDERED_FILE}"; then
		error "Failed to render full.yaml scenario"
		exit 1
	fi
else
	info "Using pre-rendered full.yaml scenario from Layer 2"
fi

# Step 1: Checkov
info "Step 1/2: Running Checkov"

# Build Checkov arguments
CHECKOV_ARGS="--file ${RENDERED_FILE} --framework kubernetes --compact --quiet"

# Use chart-specific .checkov.yaml if it exists
if [[ -f "${CHART_PATH}/.checkov.yaml" ]]; then
	CHECKOV_ARGS="${CHECKOV_ARGS} --config-file ${CHART_PATH}/.checkov.yaml"
	info "Using chart-specific Checkov config: ${CHART_PATH}/.checkov.yaml"
elif [[ -f ".checkov.yaml" ]]; then
	CHECKOV_ARGS="${CHECKOV_ARGS} --config-file .checkov.yaml"
	info "Using repo-level Checkov config: .checkov.yaml"
fi

# Append any extra args
if [[ -n "${CHECKOV_EXTRA_ARGS}" ]]; then
	CHECKOV_ARGS="${CHECKOV_ARGS} ${CHECKOV_EXTRA_ARGS}"
fi

# shellcheck disable=SC2086
if checkov ${CHECKOV_ARGS}; then
	success "Checkov passed"
else
	error "Checkov found policy violations"
	exit 1
fi

# Step 2: kube-linter
info "Step 2/2: Running kube-linter"

# Use chart-specific config if it exists, otherwise use framework default
if [[ -f "${CHART_PATH}/.kube-linter.yaml" ]]; then
	KUBELINTER_CONFIG="${CHART_PATH}/.kube-linter.yaml"
	info "Using chart-specific kube-linter config: ${KUBELINTER_CONFIG}"
else
	KUBELINTER_CONFIG="${CONFIGS_DIR}/kube-linter-default.yaml"
	info "Using framework default kube-linter config: ${KUBELINTER_CONFIG}"
fi

if kube-linter lint "${RENDERED_FILE}" --config "${KUBELINTER_CONFIG}"; then
	success "kube-linter passed"
else
	error "kube-linter found policy violations"
	exit 1
fi

success "Layer 5 validation completed successfully"
