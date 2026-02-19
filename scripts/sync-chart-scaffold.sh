#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_WORKFLOW_REF="${BUILD_WORKFLOW_REF:-}"
DRY_RUN=true

REPOS=(helm-common-lib radarr-helm sonarr-helm sabnzbd-helm transmission-helm)

usage() {
	cat <<USAGE
Usage:
  $0 [--apply] [--ref <build-workflow-ref>] [--repos <comma-separated>] [--root <workspace-root>]

Options:
  --apply                  Write files (default is dry-run)
  --ref <sha/tag/branch>   build-workflow ref to inject in workflows
  --repos <a,b,c>          Limit sync to selected app repos
  --root <path>            Workspace root containing repo directories
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

while [[ $# -gt 0 ]]; do
	case "$1" in
	--apply)
		DRY_RUN=false
		shift
		;;
	--ref)
		BUILD_WORKFLOW_REF="$2"
		shift 2
		;;
	--repos)
		IFS=',' read -r -a REPOS <<<"$2"
		shift 2
		;;
	--root)
		ROOT="$2"
		shift 2
		;;
	*)
		echo "Unknown argument: $1" >&2
		usage
		exit 2
		;;
	esac
done

if [[ -z "${BUILD_WORKFLOW_REF}" ]]; then
	echo "Error: build-workflow ref is required. Set BUILD_WORKFLOW_REF or pass --ref <sha/tag/branch>." >&2
	exit 2
fi

APP_TEMPLATE_ROOT="${ROOT}/build-workflow/templates/app-chart"
LIB_TEMPLATE_ROOT="${ROOT}/build-workflow/templates/helm-common-lib"

render_template() {
	local src="$1"
	local dest="$2"
	local chart_title="$3"
	local repo_name="$4"

	sed \
		-e "s/__BUILD_WORKFLOW_REF__/${BUILD_WORKFLOW_REF}/g" \
		-e "s/__CHART_TITLE__/${chart_title}/g" \
		-e "s/__REPO_NAME__/${repo_name}/g" \
		"${src}" >"${dest}.tmp"

	if cmp -s "${dest}.tmp" "${dest}" 2>/dev/null; then
		rm -f "${dest}.tmp"
		echo "unchanged ${dest}"
		return
	fi

	if [[ "${DRY_RUN}" == "true" ]]; then
		echo "would-update ${dest}"
		rm -f "${dest}.tmp"
	else
		mkdir -p "$(dirname "${dest}")"
		mv "${dest}.tmp" "${dest}"
		echo "updated ${dest}"
	fi
}

for repo in "${REPOS[@]}"; do
	repo="${repo// /}"
	[[ -z "${repo}" ]] && continue

	case "${repo}" in
	helm-common-lib)
		repo_root="${ROOT}/${repo}"
		if [[ ! -d "${repo_root}" ]]; then
			echo "skip missing repo ${repo_root}" >&2
			continue
		fi
		render_template "${LIB_TEMPLATE_ROOT}/.github/workflows/on-pr.yaml" "${repo_root}/.github/workflows/on-pr.yaml" "Helm Common Lib" "${repo}"
		render_template "${LIB_TEMPLATE_ROOT}/.github/workflows/on-tag.yaml" "${repo_root}/.github/workflows/on-tag.yaml" "Helm Common Lib" "${repo}"
		render_template "${LIB_TEMPLATE_ROOT}/.github/workflows/dependency-review.yaml" "${repo_root}/.github/workflows/dependency-review.yaml" "Helm Common Lib" "${repo}"
		render_template "${LIB_TEMPLATE_ROOT}/.github/workflows/renovate-config.yaml" "${repo_root}/.github/workflows/renovate-config.yaml" "Helm Common Lib" "${repo}"
		render_template "${LIB_TEMPLATE_ROOT}/.github/workflows/scaffold-drift-check.yaml" "${repo_root}/.github/workflows/scaffold-drift-check.yaml" "Helm Common Lib" "${repo}"
		continue
		;;
	radarr-helm) chart_title="Radarr" ;;
	sonarr-helm) chart_title="Sonarr" ;;
	sabnzbd-helm) chart_title="Sabnzbd" ;;
	transmission-helm) chart_title="Transmission" ;;
	*)
		echo "skip unknown repo ${repo}" >&2
		continue
		;;
	esac

	repo_root="${ROOT}/${repo}"
	if [[ ! -d "${repo_root}" ]]; then
		echo "skip missing repo ${repo_root}" >&2
		continue
	fi

	render_template "${APP_TEMPLATE_ROOT}/Makefile" "${repo_root}/Makefile" "${chart_title}" "${repo}"
	render_template "${APP_TEMPLATE_ROOT}/scripts/bump-version.sh" "${repo_root}/scripts/bump-version.sh" "${chart_title}" "${repo}"
	render_template "${APP_TEMPLATE_ROOT}/.github/workflows/on-pr.yaml" "${repo_root}/.github/workflows/on-pr.yaml" "${chart_title}" "${repo}"
	render_template "${APP_TEMPLATE_ROOT}/.github/workflows/on-tag.yaml" "${repo_root}/.github/workflows/on-tag.yaml" "${chart_title}" "${repo}"
	render_template "${APP_TEMPLATE_ROOT}/.github/workflows/dependency-review.yaml" "${repo_root}/.github/workflows/dependency-review.yaml" "${chart_title}" "${repo}"
	render_template "${APP_TEMPLATE_ROOT}/.github/workflows/renovate-config.yaml" "${repo_root}/.github/workflows/renovate-config.yaml" "${chart_title}" "${repo}"
	render_template "${APP_TEMPLATE_ROOT}/.github/workflows/renovate-snapshot-update.yaml" "${repo_root}/.github/workflows/renovate-snapshot-update.yaml" "${chart_title}" "${repo}"
	render_template "${APP_TEMPLATE_ROOT}/.github/workflows/scaffold-drift-check.yaml" "${repo_root}/.github/workflows/scaffold-drift-check.yaml" "${chart_title}" "${repo}"
done
