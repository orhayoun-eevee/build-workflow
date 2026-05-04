#!/usr/bin/env bash
# Install pinned Helm, kubectl, and kind binaries for install-smoke runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

: "${HELM_VERSION:?HELM_VERSION is required}"
: "${KUBECTL_VERSION:?KUBECTL_VERSION is required}"
: "${KIND_VERSION:?KIND_VERSION is required}"

TOOLS_BIN_DIR="${RUNNER_TEMP:-/tmp}/install-smoke-bin"
WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/install-smoke-tools-XXXXXX")"

cleanup() {
	rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${TOOLS_BIN_DIR}"

if [[ -n "${GITHUB_PATH:-}" ]]; then
	echo "${TOOLS_BIN_DIR}" >>"${GITHUB_PATH}"
fi
export PATH="${TOOLS_BIN_DIR}:${PATH}"

download_file() {
	local url="$1"
	local output="$2"
	curl -fsSL "${url}" -o "${output}"
}

install_helm() {
	local archive="helm-v${HELM_VERSION}-linux-amd64.tar.gz"
	local checksum_file="${archive}.sha256sum"

	info "Installing Helm v${HELM_VERSION}"
	download_file "https://get.helm.sh/${archive}" "${WORK_DIR}/${archive}"
	download_file "https://get.helm.sh/${checksum_file}" "${WORK_DIR}/${checksum_file}"
	(
		cd "${WORK_DIR}"
		grep " ${archive}\$" "${checksum_file}" | sha256sum -c -
		tar -xzf "${archive}"
		install -m 0755 "linux-amd64/helm" "${TOOLS_BIN_DIR}/helm"
	)
	helm version --short
}

install_kubectl() {
	local version="v${KUBECTL_VERSION}"

	info "Installing kubectl ${version}"
	download_file "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl" "${WORK_DIR}/kubectl"
	download_file "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl.sha256" "${WORK_DIR}/kubectl.sha256"
	(
		cd "${WORK_DIR}"
		echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
		install -m 0755 kubectl "${TOOLS_BIN_DIR}/kubectl"
	)
	kubectl version --client=true
}

install_kind() {
	local version="v${KIND_VERSION}"

	info "Installing kind ${version}"
	download_file "https://kind.sigs.k8s.io/dl/${version}/kind-linux-amd64" "${WORK_DIR}/kind"
	install -m 0755 "${WORK_DIR}/kind" "${TOOLS_BIN_DIR}/kind"
	kind version
}

install_helm
install_kubectl
install_kind

success "Install-smoke toolchain is ready"
