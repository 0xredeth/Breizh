#!/bin/bash
# ============================================================
# dashboard.sh - Manage Paladin UI port-forward
# ============================================================
# Usage: ./scripts/dashboard.sh [--start|--stop|start|stop]
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

# PID file location
PID_FILE="$PROJECT_DIR/.dashboard.pid"

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  --start, start    Start port-forward to Paladin UI"
    echo "  --stop, stop      Stop port-forward"
    echo "  --status, status  Check if dashboard is running"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --start        Start dashboard port-forward"
    echo "  $0 --stop         Stop dashboard port-forward"
    echo "  make dashboard-start"
    echo "  make dashboard-stop"
}

start_dashboard() {
    log_info "Starting Paladin Dashboard..."

    # Check if already running via PID file
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log_warn "Dashboard already running (PID: $old_pid)"
            log_info "Access UI at: http://localhost:${PALADIN_RPC_PORT}/ui"
            return 0
        else
            # Stale PID file
            rm -f "$PID_FILE"
        fi
    fi

    # Check if port is already in use (existing port-forward without PID file)
    if lsof -i ":${PALADIN_RPC_PORT}" &>/dev/null; then
        log_warn "Port ${PALADIN_RPC_PORT} already in use"
        log_info "Access UI at: http://localhost:${PALADIN_RPC_PORT}/ui"
        log_info "To stop: make dashboard-stop"
        return 0
    fi

    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist. Deploy the network first."
        exit 1
    fi

    # Check if Paladin service exists
    if ! kubectl get svc paladin-node-0 -n "$NAMESPACE" &>/dev/null; then
        log_error "Paladin service not found. Is Paladin deployed?"
        exit 1
    fi

    # Start port-forward in background
    kubectl port-forward -n "$NAMESPACE" svc/paladin-node-0 "${PALADIN_RPC_PORT}:${PALADIN_RPC_PORT}" &>/dev/null &
    local pf_pid=$!

    # Save PID
    echo "$pf_pid" > "$PID_FILE"

    # Wait a moment and verify
    sleep 2
    if kill -0 "$pf_pid" 2>/dev/null; then
        log_success "Dashboard started (PID: $pf_pid)"
        log_info ""
        log_info "═══════════════════════════════════════════════════════════════"
        log_info "  PALADIN DASHBOARD"
        log_info "═══════════════════════════════════════════════════════════════"
        log_info ""
        log_info "  UI:      http://localhost:${PALADIN_RPC_PORT}/ui"
        log_info "  RPC:     http://localhost:${PALADIN_RPC_PORT}"
        log_info ""
        log_info "  Stop with: make dashboard-stop"
        log_info ""
        log_info "═══════════════════════════════════════════════════════════════"
    else
        rm -f "$PID_FILE"
        log_error "Failed to start port-forward"
        exit 1
    fi
}

stop_dashboard() {
    log_info "Stopping Paladin Dashboard..."

    local stopped=false

    # Try to stop via PID file first
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            log_success "Dashboard stopped (PID: $pid)"
            stopped=true
        fi
        rm -f "$PID_FILE"
    fi

    # Also kill any process listening on the port (in case PID file was missing)
    local port_pid
    port_pid=$(lsof -ti ":${PALADIN_RPC_PORT}" 2>/dev/null || true)
    if [[ -n "$port_pid" ]]; then
        kill "$port_pid" 2>/dev/null || true
        stopped=true
        log_success "Killed process on port ${PALADIN_RPC_PORT}"
    fi

    if [[ "$stopped" != "true" ]]; then
        log_info "Dashboard was not running"
    fi
}

status_dashboard() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_success "Dashboard is running (PID: $pid)"
            log_info "  UI: http://localhost:${PALADIN_RPC_PORT}/ui"
            return 0
        fi
    fi

    log_info "Dashboard is not running"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    local cmd="${1:-}"

    case "$cmd" in
        --start|start)
            start_dashboard
            ;;
        --stop|stop)
            stop_dashboard
            ;;
        --status|status)
            status_dashboard
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
