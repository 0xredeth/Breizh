#!/bin/bash
# ============================================================
# network-ctl.sh - Start/Stop network without destroying it
# ============================================================
# Usage: ./scripts/network-ctl.sh [--start|--stop|start|stop]
# ============================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load libraries
source "$SCRIPT_DIR/lib/logging.sh"

# Load configuration
source "$PROJECT_DIR/config/network.env"

# State file to store original replica counts
STATE_FILE="$PROJECT_DIR/.network-state"

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  --start, start    Start the network (scale up pods)"
    echo "  --stop, stop      Stop the network (scale down pods)"
    echo "  --status, status  Check network status"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --stop         Stop network to free resources"
    echo "  $0 --start        Start network again"
    echo "  make network-stop"
    echo "  make network-start"
}

check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist."
        log_info "Deploy the network first with: make all"
        exit 1
    fi
}

stop_network() {
    log_info "Stopping network: $NETWORK_NAME"
    check_namespace

    # Stop dashboard if running
    if [[ -f "$PROJECT_DIR/.dashboard.pid" ]]; then
        log_info "Stopping dashboard port-forward..."
        "$SCRIPT_DIR/dashboard.sh" stop 2>/dev/null || true
    fi

    # Save current state
    log_info "Saving current state..."
    {
        echo "# Network state saved at $(date)"
        echo "BESU_REPLICAS=$(kubectl get sts "$NETWORK_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")"

        # Get Paladin replica count (from Paladin CR)
        local paladin_nodes
        paladin_nodes=$(kubectl get paladins -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        echo "PALADIN_NODES=$paladin_nodes"
    } > "$STATE_FILE"

    # Scale down Besu StatefulSet
    log_info "Scaling down Besu nodes..."
    kubectl scale sts "$NETWORK_NAME" -n "$NAMESPACE" --replicas=0

    # Scale down Paladin pods by patching PaladinNode CRs
    log_info "Scaling down Paladin nodes..."
    for node in $(kubectl get paladins -n "$NAMESPACE" -o name 2>/dev/null); do
        # Delete the Paladin node pods (they're managed by operator)
        local node_name
        node_name=$(basename "$node")
        kubectl scale deployment "${node_name}" -n "$NAMESPACE" --replicas=0 2>/dev/null || true
    done

    # Wait for pods to terminate
    log_info "Waiting for pods to terminate..."
    kubectl wait --for=delete pod -l app="$NETWORK_NAME" -n "$NAMESPACE" --timeout=60s 2>/dev/null || true

    log_success "Network stopped"
    log_info ""
    log_info "Resources are preserved. Restart with:"
    log_info "  make network-start"
}

start_network() {
    log_info "Starting network: $NETWORK_NAME"
    check_namespace

    # Determine replica counts
    local besu_replicas="$NODE_COUNT"
    local paladin_nodes="${PALADIN_NODE_COUNT:-$NODE_COUNT}"

    # Load saved state if exists
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        besu_replicas="${BESU_REPLICAS:-$NODE_COUNT}"
        paladin_nodes="${PALADIN_NODES:-$PALADIN_NODE_COUNT}"
    fi

    # Scale up Besu StatefulSet
    log_info "Scaling up Besu nodes to $besu_replicas..."
    kubectl scale sts "$NETWORK_NAME" -n "$NAMESPACE" --replicas="$besu_replicas"

    # Scale up Paladin deployments
    log_info "Scaling up Paladin nodes..."
    for node in $(kubectl get paladins -n "$NAMESPACE" -o name 2>/dev/null); do
        local node_name
        node_name=$(basename "$node")
        kubectl scale deployment "${node_name}" -n "$NAMESPACE" --replicas=1 2>/dev/null || true
    done

    # Wait for Besu pods to be ready
    log_info "Waiting for Besu pods to be ready..."
    kubectl wait --for=condition=ready pod -l app="$NETWORK_NAME" -n "$NAMESPACE" --timeout=300s

    # Wait for Paladin pods
    log_info "Waiting for Paladin pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=paladin -n "$NAMESPACE" --timeout=300s 2>/dev/null || true

    log_success "Network started"
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "  NETWORK STATUS"
    log_info "═══════════════════════════════════════════════════════════════"
    log_info ""
    kubectl get pods -n "$NAMESPACE" --no-headers | head -10
    log_info ""
    log_info "  Start dashboard: make dashboard-start"
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════"
}

status_network() {
    log_info "Network status: $NETWORK_NAME"

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_warn "Namespace '$NAMESPACE' does not exist"
        log_info "Network is not deployed"
        return 1
    fi

    log_info ""
    log_info "Namespace: $NAMESPACE"
    log_info ""

    # Besu status
    local besu_ready
    besu_ready=$(kubectl get sts "$NETWORK_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local besu_desired
    besu_desired=$(kubectl get sts "$NETWORK_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

    if [[ "$besu_desired" -eq 0 ]]; then
        log_warn "Besu: STOPPED (0 replicas)"
    elif [[ "$besu_ready" -eq "$besu_desired" ]]; then
        log_success "Besu: RUNNING ($besu_ready/$besu_desired pods ready)"
    else
        log_warn "Besu: STARTING ($besu_ready/$besu_desired pods ready)"
    fi

    # Paladin status
    local paladin_pods
    paladin_pods=$(kubectl get pods -n "$NAMESPACE" -l app=paladin --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null) || paladin_pods=0
    local paladin_total
    paladin_total=$(kubectl get paladins -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$paladin_total" -eq 0 ]]; then
        log_info "Paladin: NOT DEPLOYED"
    elif [[ "$paladin_pods" -eq 0 ]]; then
        log_warn "Paladin: STOPPED (0 pods running)"
    else
        log_success "Paladin: RUNNING ($paladin_pods/$paladin_total pods)"
    fi

    log_info ""

    # Show pods
    log_info "Pods:"
    kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null || log_info "  No pods found"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    local cmd="${1:-}"

    case "$cmd" in
        --start|start)
            start_network
            ;;
        --stop|stop)
            stop_network
            ;;
        --status|status)
            status_network
            ;;
        -h|--help|"")
            usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
