#!/bin/bash
# ============================================================
# 01-generate.sh - Generate QBFT network files using Besu CLI
# ============================================================
# Prerequisites: brew install besu
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

# Load configuration
source "$PROJECT_DIR/config/network.env"

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    log_info "=== Phase 1: Generate QBFT Network Files ==="

    # Validate configuration
    validate_config

    # Check Besu is installed
    if ! command -v besu &> /dev/null; then
        log_error "Besu CLI not found. Install with: brew install besu"
        exit 1
    fi

    local besu_version
    besu_version=$(besu --version 2>/dev/null | head -1)
    log_info "Using: $besu_version"

    # Prepare directories (network-specific folder)
    local network_dir="$PROJECT_DIR/generated/$NETWORK_NAME"
    local config_file="$network_dir/qbftConfigFile.json"

    log_info "Network: $NETWORK_NAME"
    rm -rf "$network_dir"
    mkdir -p "$network_dir"

    # Generate QBFT config from template
    log_info "Generating QBFT configuration..."
    substitute_template \
        "$PROJECT_DIR/config/qbftConfigFile.json.tmpl" \
        "$config_file"

    # Generate network files using Besu CLI
    log_info "Generating blockchain config (${NODE_COUNT} validators)..."
    besu operator generate-blockchain-config \
        --config-file="$config_file" \
        --to="$network_dir/networkFiles" \
        --private-key-file-name=key

    # Verify output
    if [[ ! -f "$network_dir/networkFiles/genesis.json" ]]; then
        log_error "Failed to generate genesis.json"
        exit 1
    fi

    # Create node-to-address mapping
    # Besu generates keys in address-named folders, we map them to node indices
    log_info "Creating node mapping..."
    local keys_dir="$network_dir/networkFiles/keys"
    local addresses=($(ls "$keys_dir" | sort))
    local mapping="{}"

    for i in "${!addresses[@]}"; do
        local addr="${addresses[$i]}"
        mapping=$(echo "$mapping" | jq --arg node "node-$i" --arg addr "$addr" '.[$node] = $addr')
        log_info "  node-$i -> $addr"
    done

    echo "$mapping" | jq '.' > "$network_dir/mapping.json"

    # Summary
    log_success "Generation complete!"
    log_info "Output: generated/$NETWORK_NAME/"
    log_info "  - networkFiles/genesis.json"
    log_info "  - networkFiles/keys/ (${#addresses[@]} validators)"
    log_info "  - mapping.json"
}

main "$@"
