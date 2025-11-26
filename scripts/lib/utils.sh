#!/bin/bash
# ============================================================
# Utility functions
# ============================================================

# Substitute template variables using envsubst
# Usage: substitute_template <template_file> <output_file>
substitute_template() {
    local template="$1"
    local output="$2"

    # Verify template exists
    if [[ ! -f "$template" ]]; then
        log_error "Template not found: $template"
        exit 1
    fi

    # Create output directory if needed
    local output_dir
    output_dir="$(dirname "$output")"
    mkdir -p "$output_dir"

    # Substitute environment variables
    envsubst < "$template" > "$output"

    log_info "Generated: $output"
}

# Validate configuration parameters
validate_config() {
    local errors=0

    # ─────────────────────────────────────────────────────────────────────
    # NODE_COUNT: minimum 4 for Byzantine Fault Tolerance
    # ─────────────────────────────────────────────────────────────────────
    if [[ -z "$NODE_COUNT" ]]; then
        log_error "NODE_COUNT is not set"
        ((errors++))
    elif [[ "$NODE_COUNT" -lt 4 ]]; then
        log_error "NODE_COUNT must be >= 4 for BFT (got: $NODE_COUNT)"
        log_info "QBFT requires: validators >= 3*f + 1 (f=1 → min 4)"
        ((errors++))
    elif [[ "$NODE_COUNT" -gt 20 ]]; then
        log_warn "NODE_COUNT=$NODE_COUNT is high, may impact performance"
    fi

    # ─────────────────────────────────────────────────────────────────────
    # CHAIN_ID: must be unique and valid
    # ─────────────────────────────────────────────────────────────────────
    if [[ -z "$CHAIN_ID" ]]; then
        log_error "CHAIN_ID is not set"
        ((errors++))
    elif [[ "$CHAIN_ID" -lt 1 ]]; then
        log_error "CHAIN_ID must be > 0 (got: $CHAIN_ID)"
        ((errors++))
    fi

    # Check reserved chain IDs (mainnet, public testnets)
    local reserved_ids=(1 3 4 5 11155111 17000)
    for id in "${reserved_ids[@]}"; do
        if [[ "$CHAIN_ID" -eq "$id" ]]; then
            log_warn "CHAIN_ID=$CHAIN_ID is a public network ID"
            log_warn "Recommended: use 1337, 31337, or custom ID > 1000000"
        fi
    done

    # ─────────────────────────────────────────────────────────────────────
    # NETWORK_NAME: valid format for K8s
    # ─────────────────────────────────────────────────────────────────────
    if [[ -z "$NETWORK_NAME" ]]; then
        log_error "NETWORK_NAME is not set"
        ((errors++))
    elif [[ ! "$NETWORK_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
        log_error "NETWORK_NAME must be lowercase, start with letter"
        log_error "Valid: a-z, 0-9, hyphens. Got: $NETWORK_NAME"
        ((errors++))
    elif [[ ${#NETWORK_NAME} -gt 53 ]]; then
        log_error "NETWORK_NAME too long (max 53 chars for K8s)"
        ((errors++))
    fi

    # ─────────────────────────────────────────────────────────────────────
    # Required tools
    # ─────────────────────────────────────────────────────────────────────
    local required_tools=(docker jq envsubst)
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            ((errors++))
        fi
    done

    # ─────────────────────────────────────────────────────────────────────
    # Result
    # ─────────────────────────────────────────────────────────────────────
    if [[ $errors -gt 0 ]]; then
        log_error "Validation failed with $errors error(s)"
        exit 1
    fi

    log_success "Configuration validated"
}
