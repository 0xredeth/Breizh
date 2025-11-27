#!/bin/bash
# ============================================================
# 04-verify.sh - Verify Besu and Paladin deployment
# ============================================================
# Phase 4: Comprehensive network verification
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
source "$SCRIPT_DIR/lib/verify.sh"

# Load configuration
source "$PROJECT_DIR/config/network.env"

# Export variables
export NETWORK_NAME NODE_COUNT CHAIN_ID
export NAMESPACE HEADLESS_SERVICE CLUSTER_DOMAIN
export P2P_PORT RPC_HTTP_PORT RPC_WS_PORT METRICS_PORT
export PALADIN_RPC_PORT PALADIN_NODE_COUNT

# ─────────────────────────────────────────────────────────────────────────────
# Options
# ─────────────────────────────────────────────────────────────────────────────
SKIP_BESU=false
SKIP_PALADIN=false
VERBOSE=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-besu       Skip Besu verification"
    echo "  --skip-paladin    Skip Paladin verification"
    echo "  -v, --verbose     Show detailed output"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                     Verify everything"
    echo "  $0 --skip-paladin      Only verify Besu"
    echo "  $0 -v                  Verbose verification"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-besu)
                SKIP_BESU=true
                shift
                ;;
            --skip-paladin)
                SKIP_PALADIN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
# Prerequisites check
# ─────────────────────────────────────────────────────────────────────────────
check_prerequisites() {
    log_info "Checking prerequisites..."

    local errors=0

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        ((errors++))
    else
        # Check cluster connectivity
        if ! kubectl cluster-info &> /dev/null; then
            log_error "Cannot connect to Kubernetes cluster"
            ((errors++))
        fi
    fi

    # Check jq (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_error "jq not found"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Prerequisites check failed"
        exit 1
    fi

    log_success "Prerequisites OK"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    log_info "=== Phase 4: Verify Deployment ==="
    log_info "Network: $NETWORK_NAME (Chain ID: $CHAIN_ID)"
    log_info "Namespace: $NAMESPACE"

    # Check prerequisites
    check_prerequisites

    local errors=0

    # ─────────────────────────────────────────────────────────────────────────
    # Phase 4.1 - Verify Besu
    # ─────────────────────────────────────────────────────────────────────────
    if [[ "$SKIP_BESU" != "true" ]]; then
        log_info ""
        log_info "─── Besu Network Verification ───"

        if ! verify_besu_network; then
            ((errors++))
        fi

        if ! verify_service_health; then
            ((errors++))
        fi
    else
        log_info "Skipping Besu verification (--skip-besu)"
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Phase 4.2 - Verify Paladin
    # ─────────────────────────────────────────────────────────────────────────
    if [[ "$SKIP_PALADIN" != "true" ]]; then
        log_info ""
        log_info "─── Paladin Verification ───"

        if ! verify_paladin_connectivity; then
            ((errors++))
        fi
    else
        log_info "Skipping Paladin verification (--skip-paladin)"
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Summary
    # ─────────────────────────────────────────────────────────────────────────
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════"

    if [[ $errors -eq 0 ]]; then
        log_success "All verifications passed!"
        print_network_summary
        exit 0
    else
        log_error "Verification completed with $errors error(s)"
        log_info ""
        log_info "Troubleshooting commands:"
        log_info "  kubectl get pods -n $NAMESPACE"
        log_info "  kubectl describe pods -n $NAMESPACE"
        log_info "  kubectl logs -n $NAMESPACE ${NETWORK_NAME}-0"
        exit 1
    fi
}

main "$@"
