#!/bin/bash
# ============================================================
# Deploy Paladin functions (Phase 3.3)
# ============================================================

# Paladin Helm repository
readonly PALADIN_HELM_REPO="https://LF-Decentralized-Trust-labs.github.io/paladin"
readonly PALADIN_HELM_REPO_NAME="paladin"

setup_paladin_helm_repo() {
    log_info "Setting up Paladin Helm repository..."

    helm repo add "$PALADIN_HELM_REPO_NAME" "$PALADIN_HELM_REPO" --force-update
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update

    log_success "Paladin Helm repository ready"
}

deploy_paladin() {
    local k8s_dir="$1"
    local release_name="${2:-paladin}"
    local values_file="$k8s_dir/paladin-values.yaml"

    if [[ ! -f "$values_file" ]]; then
        log_error "Paladin values file not found: $values_file"
        return 1
    fi

    log_info "Deploying Paladin operator..."
    setup_paladin_helm_repo

    # Step 1: Install CRDs
    log_info "Installing CRDs..."
    helm upgrade --install paladin-crds "$PALADIN_HELM_REPO_NAME/paladin-operator-crd" \
        --namespace "$NAMESPACE" --create-namespace

    # Step 2: Install cert-manager
    log_info "Installing cert-manager..."
    helm install cert-manager --namespace cert-manager --version v1.16.1 \
        jetstack/cert-manager --create-namespace --set crds.enabled=true --wait

    # Step 3: Install/Upgrade Paladin operator
    if helm list -n "$NAMESPACE" | grep -q "^${release_name}"; then
        log_info "Upgrading existing release..."
        helm upgrade "$release_name" "$PALADIN_HELM_REPO_NAME/paladin-operator" \
            -n "$NAMESPACE" -f "$values_file"
    else
        log_info "Installing Paladin operator..."
        helm install "$release_name" "$PALADIN_HELM_REPO_NAME/paladin-operator" \
            -n "$NAMESPACE" --create-namespace -f "$values_file"
    fi

    log_success "Paladin operator deployed"
}

wait_for_paladin_ready() {
    local timeout="${1:-300}"
    local interval=10
    local elapsed=0

    log_info "Waiting for Paladin pods to be ready..."

    while [[ $elapsed -lt $timeout ]]; do
        # Check for Paladin statefulsets (more reliable than pod labels)
        local paladin_pods
        paladin_pods=$(kubectl get pods -n "$NAMESPACE" -l "app=paladin" \
            --no-headers 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$paladin_pods" -gt 0 ]]; then
            local ready_count
            ready_count=$(kubectl get pods -n "$NAMESPACE" -l "app=paladin" \
                -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | \
                tr ' ' '\n' | grep -c "True" || echo "0")

            if [[ "$ready_count" -eq "$paladin_pods" ]] && [[ "$ready_count" -gt 0 ]]; then
                log_success "All $ready_count Paladin pods are ready"
                return 0
            fi

            log_info "  Paladin pods ready: $ready_count/$paladin_pods (${elapsed}s elapsed)"
        else
            log_info "  Waiting for Paladin pods to be created... (${elapsed}s elapsed)"
        fi

        sleep $interval
        ((elapsed += interval))
    done

    log_error "Timeout waiting for Paladin pods"
    return 1
}
