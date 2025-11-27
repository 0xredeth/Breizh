#!/bin/bash
# ============================================================
# Verification functions (Phase 3.2)
# ============================================================

# ─────────────────────────────────────────────────────────────────────────────
# 3.2 verify_besu_network()
# Comprehensive verification of Besu network health
# ─────────────────────────────────────────────────────────────────────────────
verify_besu_network() {
    local errors=0

    log_info "Verifying Besu network..."

    # Check peer connectivity
    if ! _verify_peer_count; then
        ((errors++))
    fi

    # Check validators
    if ! _verify_validators; then
        ((errors++))
    fi

    # Check block production
    if ! _verify_block_production; then
        ((errors++))
    fi

    # Summary
    if [[ $errors -eq 0 ]]; then
        log_success "Besu network verification passed"
        return 0
    else
        log_error "Besu network verification failed with $errors error(s)"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# _verify_peer_count()
# Verify each node has expected number of peers
# ─────────────────────────────────────────────────────────────────────────────
_verify_peer_count() {
    log_info "Checking peer connectivity..."

    local expected_peers=$((NODE_COUNT - 1))
    local all_connected=true

    for i in $(seq 0 $((NODE_COUNT - 1))); do
        local pod="${NETWORK_NAME}-${i}"
        local peer_count
        # Use high port range (18000+) to avoid conflicts with Paladin ports
        local local_port=$((18000 + i))

        # Start port-forward in background
        kubectl port-forward -n "$NAMESPACE" "pod/$pod" "${local_port}:${RPC_HTTP_PORT}" &>/dev/null &
        local pf_pid=$!
        sleep 1

        # Query peer count via JSON-RPC from local machine
        peer_count=$(curl -s -X POST \
            --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
            -H "Content-Type: application/json" \
            "http://localhost:${local_port}" 2>/dev/null | \
            jq -r '.result' 2>/dev/null | \
            xargs printf "%d" 2>/dev/null || echo "0")

        # Kill port-forward
        kill $pf_pid 2>/dev/null || true
        wait $pf_pid 2>/dev/null || true

        if [[ "$peer_count" -ge "$expected_peers" ]]; then
            log_info "  $pod: $peer_count peers (OK)"
        else
            log_warn "  $pod: $peer_count peers (expected: $expected_peers)"
            all_connected=false
        fi
    done

    if [[ "$all_connected" == "true" ]]; then
        log_success "All nodes connected to peers"
        return 0
    else
        log_warn "Some nodes have fewer peers than expected"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# _verify_validators()
# Verify QBFT validators are properly configured
# ─────────────────────────────────────────────────────────────────────────────
_verify_validators() {
    log_info "Checking QBFT validators..."

    local pod="${NETWORK_NAME}-0"
    # Use high port range for local port-forward (avoid conflicts)
    local local_port=18100

    # Start port-forward in background
    kubectl port-forward -n "$NAMESPACE" "pod/$pod" "${local_port}:${RPC_HTTP_PORT}" &>/dev/null &
    local pf_pid=$!
    sleep 1

    # Query validators via QBFT RPC from local machine
    local validators
    validators=$(curl -s -X POST \
        --data '{"jsonrpc":"2.0","method":"qbft_getValidatorsByBlockNumber","params":["latest"],"id":1}' \
        -H "Content-Type: application/json" \
        "http://localhost:${local_port}" 2>/dev/null | \
        jq -r '.result | length' 2>/dev/null || echo "0")

    # Kill port-forward
    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$validators" -eq "$NODE_COUNT" ]]; then
        log_success "QBFT validators: $validators (expected: $NODE_COUNT)"
        return 0
    else
        log_error "QBFT validator count mismatch: $validators (expected: $NODE_COUNT)"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# _verify_block_production()
# Verify blocks are being produced
# ─────────────────────────────────────────────────────────────────────────────
_verify_block_production() {
    log_info "Checking block production..."

    local pod="${NETWORK_NAME}-0"
    # Use high port range for local port-forward (avoid conflicts)
    local local_port=18101

    # Start port-forward in background
    kubectl port-forward -n "$NAMESPACE" "pod/$pod" "${local_port}:${RPC_HTTP_PORT}" &>/dev/null &
    local pf_pid=$!
    sleep 1

    # Get current block number from local machine
    local block_number
    block_number=$(curl -s -X POST \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        -H "Content-Type: application/json" \
        "http://localhost:${local_port}" 2>/dev/null | \
        jq -r '.result' 2>/dev/null | \
        xargs printf "%d" 2>/dev/null || echo "0")

    # Kill port-forward
    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$block_number" -gt 0 ]]; then
        log_success "Block production active (current block: $block_number)"
        return 0
    else
        log_warn "No blocks produced yet (block: $block_number)"
        log_info "This may be normal if network just started"
        return 0  # Don't fail on this, network might be brand new
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# verify_paladin_connectivity()
# Comprehensive Paladin verification
# ─────────────────────────────────────────────────────────────────────────────
verify_paladin_connectivity() {
    local errors=0

    log_info "Verifying Paladin deployment..."

    # Check Paladin pods status
    if ! _verify_paladin_pods; then
        ((errors++))
    fi

    # Check Paladin CRDs
    if ! _verify_paladin_crds; then
        ((errors++))
    fi

    # Check Paladin registries
    if ! _verify_paladin_registries; then
        ((errors++))
    fi

    # Check Paladin domains
    if ! _verify_paladin_domains; then
        ((errors++))
    fi

    # Test Paladin JSON-RPC connectivity
    if ! _verify_paladin_rpc; then
        ((errors++))
    fi

    # Check Paladin logs for Besu connection
    if ! _verify_paladin_besu_connection; then
        ((errors++))
    fi

    # Summary
    if [[ $errors -eq 0 ]]; then
        log_success "Paladin verification passed"
        return 0
    else
        log_error "Paladin verification failed with $errors error(s)"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# _verify_paladin_pods()
# Verify Paladin pods are running with all containers ready
# ─────────────────────────────────────────────────────────────────────────────
_verify_paladin_pods() {
    log_info "Checking Paladin pods..."

    local all_ready=true

    # Use PALADIN_NODE_COUNT (supports light mode with single node)
    for i in $(seq 0 $((PALADIN_NODE_COUNT - 1))); do
        local pod_name="paladin-node-${i}-0"
        local pod_status
        local ready_containers

        # Get pod status
        pod_status=$(kubectl get pod "$pod_name" -n "$NAMESPACE" \
            -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

        if [[ "$pod_status" == "Running" ]]; then
            # Check container readiness (expect 2/2: paladin + postgres)
            ready_containers=$(kubectl get pod "$pod_name" -n "$NAMESPACE" \
                -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null | \
                grep -o "true" | wc -l | tr -d ' ')

            if [[ "$ready_containers" -ge 2 ]]; then
                log_info "  $pod_name: Running ($ready_containers/2 containers ready)"
            else
                log_warn "  $pod_name: Running but only $ready_containers/2 containers ready"
                all_ready=false
            fi
        else
            log_warn "  $pod_name: $pod_status"
            all_ready=false
        fi
    done

    if [[ "$all_ready" == "true" ]]; then
        log_success "All Paladin pods running with containers ready"
        return 0
    else
        log_warn "Some Paladin pods not fully ready"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# _verify_paladin_crds()
# Verify Paladin CRD resources exist
# ─────────────────────────────────────────────────────────────────────────────
_verify_paladin_crds() {
    log_info "Checking Paladin CRD resources..."

    # Check Paladin CR instances
    local paladin_count
    paladin_count=$(kubectl get paladin -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$paladin_count" -ge "$PALADIN_NODE_COUNT" ]]; then
        log_success "Paladin CRs found: $paladin_count"
        return 0
    else
        log_warn "Paladin CRs: $paladin_count (expected: $PALADIN_NODE_COUNT)"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# _verify_paladin_registries()
# Verify Paladin registries are available
# ─────────────────────────────────────────────────────────────────────────────
_verify_paladin_registries() {
    log_info "Checking Paladin registries..."

    local registry_count
    registry_count=$(kubectl get registry -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$registry_count" -gt 0 ]]; then
        # Check status of registries
        local available
        # grep -c returns 1 when no matches, but outputs 0 - use subshell to capture output regardless
        available=$(kubectl get registry -n "$NAMESPACE" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | \
            { grep -c "Available" 2>/dev/null || true; })

        if [[ "$available" -gt 0 ]]; then
            log_success "Paladin registries available: $available"
            return 0
        else
            log_warn "Registries found ($registry_count) but none Available yet"
            return 1
        fi
    else
        log_warn "No Paladin registries found"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# _verify_paladin_domains()
# Verify Paladin domains are deployed
# ─────────────────────────────────────────────────────────────────────────────
_verify_paladin_domains() {
    log_info "Checking Paladin domains..."

    local domain_count
    domain_count=$(kubectl get paladindomains -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$domain_count" -gt 0 ]]; then
        log_success "Paladin domains found: $domain_count"
        kubectl get paladindomains -n "$NAMESPACE" --no-headers 2>/dev/null | while read -r line; do
            local name status
            name=$(echo "$line" | awk '{print $1}')
            log_info "  - $name"
        done
        return 0
    else
        log_warn "No Paladin domains found (may be normal during startup)"
        return 0  # Don't fail, domains may take time to appear
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# _verify_paladin_rpc()
# Test Paladin JSON-RPC connectivity
# ─────────────────────────────────────────────────────────────────────────────
_verify_paladin_rpc() {
    log_info "Testing Paladin RPC connectivity..."

    local pod_name="paladin-node-0-0"
    # Use high port range (19000+) to avoid conflicts with Besu test ports
    # Offset from PALADIN_RPC_PORT to maintain relationship with config
    local local_port=$((PALADIN_RPC_PORT + 10452))

    # Check if pod exists first
    if ! kubectl get pod "$pod_name" -n "$NAMESPACE" &>/dev/null; then
        log_warn "Paladin pod $pod_name not found, skipping RPC test"
        return 1
    fi

    # Start port-forward in background
    kubectl port-forward -n "$NAMESPACE" "pod/$pod_name" "${local_port}:${PALADIN_RPC_PORT}" &>/dev/null &
    local pf_pid=$!
    sleep 2

    # Test Paladin RPC with a simple method probe
    # Note: Paladin has its own API and doesn't proxy Ethereum methods
    # We just verify we get any valid JSON-RPC response as proof it's running
    local response
    response=$(curl -s -X POST \
        --data '{"jsonrpc":"2.0","method":"ptx_getTransportNames","params":[],"id":1}' \
        -H "Content-Type: application/json" \
        "http://localhost:${local_port}" 2>/dev/null || echo "")

    # Kill port-forward
    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    # Check for valid JSON-RPC response (either result or error proves Paladin is responding)
    if [[ -n "$response" ]] && echo "$response" | jq -e '.jsonrpc' &>/dev/null; then
        if echo "$response" | jq -e '.result' &>/dev/null; then
            log_success "Paladin RPC responding (transports available)"
        else
            log_success "Paladin RPC responding (API active)"
        fi
        return 0
    else
        log_warn "Paladin RPC not responding yet"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# _verify_paladin_besu_connection()
# Check Paladin logs for successful Besu connection
# ─────────────────────────────────────────────────────────────────────────────
_verify_paladin_besu_connection() {
    log_info "Checking Paladin-Besu connection status..."

    local pod_name="paladin-node-0-0"

    # Check if pod exists
    if ! kubectl get pod "$pod_name" -n "$NAMESPACE" &>/dev/null; then
        log_warn "Paladin pod $pod_name not found"
        return 1
    fi

    # Check logs for connection errors or success indicators
    local recent_logs
    recent_logs=$(kubectl logs "$pod_name" -n "$NAMESPACE" -c paladin --tail=50 2>/dev/null || echo "")

    if [[ -z "$recent_logs" ]]; then
        log_warn "Could not retrieve Paladin logs"
        return 1
    fi

    # Check for critical errors
    if echo "$recent_logs" | grep -qi "connection refused\|connection error\|failed to connect"; then
        log_error "Paladin has Besu connection errors"
        log_info "  Run: kubectl logs $pod_name -n $NAMESPACE -c paladin | tail -20"
        return 1
    fi

    # Check for successful blockchain connection
    if echo "$recent_logs" | grep -qi "blockchain\|connected\|synced\|block"; then
        log_success "Paladin appears connected to Besu"
        return 0
    fi

    log_info "  No obvious connection errors in recent logs"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# verify_service_health()
# Verify RPC service has endpoints
# ─────────────────────────────────────────────────────────────────────────────
verify_service_health() {
    log_info "Checking service endpoints..."

    if kubectl get endpoints -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q "${NETWORK_NAME}-rpc"; then
        log_success "RPC service has endpoints"
        return 0
    else
        log_error "RPC service has no endpoints"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# print_network_summary()
# Print a summary of the deployed network
# ─────────────────────────────────────────────────────────────────────────────
print_network_summary() {
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "                    NETWORK SUMMARY"
    log_info "═══════════════════════════════════════════════════════════════"
    log_info ""
    log_info "Network: $NETWORK_NAME"
    log_info "Chain ID: $CHAIN_ID"
    log_info "Namespace: $NAMESPACE"
    log_info "Node count: $NODE_COUNT"
    log_info ""
    log_info "───────────────────────────────────────────────────────────────"
    log_info "  BESU ENDPOINTS"
    log_info "───────────────────────────────────────────────────────────────"

    for i in $(seq 0 $((NODE_COUNT - 1))); do
        local host="${NETWORK_NAME}-${i}.${HEADLESS_SERVICE}.${NAMESPACE}.${CLUSTER_DOMAIN}"
        log_info "  node-$i:"
        log_info "    JSON-RPC: http://${host}:${RPC_HTTP_PORT}"
        log_info "    WebSocket: ws://${host}:${RPC_WS_PORT}"
    done

    log_info ""
    log_info "  RPC Service (load balanced):"
    log_info "    JSON-RPC: http://${NETWORK_NAME}-rpc.${NAMESPACE}.${CLUSTER_DOMAIN}:${RPC_HTTP_PORT}"
    log_info ""
    log_info "───────────────────────────────────────────────────────────────"
    log_info "  PALADIN ENDPOINTS ($PALADIN_NODE_COUNT nodes)"
    log_info "───────────────────────────────────────────────────────────────"

    for i in $(seq 0 $((PALADIN_NODE_COUNT - 1))); do
        log_info "  node-$i:"
        log_info "    RPC HTTP: port ${PALADIN_RPC_PORT}"
        log_info "    RPC WS:   port $((PALADIN_RPC_PORT + 1))"
    done

    log_info ""
    log_info "───────────────────────────────────────────────────────────────"
    log_info "  USEFUL COMMANDS"
    log_info "───────────────────────────────────────────────────────────────"
    log_info "  kubectl get pods -n $NAMESPACE"
    log_info "  kubectl logs -n $NAMESPACE ${NETWORK_NAME}-0"
    log_info "  kubectl port-forward -n $NAMESPACE svc/${NETWORK_NAME}-rpc ${RPC_HTTP_PORT}:${RPC_HTTP_PORT}"
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════"
}
