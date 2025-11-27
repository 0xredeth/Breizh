#!/bin/bash
# ============================================================
# dashboard.sh - Manage Paladin UI port-forwards for all nodes
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

# PID file directory for all node port-forwards
PID_DIR="$PROJECT_DIR/.dashboard-pids"

# Port mapping: node-X uses port BASE_PORT + (X * 10)
# Node 0: 8548, Node 1: 8558, Node 2: 8568, Node 3: 8578
BASE_PORT=${PALADIN_RPC_PORT:-8548}
PORT_INCREMENT=10

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  --start, start    Start port-forwards to all Paladin nodes"
    echo "  --stop, stop      Stop all port-forwards"
    echo "  --status, status  Check if dashboards are running"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Port mapping (dynamic based on PALADIN_NODE_COUNT=$PALADIN_NODE_COUNT):"
    for i in $(seq 0 $((PALADIN_NODE_COUNT - 1))); do
        echo "  Node $i: localhost:$(get_local_port $i)"
    done
    echo ""
    echo "Examples:"
    echo "  $0 --start        Start all dashboard port-forwards"
    echo "  $0 --stop         Stop all dashboard port-forwards"
    echo "  make dashboard-start"
    echo "  make dashboard-stop"
}

# Get local port for a node index
get_local_port() {
    local node_idx=$1
    echo $((BASE_PORT + node_idx * PORT_INCREMENT))
}

start_dashboard() {
    log_info "Starting Paladin Dashboard for $PALADIN_NODE_COUNT nodes..."

    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist. Deploy the network first."
        exit 1
    fi

    # Create PID directory if it doesn't exist
    mkdir -p "$PID_DIR"

    # Check if already running
    local running_count=0
    for i in $(seq 0 $((PALADIN_NODE_COUNT - 1))); do
        local pid_file="$PID_DIR/node-$i.pid"
        if [[ -f "$pid_file" ]]; then
            local old_pid
            old_pid=$(cat "$pid_file")
            if kill -0 "$old_pid" 2>/dev/null; then
                running_count=$((running_count + 1))
            else
                rm -f "$pid_file"
            fi
        fi
    done

    if [[ $running_count -eq $PALADIN_NODE_COUNT ]]; then
        log_warn "All $PALADIN_NODE_COUNT dashboards already running"
        status_dashboard
        return 0
    elif [[ $running_count -gt 0 ]]; then
        log_warn "Some dashboards running ($running_count/$PALADIN_NODE_COUNT). Stopping and restarting..."
        stop_dashboard
    fi

    local started=0
    local failed=0

    for i in $(seq 0 $((PALADIN_NODE_COUNT - 1))); do
        local service_name="paladin-node-$i"
        local local_port=$(get_local_port $i)
        local pid_file="$PID_DIR/node-$i.pid"

        # Check if service exists
        if ! kubectl get svc "$service_name" -n "$NAMESPACE" &>/dev/null; then
            log_warn "Service $service_name not found, skipping"
            failed=$((failed + 1))
            continue
        fi

        # Check if port is already in use
        if lsof -i ":${local_port}" &>/dev/null; then
            log_warn "Port $local_port already in use, skipping node-$i"
            failed=$((failed + 1))
            continue
        fi

        # Start port-forward in background
        kubectl port-forward -n "$NAMESPACE" "svc/$service_name" "${local_port}:${PALADIN_RPC_PORT}" &>/dev/null &
        local pf_pid=$!

        # Save PID
        echo "$pf_pid" > "$pid_file"

        # Brief wait and verify
        sleep 1
        if kill -0 "$pf_pid" 2>/dev/null; then
            log_info "  Node $i: localhost:$local_port (PID: $pf_pid)"
            started=$((started + 1))
        else
            rm -f "$pid_file"
            log_warn "  Node $i: failed to start"
            failed=$((failed + 1))
        fi
    done

    echo ""
    if [[ $started -gt 0 ]]; then
        log_success "Started $started/$PALADIN_NODE_COUNT dashboard port-forwards"
        log_info ""
        log_info "═══════════════════════════════════════════════════════════════"
        log_info "  PALADIN DASHBOARDS"
        log_info "═══════════════════════════════════════════════════════════════"
        log_info ""
        for i in $(seq 0 $((PALADIN_NODE_COUNT - 1))); do
            local local_port=$(get_local_port $i)
            local pid_file="$PID_DIR/node-$i.pid"
            if [[ -f "$pid_file" ]]; then
                log_info "  Node $i:  http://localhost:$local_port/ui"
            fi
        done
        log_info ""
        log_info "  Stop with: make dashboard-stop"
        log_info ""
        log_info "═══════════════════════════════════════════════════════════════"
    else
        log_error "Failed to start any dashboard port-forwards"
        exit 1
    fi
}

stop_dashboard() {
    log_info "Stopping Paladin Dashboards..."

    local stopped=0

    # Stop via PID files in directory
    if [[ -d "$PID_DIR" ]]; then
        for pid_file in "$PID_DIR"/*.pid; do
            [[ -f "$pid_file" ]] || continue
            local node_name
            node_name=$(basename "$pid_file" .pid)
            local pid
            pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                log_info "  Stopped $node_name (PID: $pid)"
                stopped=$((stopped + 1))
            fi
            rm -f "$pid_file"
        done
        # Clean up empty directory
        rmdir "$PID_DIR" 2>/dev/null || true
    fi

    # Also handle legacy single PID file (.dashboard.pid)
    local legacy_pid_file="$PROJECT_DIR/.dashboard.pid"
    if [[ -f "$legacy_pid_file" ]]; then
        local pid
        pid=$(cat "$legacy_pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            log_info "  Stopped legacy dashboard (PID: $pid)"
            stopped=$((stopped + 1))
        fi
        rm -f "$legacy_pid_file"
    fi

    # Kill any kubectl port-forward processes for paladin services
    # This catches orphaned processes where PID file was missing
    for i in $(seq 0 $((PALADIN_NODE_COUNT - 1))); do
        local local_port=$(get_local_port $i)
        local port_pid
        port_pid=$(lsof -ti ":${local_port}" 2>/dev/null || true)
        if [[ -n "$port_pid" ]]; then
            kill "$port_pid" 2>/dev/null || true
            log_info "  Killed orphan process on port $local_port"
            stopped=$((stopped + 1))
        fi
    done

    if [[ $stopped -gt 0 ]]; then
        log_success "Stopped $stopped dashboard port-forward(s)"
    else
        log_info "No dashboards were running"
    fi
}

status_dashboard() {
    local running=0
    local total=$PALADIN_NODE_COUNT

    log_info "Dashboard status:"
    log_info ""

    for i in $(seq 0 $((PALADIN_NODE_COUNT - 1))); do
        local local_port=$(get_local_port $i)
        local pid_file="$PID_DIR/node-$i.pid"
        local status="stopped"
        local pid=""

        if [[ -f "$pid_file" ]]; then
            pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                status="running"
                running=$((running + 1))
            fi
        fi

        # Also check if port is in use (orphaned process)
        if [[ "$status" == "stopped" ]] && lsof -i ":${local_port}" &>/dev/null; then
            status="running (orphan)"
            running=$((running + 1))
        fi

        if [[ "$status" == "running" ]]; then
            log_success "  Node $i: http://localhost:$local_port/ui (PID: $pid)"
        elif [[ "$status" == "running (orphan)" ]]; then
            log_warn "  Node $i: http://localhost:$local_port/ui (orphan process)"
        else
            log_info "  Node $i: stopped"
        fi
    done

    log_info ""
    if [[ $running -eq $total ]]; then
        log_success "All $total dashboards running"
        return 0
    elif [[ $running -gt 0 ]]; then
        log_warn "$running/$total dashboards running"
        return 0
    else
        log_info "No dashboards running"
        return 1
    fi
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
