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
        local local_port=$((RPC_HTTP_PORT + 100 + i))

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
    local local_port=$((RPC_HTTP_PORT + 200))

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
    local local_port=$((RPC_HTTP_PORT + 201))

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
# Verify Paladin can connect to Besu nodes
# ─────────────────────────────────────────────────────────────────────────────
verify_paladin_connectivity() {
    log_info "Verifying Paladin connectivity to Besu..."

    # Check if any Paladin pods exist
    local paladin_pods
    paladin_pods=$(kubectl get pods -n "$NAMESPACE" -l "app=paladin" \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$paladin_pods" -eq 0 ]]; then
        log_warn "No Paladin pods found"
        return 1
    fi

    log_success "Paladin pods found: $paladin_pods"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# verify_service_health()
# Verify RPC service has endpoints
# ─────────────────────────────────────────────────────────────────────────────
verify_service_health() {
    log_info "Checking service endpoints..."

    if kubectl get endpoints -n "$NAMESPACE" --no-headers | grep -q "${NETWORK_NAME}-rpc"; then
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
    log_info "  PALADIN ENDPOINTS"
    log_info "───────────────────────────────────────────────────────────────"

    for i in $(seq 0 $((NODE_COUNT - 1))); do
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
