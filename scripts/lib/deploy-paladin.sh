#!/bin/bash
# ============================================================
# Deploy Paladin functions (Phase 3.3)
# ============================================================

# Paladin Helm repository (correct URL from official docs)
readonly PALADIN_HELM_REPO="https://lfdt-paladin.github.io/paladin"
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

    # Step 2: Install cert-manager (skip if already installed)
    log_info "Installing cert-manager..."
    if helm list -n cert-manager 2>/dev/null | grep -q "cert-manager"; then
        log_info "cert-manager already installed, skipping..."
    else
        helm install cert-manager --namespace cert-manager --version v1.16.1 \
            jetstack/cert-manager --create-namespace --set crds.enabled=true --wait || {
            log_warn "cert-manager installation failed - may already exist"
        }
    fi

    # Step 3: Install/Upgrade Paladin operator (use upgrade --install to handle both cases)
    log_info "Installing/Upgrading Paladin operator..."
    helm upgrade --install "$release_name" "$PALADIN_HELM_REPO_NAME/paladin-operator" \
        -n "$NAMESPACE" --create-namespace -f "$values_file" --wait --timeout 5m

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
            --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')

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

# ─────────────────────────────────────────────────────────────────────────────
# NOTE: Account permissioning functions REMOVED
# ─────────────────────────────────────────────────────────────────────────────
# Besu account permissioning is DISABLED for Paladin compatibility.
# Paladin uses HD wallet key derivation (autoHDWallet) which generates
# a NEW signing address for EVERY transaction for privacy.
# This is fundamentally incompatible with Besu's static account allowlists.
# Security is provided by Paladin's cryptography (ZKPs, private EVM, notary).
# See: besu.toml.tmpl -> permissions-accounts-config-file-enabled=false
# ─────────────────────────────────────────────────────────────────────────────
