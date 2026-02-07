#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Defaults
UPDATE_MODE=false
GOLDEN_FILE=""
VALUES_FILE=""
RELEASE_NAME="test-release"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --update)
            UPDATE_MODE=true
            shift
            ;;
        --golden-file)
            GOLDEN_FILE="$2"
            shift 2
            ;;
        --values-file)
            VALUES_FILE="$2"
            shift 2
            ;;
        --release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --help)
            cat <<EOF
Usage: golden.sh [OPTIONS] <chart_path>

Generate Helm template and compare against golden snapshot.

Options:
  --update              Update golden file instead of comparing
  --golden-file PATH    Path to golden file (default: auto-detect)
  --values-file PATH    Path to values file for templating (default: auto-detect)
  --release-name NAME   Helm release name (default: test-release)
  --help                Show this help

Exit Codes:
  0   Golden snapshot matches (or updated successfully)
  1   Drift detected
  2   Invalid arguments or missing files
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

# Validate
if [[ -z "${CHART_PATH:-}" ]]; then
    error "Chart path is required"
    exit 2
fi

check_command helm || exit 1
check_command diff || exit 1

# Auto-detect golden file
if [[ -z "$GOLDEN_FILE" ]]; then
    if [[ -f "tests/golden.yaml" ]]; then
        GOLDEN_FILE="tests/golden.yaml"
    elif [[ -f "gold/gold_file.yaml" ]]; then
        GOLDEN_FILE="gold/gold_file.yaml"
    else
        GOLDEN_FILE="tests/golden.yaml"  # default
    fi
fi

# Auto-detect values file
if [[ -z "$VALUES_FILE" ]]; then
    if [[ -f "tests/values.test.yaml" ]]; then
        VALUES_FILE="tests/values.test.yaml"
    elif [[ -f "$CHART_PATH/values.yaml" ]]; then
        VALUES_FILE="$CHART_PATH/values.yaml"
    fi
fi

# Create temp file
TEMP_MANIFEST=$(mktemp)
trap "rm -f $TEMP_MANIFEST" EXIT

# Generate manifests
info "Generating manifests from chart: $CHART_PATH"
TEMPLATE_CMD="helm template $RELEASE_NAME $CHART_PATH"
[[ -n "$VALUES_FILE" ]] && TEMPLATE_CMD="$TEMPLATE_CMD -f $VALUES_FILE"

if ! $TEMPLATE_CMD > "$TEMP_MANIFEST" 2>&1; then
    error "Failed to generate manifests"
    cat "$TEMP_MANIFEST"
    exit 2
fi

# Check if golden file exists
if [[ ! -f "$GOLDEN_FILE" ]]; then
    if [[ "$UPDATE_MODE" == "true" ]]; then
        info "Golden file not found. Creating: $GOLDEN_FILE"
        mkdir -p "$(dirname "$GOLDEN_FILE")"
        cp "$TEMP_MANIFEST" "$GOLDEN_FILE"
        info "✓ Golden snapshot created"
        exit 0
    else
        error "Golden file not found: $GOLDEN_FILE"
        error "Run with --update to create it"
        exit 2
    fi
fi

# Compare
if diff -u "$GOLDEN_FILE" "$TEMP_MANIFEST" > /dev/null 2>&1; then
    info "✓ No drift detected - manifests match golden snapshot"
    exit 0
else
    if [[ "$UPDATE_MODE" == "true" ]]; then
        warn "Drift detected. Updating golden snapshot..."
        cp "$TEMP_MANIFEST" "$GOLDEN_FILE"
        info "✓ Golden snapshot updated: $GOLDEN_FILE"
        warn "Review changes and commit: git diff $GOLDEN_FILE"
        exit 0
    else
        error "Drift detected! Manifests differ from golden snapshot"
        echo ""
        echo "Diff (golden vs current):"
        diff -u "$GOLDEN_FILE" "$TEMP_MANIFEST" || true
        echo ""
        error "To update: $0 --update $CHART_PATH"
        exit 1
    fi
fi
