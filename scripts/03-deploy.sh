#!/bin/bash
# ============================================================
# 03-deploy.sh - Deploy Besu and Paladin to Kubernetes
# ============================================================
# Phase 3: Deploy to k3s/Kubernetes cluster
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
source "$SCRIPT_DIR/lib/deploy-besu.sh"
source "$SCRIPT_DIR/lib/deploy-paladin.sh"
source "$SCRIPT_DIR/lib/verify.sh"

# Load configuration
source "$PROJECT_DIR/config/network.env"

# Export variables
export NETWORK_NAME NODE_COUNT CHAIN_ID
export NAMESPACE HEADLESS_SERVICE CLUSTER_DOMAIN
export P2P_PORT RPC_HTTP_PORT RPC_WS_PORT METRICS_PORT
export PALADIN_RPC_PORT

# ─────────────────────────────────────────────────────────────────────────────
# Options
# ─────────────────────────────────────────────────────────────────────────────
SKIP_BESU=false
SKIP_PALADIN=false
SKIP_VERIFY=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-besu       Skip Besu deployment (use existing)"
    echo "  --skip-paladin    Skip Paladin deployment"
    echo "  --skip-verify     Skip network verification"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                     Deploy everything"
    echo "  $0 --skip-besu         Only deploy Paladin (Besu already running)"
    echo "  $0 --skip-paladin      Only deploy Besu"
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
            --skip-verify)
                SKIP_VERIFY=true
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
            log_info "Ensure kubectl is configured and cluster is running"
            ((errors++))
        fi
    fi

    # Check helm (for Paladin)
    if [[ "$SKIP_PALADIN" != "true" ]]; then
        if ! command -v helm &> /dev/null; then
            log_error "helm not found (required for Paladin)"
            ((errors++))
        fi
    fi

    # Check jq (for verification)
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

    log_info "=== Phase 3: Deploy to Kubernetes ==="
    log_info "Network: $NETWORK_NAME (Chain ID: $CHAIN_ID)"
    log_info "Namespace: $NAMESPACE"

    # Check prerequisites
    check_prerequisites

    # Define directories
    local network_dir="$PROJECT_DIR/generated/$NETWORK_NAME"
    local k8s_dir="$network_dir/k8s"

    # Verify build output exists
    if [[ ! -d "$k8s_dir" ]]; then
        log_error "K8s manifests not found. Run 02-build.sh first."
        exit 1
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Phase 3.1 - Deploy Besu
    # ─────────────────────────────────────────────────────────────────────────
    if [[ "$SKIP_BESU" != "true" ]]; then
        deploy_besu "$k8s_dir"
        wait_for_besu_ready 300
    else
        log_info "Skipping Besu deployment (--skip-besu)"
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Phase 3.2 - Verify Besu network
    # ─────────────────────────────────────────────────────────────────────────
    if [[ "$SKIP_VERIFY" != "true" ]]; then
        log_info ""
        log_info "Waiting 30s for network stabilization..."
        sleep 30
        verify_besu_network || log_warn "Verification had warnings (may be OK for new network)"
    else
        log_info "Skipping verification (--skip-verify)"
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Phase 3.3 - Deploy Paladin
    # ─────────────────────────────────────────────────────────────────────────
    if [[ "$SKIP_PALADIN" != "true" ]]; then
        deploy_paladin "$k8s_dir"
        wait_for_paladin_ready 300 || log_warn "Paladin may still be starting up"
    else
        log_info "Skipping Paladin deployment (--skip-paladin)"
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Summary
    # ─────────────────────────────────────────────────────────────────────────
    log_success ""
    log_success "Deployment complete!"

    print_network_summary

    log_info ""
    log_info "Next steps:"
    log_info "  1. Port-forward to access RPC:"
    log_info "     kubectl port-forward -n $NAMESPACE svc/${NETWORK_NAME}-rpc ${RPC_HTTP_PORT}:${RPC_HTTP_PORT}"
    log_info ""
    log_info "  2. Test connectivity:"
    log_info "     curl -X POST http://localhost:${RPC_HTTP_PORT} \\"
    log_info "       -H 'Content-Type: application/json' \\"
    log_info "       -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[],\"id\":1}'"
}

main "$@"
