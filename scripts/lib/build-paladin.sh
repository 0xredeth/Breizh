#!/bin/bash
# ============================================================
# Build Paladin configuration functions (Phase 2.5)
# ============================================================

# ─────────────────────────────────────────────────────────────────────────────
# 2.5 build_paladin_values()
# Generate paladin-values.yaml for Helm deployment
# ─────────────────────────────────────────────────────────────────────────────
build_paladin_values() {
    local k8s_dir="$1"

    log_info "Building paladin-values.yaml..."

    cat > "$k8s_dir/paladin-values.yaml" << EOF
# Paladin Helm values for ${NETWORK_NAME}
# Generated for ${PALADIN_NODE_COUNT} Paladin nodes connecting to external Besu network

mode: customnet

paladinNodes:
EOF

    # Generate node entries (use PALADIN_NODE_COUNT for light mode support)
    for i in $(seq 0 $((PALADIN_NODE_COUNT - 1))); do
        local besu_host="${NETWORK_NAME}-${i}.${HEADLESS_SERVICE}.${NAMESPACE}.${CLUSTER_DOMAIN}"

        cat >> "$k8s_dir/paladin-values.yaml" << EOF
  - name: node-${i}
    baseLedgerEndpoint:
      type: endpoint
      endpoint:
        jsonrpc: http://${besu_host}:${RPC_HTTP_PORT}
        ws: ws://${besu_host}:${RPC_WS_PORT}
    service:
      type: ClusterIP
      ports:
        rpcHttp:
          port: ${PALADIN_RPC_PORT}
        rpcWs:
          port: $((PALADIN_RPC_PORT + 1))
    domains:
      - noto
      - zeto
      - pente
    registries:
      - evm-registry
    transports:
      - name: grpc
        plugin:
          type: c-shared
          library: /app/transports/libgrpc.so
        config:
          port: 9000
          address: 0.0.0.0
        tls:
          secretName: node-${i}-grpc-tls
          certName: node-${i}-grpc-tls
        ports:
          transportGrpc:
            port: 9000
            targetPort: 9000
    resources:
      limits:
        cpu: "2000m"
        memory: "4Gi"
      requests:
        cpu: "500m"
        memory: "2Gi"
    database:
      mode: sidecarPostgres
      migrationMode: auto
      resources:
        limits:
          cpu: "1000m"
          memory: "2Gi"
        requests:
          cpu: "100m"
          memory: "512Mi"
    secretBackedSigners:
      - name: signer-auto-wallet
        secret: node-${i}.keys
        type: autoHDWallet
        keySelector: ".*"
    config: |
      log:
        level: info
    paladinRegistration:
      registryAdminNode: node-0
      registryAdminKey: registry.operator
      registry: evm-registry
EOF
    done

    log_success "Generated: k8s/paladin-values.yaml"
}
