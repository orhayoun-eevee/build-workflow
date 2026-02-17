#!/usr/bin/env bash
# Common utilities for the Helm validation framework scripts.
# Sourced by all validate-*.sh scripts.

# Colors for output (test stderr since all logging goes to >&2)
if [[ -t 2 ]]; then
	readonly COLOR_RED='\033[0;31m'
	readonly COLOR_GREEN='\033[0;32m'
	readonly COLOR_YELLOW='\033[1;33m'
	readonly COLOR_BLUE='\033[0;34m'
	readonly COLOR_RESET='\033[0m'
else
	readonly COLOR_RED=''
	readonly COLOR_GREEN=''
	readonly COLOR_YELLOW=''
	readonly COLOR_BLUE=''
	readonly COLOR_RESET=''
fi

# Logging functions
info() {
	echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*" >&2
}

success() {
	echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*" >&2
}

warn() {
	echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

error() {
	echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

# Check if a command exists
check_command() {
	local cmd="$1"
	if ! command -v "$cmd" &>/dev/null; then
		error "Required command not found: $cmd"
		return 1
	fi
	return 0
}

# Semver comparison - returns 0 if $1 > $2
semver_greater_than() {
	local version1="$1"
	local version2="$2"

	# Remove 'v' prefix if present
	version1="${version1#v}"
	version2="${version2#v}"

	# Use sort -V to compare versions
	local highest
	highest=$(printf '%s\n%s\n' "$version1" "$version2" | sort -V | tail -n1)

	if [[ "$highest" == "$version1" ]] && [[ "$version1" != "$version2" ]]; then
		return 0
	else
		return 1
	fi
}
