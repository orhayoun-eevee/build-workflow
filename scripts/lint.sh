#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Defaults
STRICT=false
RUN_CT=false
ADDITIONAL_CHARTS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --strict)
            STRICT=true
            shift
            ;;
        --ct)
            RUN_CT=true
            shift
            ;;
        --additional)
            ADDITIONAL_CHARTS="$2"
            shift 2
            ;;
        --help)
            cat <<EOF
Usage: lint.sh [OPTIONS] <chart_path>

Lint Helm charts using helm lint and optionally chart-testing.

Options:
  --strict              Enable strict mode (warnings as errors)
  --ct                  Also run chart-testing (ct lint)
  --additional PATHS    Additional charts to lint (comma-separated)
  --help                Show this help

Environment Variables:
  CT_CONFIG            Path to ct.yaml config (default: ./ct.yaml)
  DEBUG                Enable debug output (true/false)

Exit Codes:
  0   All checks passed
  1   Linting failed
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

# Validate required arguments
if [[ -z "${CHART_PATH:-}" ]]; then
    error "Chart path is required"
    exit 2
fi

# Check prerequisites
check_command helm || exit 1

if [[ "$RUN_CT" == "true" ]]; then
    check_command ct || exit 1
fi

# Lint main chart
info "Linting chart: $CHART_PATH"
LINT_CMD="helm lint $CHART_PATH"
[[ "$STRICT" == "true" ]] && LINT_CMD="$LINT_CMD --strict"

if ! $LINT_CMD; then
    error "Helm lint failed for $CHART_PATH"
    exit 1
fi
info "✓ Helm lint passed for $CHART_PATH"

# Lint additional charts
if [[ -n "$ADDITIONAL_CHARTS" ]]; then
    IFS=',' read -ra CHARTS <<< "$ADDITIONAL_CHARTS"
    for chart in "${CHARTS[@]}"; do
        info "Linting additional chart: $chart"
        LINT_CMD_EXTRA="helm lint $chart"
        [[ "$STRICT" == "true" ]] && LINT_CMD_EXTRA="$LINT_CMD_EXTRA --strict"
        if ! $LINT_CMD_EXTRA; then
            error "Helm lint failed for $chart"
            exit 1
        fi
        info "✓ Helm lint passed for $chart"
    done
fi

# Run chart-testing if requested
if [[ "$RUN_CT" == "true" ]]; then
    info "Running chart-testing (ct lint)..."
    CT_CONFIG="${CT_CONFIG:-./ct.yaml}"
    CT_CMD="ct lint --all"
    [[ -f "$CT_CONFIG" ]] && CT_CMD="$CT_CMD --config $CT_CONFIG"
    
    if ! $CT_CMD; then
        error "chart-testing (ct lint) failed"
        exit 1
    fi
    info "✓ chart-testing passed"
fi

info "All linting checks passed!"
