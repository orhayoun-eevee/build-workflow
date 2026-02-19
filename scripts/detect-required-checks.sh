#!/usr/bin/env bash
set -euo pipefail

: "${MODE:?MODE is required (build|chart)}"

event_name="${EVENT_NAME:-${GITHUB_EVENT_NAME:-}}"
base_sha="${BASE_SHA:-}"
head_sha="${HEAD_SHA:-}"

chart_kind="${CHART_KIND:-app}"
enable_codeql="${ENABLE_CODEQL:-true}"

force_all=false
if [[ "${event_name}" != "pull_request" ]]; then
	force_all=true
elif [[ -z "${base_sha}" || -z "${head_sha}" ]]; then
	force_all=true
elif ! git cat-file -e "${base_sha}^{commit}" 2>/dev/null || ! git cat-file -e "${head_sha}^{commit}" 2>/dev/null; then
	force_all=true
fi

if [[ "${force_all}" == "true" ]]; then
	if [[ "${MODE}" == "build" ]]; then
		{
			echo "run_guardrails=true"
			echo "run_docker_smoke=true"
			echo "run_renovate_validation=true"
			echo "run_codeql=true"
		} >>"${GITHUB_OUTPUT}"
		exit 0
	fi

	if [[ "${MODE}" == "chart" ]]; then
		{
			echo "run_validate=true"
			echo "run_renovate_validation=true"
			if [[ "${enable_codeql}" == "true" ]]; then
				echo "run_codeql=true"
			else
				echo "run_codeql=false"
			fi
		} >>"${GITHUB_OUTPUT}"
		exit 0
	fi

	echo "Unsupported MODE: ${MODE}" >&2
	exit 2
fi

changed_files="$(git diff --name-only "${base_sha}" "${head_sha}")"

if [[ "${MODE}" == "build" ]]; then
	run_guardrails=false
	run_docker_smoke=false
	run_renovate_validation=false
	run_codeql=false

	if grep -Eq '^(scripts/|\.github/workflows/|docker/Dockerfile)' <<<"${changed_files}"; then
		run_guardrails=true
	fi

	if grep -Eq '^(docker/|\.github/workflows/docker-build\.yaml|\.github/workflows/helm-validate\.yaml)' <<<"${changed_files}"; then
		run_docker_smoke=true
	fi

	if grep -Eq '^(renovate\.json|renovate\.json5|\.github/renovate\.json|\.github/renovate\.json5|\.github/workflows/renovate-config\.yaml)' <<<"${changed_files}"; then
		run_renovate_validation=true
	fi

	if grep -Eq '^(scripts/|\.github/workflows/)' <<<"${changed_files}"; then
		run_codeql=true
	fi

	{
		echo "run_guardrails=${run_guardrails}"
		echo "run_docker_smoke=${run_docker_smoke}"
		echo "run_renovate_validation=${run_renovate_validation}"
		echo "run_codeql=${run_codeql}"
	} >>"${GITHUB_OUTPUT}"
	exit 0
fi

if [[ "${MODE}" == "chart" ]]; then
	run_validate=false
	run_renovate_validation=false
	run_codeql=false

	if [[ "${chart_kind}" == "lib" ]]; then
		if grep -Eq '^(libChart/|test-chart/|tests/|scripts/|Makefile|ct\.yaml|\.checkov\.yaml|\.kube-linter\.yaml)' <<<"${changed_files}"; then
			run_validate=true
		fi

		if [[ "${enable_codeql}" == "true" ]] && grep -Eq '^(\.github/workflows/|scripts/)' <<<"${changed_files}"; then
			run_codeql=true
		fi
	else
		if grep -Eq '^(Chart\.yaml|Chart\.lock|values\.yaml|templates/|tests/|charts/|scripts/|Makefile|ct\.yaml|\.checkov\.yaml|\.kube-linter\.yaml)' <<<"${changed_files}"; then
			run_validate=true
		fi

		if [[ "${enable_codeql}" == "true" ]] && grep -Eq '^(\.github/workflows/|scripts/)' <<<"${changed_files}"; then
			run_codeql=true
		fi
	fi

	if grep -Eq '^(renovate\.json|renovate\.json5|\.github/renovate\.json|\.github/renovate\.json5|\.github/workflows/renovate-config\.yaml)' <<<"${changed_files}"; then
		run_renovate_validation=true
	fi

	{
		echo "run_validate=${run_validate}"
		echo "run_renovate_validation=${run_renovate_validation}"
		echo "run_codeql=${run_codeql}"
	} >>"${GITHUB_OUTPUT}"
	exit 0
fi

echo "Unsupported MODE: ${MODE}" >&2
exit 2
