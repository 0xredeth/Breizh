#!/bin/bash
# ============================================================
# Deploy Besu functions (Phase 3.1)
# ============================================================

# ─────────────────────────────────────────────────────────────────────────────
# 3.1 deploy_besu()
# Apply all Kubernetes manifests for Besu network
# ─────────────────────────────────────────────────────────────────────────────
deploy_besu() {
    local k8s_dir="$1"
    local timeout="${2:-300s}"

    log_info "Deploying Besu network to Kubernetes..."

    # Apply manifests in dependency order
    log_info "Applying namespace..."
    kubectl apply -f "$k8s_dir/namespace.yaml"

    log_info "Applying ConfigMap..."
    kubectl apply -f "$k8s_dir/configmap-besu.yaml"

    log_info "Applying Secret..."
    kubectl apply -f "$k8s_dir/secret-keys.yaml"

    log_info "Applying headless service..."
    kubectl apply -f "$k8s_dir/service-headless.yaml"

    log_info "Applying RPC service..."
    kubectl apply -f "$k8s_dir/service-rpc.yaml"

    log_info "Applying StatefulSet..."
    kubectl apply -f "$k8s_dir/statefulset-besu.yaml"

    log_success "Kubernetes manifests applied"

    # Wait for StatefulSet rollout
    log_info "Waiting for StatefulSet rollout (timeout: $timeout)..."
    if kubectl rollout status statefulset/"$NETWORK_NAME" -n "$NAMESPACE" --timeout="$timeout"; then
        log_success "Besu StatefulSet rolled out successfully"
    else
        log_error "StatefulSet rollout failed or timed out"
        log_info "Check pods: kubectl get pods -n $NAMESPACE"
        log_info "Check logs: kubectl logs -n $NAMESPACE ${NETWORK_NAME}-0"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# wait_for_besu_ready()
# Wait for all Besu pods to be ready
# ─────────────────────────────────────────────────────────────────────────────
wait_for_besu_ready() {
    local timeout="${1:-300}"
    local interval=10
    local elapsed=0

    log_info "Waiting for $NODE_COUNT Besu pods to be ready..."

    while [[ $elapsed -lt $timeout ]]; do
        local ready_count
        ready_count=$(kubectl get pods -n "$NAMESPACE" -l app="$NETWORK_NAME" \
            -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | \
            tr ' ' '\n' | grep -c "True" || echo "0")

        if [[ "$ready_count" -eq "$NODE_COUNT" ]]; then
            log_success "All $NODE_COUNT Besu pods are ready"
            return 0
        fi

        log_info "  Ready: $ready_count/$NODE_COUNT (${elapsed}s elapsed)"
        sleep $interval
        ((elapsed += interval))
    done

    log_error "Timeout waiting for Besu pods"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# get_besu_pod_status()
# Display status of all Besu pods
# ─────────────────────────────────────────────────────────────────────────────
get_besu_pod_status() {
    log_info "Besu pod status:"
    kubectl get pods -n "$NAMESPACE" -l app="$NETWORK_NAME" -o wide
}
