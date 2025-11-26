#!/bin/bash
# ============================================================
# 05-clean.sh - Clean up Besu and Paladin deployment
# ============================================================
# Phase 5: Remove all deployed resources and generated files
# ============================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load libraries
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Load configuration
source "$PROJECT_DIR/config/network.env"

# Export variables
export NETWORK_NAME NODE_COUNT NAMESPACE

# ─────────────────────────────────────────────────────────────────────────────
# Options
# ─────────────────────────────────────────────────────────────────────────────
KEEP_GENERATED=false
FORCE=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --keep-generated  Keep generated/ directory (only clean K8s resources)"
    echo "  --force           Skip confirmation prompt"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                     Clean everything (with confirmation)"
    echo "  $0 --force             Clean everything without confirmation"
    echo "  $0 --keep-generated    Only clean K8s resources, keep generated files"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep-generated)
                KEEP_GENERATED=true
                shift
                ;;
            --force|-f)
                FORCE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# clean_kubernetes()
# Remove all K8s resources in the namespace
# ─────────────────────────────────────────────────────────────────────────────
clean_kubernetes() {
    log_info "Cleaning Kubernetes resources..."

    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_info "Namespace '$NAMESPACE' does not exist, skipping K8s cleanup"
        return 0
    fi

    # Delete namespace (cascades to all resources)
    log_info "Deleting namespace: $NAMESPACE"
    kubectl delete namespace "$NAMESPACE" --wait=false 2>/dev/null || true

    # Wait for namespace to be fully deleted
    log_info "Waiting for namespace deletion..."
    local timeout=120
    local elapsed=0
    while kubectl get namespace "$NAMESPACE" &>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            log_warn "Namespace deletion timed out after ${timeout}s"
            log_info "You may need to manually delete: kubectl delete namespace $NAMESPACE --force"
            return 1
        fi
        sleep 2
        ((elapsed+=2))
        printf "."
    done
    echo ""

    log_success "Kubernetes resources cleaned"
}

# ─────────────────────────────────────────────────────────────────────────────
# clean_pvcs()
# Clean up any orphaned PVCs (in case namespace deletion didn't catch them)
# ─────────────────────────────────────────────────────────────────────────────
clean_pvcs() {
    log_info "Checking for orphaned PVCs..."

    # Look for PVs that were bound to our namespace
    local orphaned_pvs
    orphaned_pvs=$(kubectl get pv -o json 2>/dev/null | \
        jq -r ".items[] | select(.spec.claimRef.namespace == \"$NAMESPACE\") | .metadata.name" 2>/dev/null || echo "")

    if [[ -n "$orphaned_pvs" ]]; then
        log_info "Cleaning orphaned PVs:"
        echo "$orphaned_pvs" | while read -r pv; do
            log_info "  Deleting PV: $pv"
            kubectl delete pv "$pv" --wait=false 2>/dev/null || true
        done
    else
        log_info "No orphaned PVs found"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# clean_generated()
# Remove generated files
# ─────────────────────────────────────────────────────────────────────────────
clean_generated() {
    local generated_dir="$PROJECT_DIR/generated"

    if [[ -d "$generated_dir" ]]; then
        log_info "Removing generated files: $generated_dir"
        rm -rf "$generated_dir"
        log_success "Generated files removed"
    else
        log_info "No generated files to clean"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    log_info "=== Phase 5: Clean Deployment ==="
    log_info "Network: $NETWORK_NAME"
    log_info "Namespace: $NAMESPACE"
    log_info ""

    # Confirmation prompt
    if [[ "$FORCE" != "true" ]]; then
        log_warn "This will delete:"
        log_warn "  - Kubernetes namespace: $NAMESPACE (all pods, services, secrets)"
        if [[ "$KEEP_GENERATED" != "true" ]]; then
            log_warn "  - Generated directory: $PROJECT_DIR/generated/"
        fi
        log_warn ""
        read -p "Are you sure? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled"
            exit 0
        fi
    fi

    log_info ""

    # Clean Kubernetes resources
    clean_kubernetes

    # Clean orphaned PVCs
    clean_pvcs

    # Clean generated files
    if [[ "$KEEP_GENERATED" != "true" ]]; then
        clean_generated
    else
        log_info "Keeping generated files (--keep-generated)"
    fi

    log_info ""
    log_success "════════════════════════════════════════════════════════"
    log_success "  Cleanup complete!"
    log_success "════════════════════════════════════════════════════════"
    log_info ""
    log_info "To redeploy, run:"
    log_info "  make all"
    log_info ""
}

main "$@"
