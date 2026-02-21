#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_SCRIPT="${SCRIPT_DIR}/detect-required-checks.sh"

assert_contains() {
	local file="$1"
	local expected="$2"
	if ! grep -qx "${expected}" "${file}"; then
		echo "Expected output '${expected}' not found in ${file}" >&2
		cat "${file}" >&2
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

	out="${tmpdir}/build-merge-group.out"
	: >"${out}"
	MODE=build EVENT_NAME=merge_group GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_guardrails=true"
	assert_contains "${out}" "run_docker_smoke=true"
	assert_contains "${out}" "run_renovate_validation=true"
	assert_contains "${out}" "run_codeql=true"

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
	assert_contains "${out}" "run_validate=false"
	assert_contains "${out}" "run_renovate_validation=true"

	mkdir -p libChart
	echo "name: lib" >libChart/Chart.yaml
	git add libChart/Chart.yaml
	git commit -q -m "lib chart change"
	head_sha_lib="$(git rev-parse HEAD)"

	out="${tmpdir}/chart-lib-pr.out"
	: >"${out}"
	MODE=chart EVENT_NAME=pull_request BASE_SHA="${head_sha_renovate}" HEAD_SHA="${head_sha_lib}" CHART_KIND=lib GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_validate=true"
	assert_contains "${out}" "run_renovate_validation=false"

	out="${tmpdir}/chart-merge-group.out"
	: >"${out}"
	MODE=chart EVENT_NAME=merge_group CHART_KIND=app GITHUB_OUTPUT="${out}" "${DETECT_SCRIPT}"
	assert_contains "${out}" "run_validate=true"
	assert_contains "${out}" "run_renovate_validation=true"
)

echo "detect-required-checks tests passed"
