#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Defaults
VALUES_FILE=""
SKIP_RESOURCES="ServiceMonitor,PrometheusRule,HTTPRoute,AuthorizationPolicy,DestinationRule"
MANIFEST_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --values-file)
            VALUES_FILE="$2"
            shift 2
            ;;
        --skip)
            SKIP_RESOURCES="$2"
            shift 2
            ;;
        --manifest)
            MANIFEST_FILE="$2"
            shift 2
            ;;
        --help)
            cat <<EOF
Usage: kubeconform.sh [OPTIONS] <chart_path>

Validate Kubernetes manifests against schemas.

Options:
  --values-file PATH    Values file for templating
  --skip RESOURCES      Skip validation for these resources (comma-separated)
  --manifest PATH       Validate existing manifest file instead of generating
  --help                Show this help

Exit Codes:
  0   Validation passed
  1   Validation failed
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

check_command kubeconform || exit 1

# Generate or use existing manifest
if [[ -n "$MANIFEST_FILE" ]]; then
    TEMP_MANIFEST="$MANIFEST_FILE"
    CLEANUP=false
else
    if [[ -z "${CHART_PATH:-}" ]]; then
        error "Chart path is required"
        exit 2
    fi
    
    check_command helm || exit 1
    
    TEMP_MANIFEST=$(mktemp)
    CLEANUP=true
    trap "[[ \"$CLEANUP\" == \"true\" ]] && rm -f $TEMP_MANIFEST" EXIT
    
    info "Generating manifests from chart: $CHART_PATH"
    TEMPLATE_CMD="helm template test-release $CHART_PATH"
    [[ -n "$VALUES_FILE" ]] && TEMPLATE_CMD="$TEMPLATE_CMD -f $VALUES_FILE"
    
    if ! $TEMPLATE_CMD > "$TEMP_MANIFEST" 2>&1; then
        error "Failed to generate manifests"
        exit 2
    fi
fi

# Validate
info "Validating manifests with kubeconform..."
KUBECONFORM_CMD="kubeconform -strict -summary"
[[ -n "$SKIP_RESOURCES" ]] && KUBECONFORM_CMD="$KUBECONFORM_CMD -skip $SKIP_RESOURCES"
KUBECONFORM_CMD="$KUBECONFORM_CMD -schema-location default"
KUBECONFORM_CMD="$KUBECONFORM_CMD -schema-location https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

if ! $KUBECONFORM_CMD "$TEMP_MANIFEST"; then
    error "kubeconform validation failed"
    exit 1
fi

info "✓ All manifests passed kubeconform validation"
