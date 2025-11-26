#!/bin/bash
# ============================================================
# 02-build.sh - Build configurations and K8s manifests
# ============================================================
# Phase 2: Build configs from generated keys
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
source "$SCRIPT_DIR/lib/build-config.sh"
source "$SCRIPT_DIR/lib/build-k8s.sh"
source "$SCRIPT_DIR/lib/build-paladin.sh"

# Load configuration
source "$PROJECT_DIR/config/network.env"

# Export variables for envsubst
export NETWORK_NAME NODE_COUNT CHAIN_ID
export NAMESPACE HEADLESS_SERVICE CLUSTER_DOMAIN
export P2P_PORT RPC_HTTP_PORT RPC_WS_PORT METRICS_PORT
export MIN_GAS_PRICE SYNC_MODE DATA_STORAGE_FORMAT
export BESU_IMAGE PALADIN_RPC_PORT

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    log_info "=== Phase 2: Build Configurations ==="
    log_info "Network: $NETWORK_NAME (Chain ID: $CHAIN_ID)"

    # Validate configuration
    validate_config

    # Define directories (network-specific folder)
    local network_dir="$PROJECT_DIR/generated/$NETWORK_NAME"
    local config_dir="$network_dir/config"
    local k8s_dir="$network_dir/k8s"

    # Verify Phase 1 output exists
    if [[ ! -d "$network_dir/networkFiles" ]]; then
        log_error "Network files not found. Run 01-generate.sh first."
        exit 1
    fi

    # Prepare output directories
    mkdir -p "$config_dir"
    mkdir -p "$k8s_dir"

    # ─────────────────────────────────────────────────────────────────────────
    # Phase 2.1 - Build static-nodes.json
    # ─────────────────────────────────────────────────────────────────────────
    build_static_nodes "$network_dir" "$config_dir"

    # ─────────────────────────────────────────────────────────────────────────
    # Phase 2.2 - Build permissions_config.toml
    # ─────────────────────────────────────────────────────────────────────────
    build_permissions_config "$network_dir" "$config_dir"

    # ─────────────────────────────────────────────────────────────────────────
    # Phase 2.3 - Build besu.toml from template
    # ─────────────────────────────────────────────────────────────────────────
    build_besu_config "$PROJECT_DIR" "$config_dir"

    # ─────────────────────────────────────────────────────────────────────────
    # Phase 2.4 - Build K8s manifests
    # ─────────────────────────────────────────────────────────────────────────
    build_k8s_manifests "$network_dir" "$config_dir" "$k8s_dir"

    # ─────────────────────────────────────────────────────────────────────────
    # Phase 2.5 - Build Paladin values for Helm
    # ─────────────────────────────────────────────────────────────────────────
    build_paladin_values "$k8s_dir"

    # ─────────────────────────────────────────────────────────────────────────
    # Summary
    # ─────────────────────────────────────────────────────────────────────────
    log_success "Build complete!"
    log_info ""
    log_info "Generated files:"
    log_info "  Config:"
    log_info "    - generated/$NETWORK_NAME/config/static-nodes.json"
    log_info "    - generated/$NETWORK_NAME/config/permissions_config.toml"
    log_info "    - generated/$NETWORK_NAME/config/besu.toml"
    log_info ""
    log_info "  K8s manifests:"
    log_info "    - generated/$NETWORK_NAME/k8s/namespace.yaml"
    log_info "    - generated/$NETWORK_NAME/k8s/configmap-besu.yaml"
    log_info "    - generated/$NETWORK_NAME/k8s/secret-keys.yaml"
    log_info "    - generated/$NETWORK_NAME/k8s/service-headless.yaml"
    log_info "    - generated/$NETWORK_NAME/k8s/service-rpc.yaml"
    log_info "    - generated/$NETWORK_NAME/k8s/statefulset-besu.yaml"
    log_info "    - generated/$NETWORK_NAME/k8s/paladin-values.yaml"
    log_info ""
    log_info "Next: ./scripts/03-deploy.sh"
}

main "$@"
