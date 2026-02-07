#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Defaults
MANIFEST_FILE=""
SKIP_CHECKS="CKV_K8S_40"
SOFT_FAIL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --manifest)
            MANIFEST_FILE="$2"
            shift 2
            ;;
        --skip-checks)
            SKIP_CHECKS="$2"
            shift 2
            ;;
        --soft-fail)
            SOFT_FAIL=true
            shift
            ;;
        --help)
            cat <<EOF
Usage: checkov.sh [OPTIONS] <chart_path>

Run Checkov security and policy checks.

Options:
  --manifest PATH       Check manifest file instead of chart directory
  --skip-checks IDS     Skip specific checks (comma-separated, default: CKV_K8S_40)
  --soft-fail           Don't fail on policy violations
  --help                Show this help

Exit Codes:
  0   Checks passed (or soft-fail mode)
  1   Checks failed
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

check_command checkov || {
    warn "checkov not installed - skipping security checks"
    warn "Install: pip install checkov"
    exit 0
}

if [[ -n "$MANIFEST_FILE" ]]; then
    TARGET="$MANIFEST_FILE"
    FRAMEWORK="kubernetes"
    TARGET_FLAG="--file"
else
    if [[ -z "${CHART_PATH:-}" ]]; then
        error "Chart path is required"
        exit 2
    fi
    TARGET="$CHART_PATH"
    FRAMEWORK="helm"
    TARGET_FLAG="--directory"
fi

info "Running Checkov security checks on: $TARGET"

CHECKOV_CMD="checkov $TARGET_FLAG $TARGET --framework $FRAMEWORK --output cli"
[[ -n "$SKIP_CHECKS" ]] && CHECKOV_CMD="$CHECKOV_CMD --skip-check $SKIP_CHECKS"
[[ "$SOFT_FAIL" == "true" ]] && CHECKOV_CMD="$CHECKOV_CMD --soft-fail"

if $CHECKOV_CMD; then
    info "✓ Checkov checks passed"
    exit 0
else
    if [[ "$SOFT_FAIL" == "true" ]]; then
        warn "Checkov found issues (soft-fail mode)"
        exit 0
    else
        error "Checkov checks failed"
        exit 1
    fi
fi
