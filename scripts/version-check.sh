#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Defaults
BASE_REF="${BASE_REF:-main}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --base-ref)
            BASE_REF="$2"
            shift 2
            ;;
        --help)
            cat <<EOF
Usage: version-check.sh [OPTIONS] <chart_path>

Verify Chart.yaml version was bumped when templates/values changed.

Options:
  --base-ref REF        Base branch to compare (default: main)
  --help                Show this help

Environment Variables:
  GITHUB_BASE_REF       Auto-detected in GitHub Actions PR context
  BASE_REF              Alternative to --base-ref flag

Exit Codes:
  0   Version check passed or not applicable
  1   Version not bumped when required
  2   Invalid arguments
EOF
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            exit 2
            ;;
        *)
            CHART_PATH="$1"
            shift
            ;;
    esac
done

if [[ -z "${CHART_PATH:-}" ]]; then
    error "Chart path is required"
    exit 2
fi

check_command git || exit 1
check_command yq || { error "yq is required (install: https://github.com/mikefarah/yq)"; exit 1; }

# Auto-detect base ref from GitHub Actions
if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    BASE_REF="$GITHUB_BASE_REF"
fi

info "Checking version bump against base: $BASE_REF"

# Get current version
CHART_YAML="$CHART_PATH/Chart.yaml"
if [[ ! -f "$CHART_YAML" ]]; then
    error "Chart.yaml not found: $CHART_YAML"
    exit 2
fi

CURRENT_VERSION=$(yq eval '.version' "$CHART_YAML")
info "Current version: $CURRENT_VERSION"

# Check if we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    warn "Not in a git repository - skipping version check"
    exit 0
fi

# Fetch base branch
git fetch origin "$BASE_REF" 2>/dev/null || {
    warn "Could not fetch $BASE_REF - skipping version check"
    exit 0
}

# Check if templates or values changed
TEMPLATES_CHANGED=$(git diff --name-only "origin/$BASE_REF...HEAD" -- "$CHART_PATH/templates/" "$CHART_PATH/values"*.yaml 2>/dev/null | grep -E "(templates/|values.*\.yaml)" || true)
CHART_YAML_CHANGED=$(git diff --name-only "origin/$BASE_REF...HEAD" -- "$CHART_YAML" 2>/dev/null || true)

if [[ -n "$TEMPLATES_CHANGED" ]] && [[ -z "$CHART_YAML_CHANGED" ]]; then
    error "Templates/values changed but Chart.yaml not modified"
    echo ""
    echo "Changed files:"
    echo "$TEMPLATES_CHANGED"
    echo ""
    error "Please bump version in $CHART_YAML"
    exit 1
fi

if [[ -n "$CHART_YAML_CHANGED" ]]; then
    # Check if version actually changed
    BASE_VERSION=$(git show "origin/$BASE_REF:$CHART_YAML" 2>/dev/null | yq eval '.version' - || echo "")
    if [[ -z "$BASE_VERSION" ]]; then
        warn "Could not determine base version - skipping comparison"
        exit 0
    fi
    
    if [[ "$CURRENT_VERSION" == "$BASE_VERSION" ]]; then
        error "Chart.yaml modified but version unchanged"
        echo "Current: $CURRENT_VERSION"
        echo "Base: $BASE_VERSION"
        exit 1
    fi
    
    info "✓ Version bumped: $BASE_VERSION → $CURRENT_VERSION"
else
    info "✓ No template/values changes - version check skipped"
fi
