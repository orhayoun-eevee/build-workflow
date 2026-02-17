#!/usr/bin/env bash
# Layer 3: Chart Metadata & Version validation
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

# Required environment variables
: "${CHART_PATH:?CHART_PATH is required}"

# Optional with defaults
CONFIGS_DIR="${CONFIGS_DIR:-${SCRIPT_DIR}/../configs}"
TARGET_BRANCH="${TARGET_BRANCH:-main}"
RUN_VERSION_CHECK="${RUN_VERSION_CHECK:-true}"

info "Layer 3: Chart Metadata & Version validation"

# Check required commands
check_command ct || exit 1
check_command yq || exit 1

# Step 1: ct lint
info "Step 1/2: Running chart-testing (ct lint)"

# Build ct config: start from chart-local ct.yaml or framework default,
# then ensure chart-yaml-schema and lint-conf point to framework configs
CT_CONFIG=$(mktemp /tmp/ct-config-XXXXXX.yaml)

if [[ -f "ct.yaml" ]]; then
	cp "ct.yaml" "${CT_CONFIG}"
	info "Using chart-local ct.yaml as base"
elif [[ -f "${CONFIGS_DIR}/ct-default.yaml" ]]; then
	cp "${CONFIGS_DIR}/ct-default.yaml" "${CT_CONFIG}"
	info "Using framework default ct config as base"
else
	error "No ct config found (checked ./ct.yaml and ${CONFIGS_DIR}/ct-default.yaml)"
	rm -f "${CT_CONFIG}"
	exit 1
fi

# Ensure chart-yaml-schema and lint-conf resolve to framework configs (absolute paths)
if [[ -f "${CONFIGS_DIR}/chart_schema.yaml" ]]; then
	yq -i ".\"chart-yaml-schema\" = \"${CONFIGS_DIR}/chart_schema.yaml\"" "${CT_CONFIG}"
fi
if [[ -f "${CONFIGS_DIR}/yamllint.yaml" ]]; then
	yq -i ".\"lint-conf\" = \"${CONFIGS_DIR}/yamllint.yaml\"" "${CT_CONFIG}"
fi

info "Resolved ct config paths to ${CONFIGS_DIR}"

if ct lint \
	--config "${CT_CONFIG}" \
	--charts "${CHART_PATH}" \
	--target-branch "${TARGET_BRANCH}"; then
	success "ct lint passed"
else
	error "ct lint failed"
	rm -f "${CT_CONFIG}"
	exit 1
fi

rm -f "${CT_CONFIG}"

# Step 2: Version strictly greater check
if [[ "${RUN_VERSION_CHECK}" == "true" ]]; then
	info "Step 2/2: Verifying Chart version is strictly greater than previous"

	# Get current version from Chart.yaml
	if [[ ! -f "${CHART_PATH}/Chart.yaml" ]]; then
		error "Chart.yaml not found in ${CHART_PATH}"
		exit 1
	fi

	CURRENT_VERSION=$(yq '.version' "${CHART_PATH}/Chart.yaml")
	info "Current version: ${CURRENT_VERSION}"

	# Try to get previous version from target branch
	if git show "${TARGET_BRANCH}:${CHART_PATH}/Chart.yaml" &>/dev/null; then
		PREVIOUS_VERSION=$(git show "${TARGET_BRANCH}:${CHART_PATH}/Chart.yaml" | yq '.version')
		info "Previous version: ${PREVIOUS_VERSION}"

		# Compare versions
		if semver_greater_than "${CURRENT_VERSION}" "${PREVIOUS_VERSION}"; then
			success "Version check passed: ${CURRENT_VERSION} > ${PREVIOUS_VERSION}"
		else
			error "Chart version ${CURRENT_VERSION} is not strictly greater than ${PREVIOUS_VERSION}"
			exit 1
		fi
	else
		info "No previous version found in ${TARGET_BRANCH} (new chart or branch)"
		success "Version check skipped for new chart"
	fi
else
	info "Version check disabled via RUN_VERSION_CHECK=false"
fi

success "Layer 3 validation completed successfully"
