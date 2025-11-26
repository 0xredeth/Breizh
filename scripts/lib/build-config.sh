#!/bin/bash
# ============================================================
# Build configuration functions (Phase 2.1 - 2.3)
# ============================================================

# ─────────────────────────────────────────────────────────────────────────────
# 2.1 build_static_nodes()
# Create static-nodes.json with enodes for all nodes
# ─────────────────────────────────────────────────────────────────────────────
build_static_nodes() {
    local network_dir="$1"
    local config_dir="$2"

    log_info "Building static-nodes.json..."

    local mapping_file="$network_dir/mapping.json"
    local keys_dir="$network_dir/networkFiles/keys"

    if [[ ! -f "$mapping_file" ]]; then
        log_error "mapping.json not found. Run 01-generate.sh first."
        exit 1
    fi

    local enodes="[]"

    for i in $(seq 0 $((NODE_COUNT - 1))); do
        local addr
        addr=$(jq -r ".\"node-$i\"" "$mapping_file")

        local key_pub_file="$keys_dir/$addr/key.pub"
        if [[ ! -f "$key_pub_file" ]]; then
            log_error "Public key not found: $key_pub_file"
            exit 1
        fi

        # Read public key and strip 0x prefix
        local pubkey
        pubkey=$(cat "$key_pub_file" | sed 's/^0x//')

        # Build enode URL with K8s DNS
        # Format: ${NETWORK_NAME}-<index>.${HEADLESS_SERVICE}.${NAMESPACE}.${CLUSTER_DOMAIN}
        local host="${NETWORK_NAME}-${i}.${HEADLESS_SERVICE}.${NAMESPACE}.${CLUSTER_DOMAIN}"
        local enode="enode://${pubkey}@${host}:${P2P_PORT}"

        enodes=$(echo "$enodes" | jq --arg enode "$enode" '. += [$enode]')
        log_info "  node-$i: ${host}"
    done

    echo "$enodes" | jq '.' > "$config_dir/static-nodes.json"
    log_success "Generated: config/static-nodes.json"
}

# ─────────────────────────────────────────────────────────────────────────────
# 2.2 build_permissions_config()
# Create permissions_config.toml for local permissioning
# ─────────────────────────────────────────────────────────────────────────────
build_permissions_config() {
    local network_dir="$1"
    local config_dir="$2"

    log_info "Building permissions_config.toml..."

    local mapping_file="$network_dir/mapping.json"
    local static_nodes_file="$config_dir/static-nodes.json"

    # Start building TOML content
    local toml_content="# Permissions configuration for ${NETWORK_NAME}\n\n"

    # Nodes allowlist (same enodes as static-nodes.json)
    toml_content+="nodes-allowlist = [\n"
    local enodes
    enodes=$(jq -r '.[]' "$static_nodes_file")
    local first=true
    while IFS= read -r enode; do
        if [[ "$first" == "true" ]]; then
            toml_content+="  \"${enode}\""
            first=false
        else
            toml_content+=",\n  \"${enode}\""
        fi
    done <<< "$enodes"
    toml_content+="\n]\n\n"

    # Accounts allowlist (validator addresses only)
    toml_content+="accounts-allowlist = [\n"
    first=true
    for i in $(seq 0 $((NODE_COUNT - 1))); do
        local addr
        addr=$(jq -r ".\"node-$i\"" "$mapping_file")
        if [[ "$first" == "true" ]]; then
            toml_content+="  \"${addr}\""
            first=false
        else
            toml_content+=",\n  \"${addr}\""
        fi
    done
    toml_content+="\n]\n"

    echo -e "$toml_content" > "$config_dir/permissions_config.toml"
    log_success "Generated: config/permissions_config.toml"
}

# ─────────────────────────────────────────────────────────────────────────────
# 2.3 build_besu_config()
# Generate besu.toml from template
# ─────────────────────────────────────────────────────────────────────────────
build_besu_config() {
    local project_dir="$1"
    local config_dir="$2"

    log_info "Building besu.toml..."

    substitute_template \
        "$project_dir/templates/besu.toml.tmpl" \
        "$config_dir/besu.toml"

    log_success "Generated: config/besu.toml"
}
