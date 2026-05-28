#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_SCRIPT="${SCRIPT_DIR}/detect-required-checks.sh"
SYNC_SCRIPT="${SCRIPT_DIR}/sync-chart-scaffold.sh"
BUILD_WORKFLOW_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

assert_contains() {
	local file="$1"
	local expected="$2"
	if ! grep -Fqx "${expected}" "${file}"; then
		echo "Expected output '${expected}' not found in ${file}" >&2
		cat "${file}" >&2
		exit 1
	fi
}

assert_not_contains() {
	local file="$1"
	local unexpected="$2"
	if grep -Fqx "${unexpected}" "${file}"; then
		echo "Unexpected output '${unexpected}' found in ${file}" >&2
		cat "${file}" >&2
		exit 1
	fi
}

assert_file_exists() {
	local file="$1"
	if [[ ! -f "${file}" ]]; then
		echo "Expected file '${file}' to exist" >&2
		exit 1
	fi
}

assert_file_missing() {
	local file="$1"
	if [[ -e "${file}" ]]; then
		echo "Expected file '${file}' to be absent" >&2
		exit 1
	fi
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
repo="${tmpdir}/repo"
mkdir -p "${repo}"

(
	cd "${repo}"
	git init -q
	git config user.name "ci"
	git config user.email "ci@example.com"
	git config commit.gpgsign false
	mkdir -p scripts .github/workflows templates
	cat >scripts/a.sh <<'EOF'
#!/usr/bin/env bash
echo a
EOF
	cat >values.yaml <<'EOF'
image:
  repository: nginx
  tag: "1.0.0"
EOF
	cat >renovate.json <<'EOF'
{}
EOF
	git add .
	git commit -q -m "base"
	base_sha="$(git rev-parse HEAD)"

	echo "echo changed" >>scripts/a.sh
	git add scripts/a.sh
	git commit -q -m "scripts change"
	head_sha="$(git rev-parse HEAD)"

	out="${tmpdir}/build-pr.out"
	: >"${out}"
	MODE=build EVENT_NAME=pull_request BASE_SHA="${base_sha}" HEAD_SHA="${head_sha}" GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_guardrails=true"
	assert_contains "${out}" "run_docker_smoke=false"
	assert_contains "${out}" "run_renovate_validation=false"
	assert_contains "${out}" "run_codeql=true"
	assert_contains "${out}" "run_dependency_review=true"

	out="${tmpdir}/build-merge-group.out"
	: >"${out}"
	MODE=build EVENT_NAME=merge_group GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_guardrails=true"
	assert_contains "${out}" "run_docker_smoke=true"
	assert_contains "${out}" "run_renovate_validation=true"
	assert_contains "${out}" "run_codeql=true"
	assert_contains "${out}" "run_dependency_review=true"

	cat >README.md <<'EOF'
# docs only
EOF
	git add README.md
	git commit -q -m "docs change"
	head_sha_docs="$(git rev-parse HEAD)"

	out="${tmpdir}/build-docs-pr.out"
	: >"${out}"
	MODE=build EVENT_NAME=pull_request BASE_SHA="${head_sha}" HEAD_SHA="${head_sha_docs}" GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_guardrails=false"
	assert_contains "${out}" "run_docker_smoke=false"
	assert_contains "${out}" "run_renovate_validation=false"
	assert_contains "${out}" "run_codeql=false"
	assert_contains "${out}" "run_dependency_review=false"

	mkdir -p templates/app-chart/.github/workflows
	echo "name: template contract" >templates/app-chart/.github/workflows/pr-required-checks.yaml
	git add templates/app-chart/.github/workflows/pr-required-checks.yaml
	git commit -q -m "template workflow change"
	head_sha_template="$(git rev-parse HEAD)"

	out="${tmpdir}/build-templates-pr.out"
	: >"${out}"
	MODE=build EVENT_NAME=pull_request BASE_SHA="${head_sha_docs}" HEAD_SHA="${head_sha_template}" GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_guardrails=true"
	assert_contains "${out}" "run_docker_smoke=false"
	assert_contains "${out}" "run_renovate_validation=false"
	assert_contains "${out}" "run_codeql=false"
	assert_contains "${out}" "run_dependency_review=false"

	mkdir -p configs
	echo "chart-dirs: []" >configs/ct-default.yaml
	git add configs/ct-default.yaml
	git commit -q -m "config change"
	head_sha_config="$(git rev-parse HEAD)"

	out="${tmpdir}/build-configs-pr.out"
	: >"${out}"
	MODE=build EVENT_NAME=pull_request BASE_SHA="${head_sha_template}" HEAD_SHA="${head_sha_config}" GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_guardrails=true"
	assert_contains "${out}" "run_docker_smoke=false"
	assert_contains "${out}" "run_renovate_validation=false"
	assert_contains "${out}" "run_codeql=false"
	assert_contains "${out}" "run_dependency_review=false"

	echo "# chart change" >Chart.yaml
	git add Chart.yaml
	git commit -q -m "chart change"
	head_sha_chart="$(git rev-parse HEAD)"

	out="${tmpdir}/chart-app-pr.out"
	: >"${out}"
	MODE=chart EVENT_NAME=pull_request BASE_SHA="${head_sha}" HEAD_SHA="${head_sha_chart}" CHART_KIND=app GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_validate=true"
	assert_contains "${out}" "run_renovate_validation=false"

	echo "{}" >.github/workflows/renovate-config.yaml
	git add .github/workflows/renovate-config.yaml
	git commit -q -m "renovate config workflow change"
	head_sha_renovate="$(git rev-parse HEAD)"

	out="${tmpdir}/chart-renovate-pr.out"
	: >"${out}"
	MODE=chart EVENT_NAME=pull_request BASE_SHA="${head_sha_chart}" HEAD_SHA="${head_sha_renovate}" CHART_KIND=app GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_validate=true"
	assert_contains "${out}" "run_renovate_validation=true"

	echo "{}" >.github/workflows/pr-required-checks.yaml
	git add .github/workflows/pr-required-checks.yaml
	git commit -q -m "required checks wrapper change"
	head_sha_chart_wrapper="$(git rev-parse HEAD)"

	out="${tmpdir}/chart-wrapper-pr.out"
	: >"${out}"
	MODE=chart EVENT_NAME=pull_request BASE_SHA="${head_sha_renovate}" HEAD_SHA="${head_sha_chart_wrapper}" CHART_KIND=app GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_validate=true"
	assert_contains "${out}" "run_renovate_validation=false"

	mkdir -p libChart
	echo "name: lib" >libChart/Chart.yaml
	git add libChart/Chart.yaml
	git commit -q -m "lib chart change"
	head_sha_lib="$(git rev-parse HEAD)"

	out="${tmpdir}/chart-lib-pr.out"
	: >"${out}"
	MODE=chart EVENT_NAME=pull_request BASE_SHA="${head_sha_chart_wrapper}" HEAD_SHA="${head_sha_lib}" CHART_KIND=lib GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_validate=true"
	assert_contains "${out}" "run_renovate_validation=false"

	out="${tmpdir}/chart-merge-group.out"
	: >"${out}"
	MODE=chart EVENT_NAME=merge_group CHART_KIND=app GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_validate=true"
	assert_contains "${out}" "run_renovate_validation=true"

	workspace="${tmpdir}/workspace"
	mkdir -p "${workspace}"
	ln -s "${BUILD_WORKFLOW_ROOT}" "${workspace}/build-workflow"

	for scaffold_repo in helm-common-lib jellyfin-helm home-assistant-helm seerr-helm radarr-helm sonarr-helm sabnzbd-helm transmission-helm; do
		mkdir -p "${workspace}/${scaffold_repo}"
	done

	mkdir -p "${workspace}/helm-common-lib/.github/workflows"

	for app_repo in jellyfin-helm home-assistant-helm seerr-helm radarr-helm sonarr-helm sabnzbd-helm transmission-helm; do
		mkdir -p "${workspace}/${app_repo}/.github/workflows" "${workspace}/${app_repo}/scripts"
	done

	scaffold_out="${tmpdir}/sync-chart-scaffold.out"
	"${SYNC_SCRIPT}" --apply --root "${workspace}" --ref "v-test" >"${scaffold_out}"

	for app_repo in jellyfin-helm home-assistant-helm seerr-helm radarr-helm sonarr-helm sabnzbd-helm transmission-helm; do
		assert_file_exists "${workspace}/${app_repo}/.github/workflows/renovate-snapshot-update.yaml"
	done

	assert_file_missing "${workspace}/helm-common-lib/.github/workflows/renovate-snapshot-update.yaml"

	wrapper_count="$(find "${workspace}" -path '*/.github/workflows/renovate-snapshot-update.yaml' | wc -l | tr -d ' ')"
	if [[ "${wrapper_count}" != "7" ]]; then
		echo "Expected exactly 7 app-chart snapshot wrappers, found ${wrapper_count}" >&2
		find "${workspace}" -path '*/.github/workflows/renovate-snapshot-update.yaml' -print >&2
		exit 1
	fi

	rendered_wrapper="${workspace}/jellyfin-helm/.github/workflows/renovate-snapshot-update.yaml"
	assert_contains "${rendered_wrapper}" "    types: [opened, synchronize, reopened]"
	assert_contains "${rendered_wrapper}" "    branches: [main]"
	assert_contains "${rendered_wrapper}" "      - \"Chart.yaml\""
	assert_contains "${rendered_wrapper}" "      - \"Chart.lock\""
	assert_contains "${rendered_wrapper}" "      - \"values.yaml\""
	assert_contains "${rendered_wrapper}" "      - \"templates/**\""
	assert_contains "${rendered_wrapper}" "      - \"charts/**\""
	assert_contains "${rendered_wrapper}" "      - \"tests/scenarios/**\""
	assert_not_contains "${rendered_wrapper}" "      - \"tests/snapshots/**\""
	assert_contains "${rendered_wrapper}" '    if: github.event.pull_request.head.repo.full_name == github.repository'
	assert_contains "${rendered_wrapper}" "    uses: orhayoun-eevee/build-workflow/.github/workflows/renovate-snapshot-update.yaml@v-test"
	assert_not_contains "${rendered_wrapper}" "    uses: orhayoun-eevee/build-workflow/.github/workflows/renovate-snapshot-update.yaml@__BUILD_WORKFLOW_REF__"
	assert_not_contains "${rendered_wrapper}" "__BUILD_WORKFLOW_REF__"
	assert_contains "${rendered_wrapper}" "  group: caller-renovate-snapshot-update-\${{ github.workflow }}-\${{ github.ref }}"
	assert_contains "${rendered_wrapper}" "      gh_app_client_id: \${{ secrets.GHCR_AUTO_CLIENT_ID }}"
	assert_not_contains "${rendered_wrapper}" "      gh_app_id: \${{ secrets.GHCR_AUTO_APP_ID }}"

	rendered_required_wrapper="${workspace}/jellyfin-helm/.github/workflows/pr-required-checks.yaml"
	assert_contains "${rendered_required_wrapper}" "      gh_app_client_id: \${{ secrets.GHCR_AUTO_CLIENT_ID }}"
	assert_not_contains "${rendered_required_wrapper}" "      gh_app_id: \${{ secrets.GHCR_AUTO_APP_ID }}"
	assert_not_contains "${rendered_required_wrapper}" "    paths-ignore:"

	rendered_lib_required_wrapper="${workspace}/helm-common-lib/.github/workflows/pr-required-checks.yaml"
	assert_contains "${rendered_lib_required_wrapper}" "      gh_app_client_id: \${{ secrets.GHCR_AUTO_CLIENT_ID }}"
	assert_not_contains "${rendered_lib_required_wrapper}" "      gh_app_id: \${{ secrets.GHCR_AUTO_APP_ID }}"
	assert_not_contains "${rendered_lib_required_wrapper}" "    paths-ignore:"
)

echo "detect-required-checks tests passed"
