#!/bin/bash
# ============================================================
# Build K8s manifest functions (Phase 2.4)
# ============================================================

# ─────────────────────────────────────────────────────────────────────────────
# 2.4 build_k8s_manifests()
# Generate all Kubernetes manifests
# ─────────────────────────────────────────────────────────────────────────────
build_k8s_manifests() {
    local network_dir="$1"
    local config_dir="$2"
    local k8s_dir="$3"

    log_info "Building K8s manifests..."

    _build_namespace "$k8s_dir"
    _build_configmap "$network_dir" "$config_dir" "$k8s_dir"
    _build_secret "$network_dir" "$k8s_dir"
    _build_service_headless "$k8s_dir"
    _build_service_rpc "$k8s_dir"
    _build_statefulset "$k8s_dir"

    log_success "K8s manifests generated in: k8s/"
}

# ─────────────────────────────────────────────────────────────────────────────
# Namespace
# ─────────────────────────────────────────────────────────────────────────────
_build_namespace() {
    local k8s_dir="$1"

    cat > "$k8s_dir/namespace.yaml" << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    app: ${NETWORK_NAME}
EOF
    log_info "  - namespace.yaml"
}

# ─────────────────────────────────────────────────────────────────────────────
# ConfigMap - genesis.json, static-nodes.json, besu.toml, permissions_config.toml
# ─────────────────────────────────────────────────────────────────────────────
_build_configmap() {
    local network_dir="$1"
    local config_dir="$2"
    local k8s_dir="$3"

    cat > "$k8s_dir/configmap-besu.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${NETWORK_NAME}-config
  namespace: ${NAMESPACE}
  labels:
    app: ${NETWORK_NAME}
data:
  genesis.json: |
$(cat "$network_dir/networkFiles/genesis.json" | sed 's/^/    /')
  static-nodes.json: |
$(cat "$config_dir/static-nodes.json" | sed 's/^/    /')
  besu.toml: |
$(cat "$config_dir/besu.toml" | sed 's/^/    /')
  permissions_config.toml: |
$(cat "$config_dir/permissions_config.toml" | sed 's/^/    /')
EOF
    log_info "  - configmap-besu.yaml"
}

# ─────────────────────────────────────────────────────────────────────────────
# Secret - Node private keys (base64 encoded)
# ─────────────────────────────────────────────────────────────────────────────
_build_secret() {
    local network_dir="$1"
    local k8s_dir="$2"

    local mapping_file="$network_dir/mapping.json"
    local keys_dir="$network_dir/networkFiles/keys"

    cat > "$k8s_dir/secret-keys.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${NETWORK_NAME}-keys
  namespace: ${NAMESPACE}
  labels:
    app: ${NETWORK_NAME}
type: Opaque
data:
EOF

    for i in $(seq 0 $((NODE_COUNT - 1))); do
        local addr
        addr=$(jq -r ".\"node-$i\"" "$mapping_file")

        local key_file="$keys_dir/$addr/key"
        local key_b64
        key_b64=$(cat "$key_file" | base64)

        echo "  node-${i}-key: ${key_b64}" >> "$k8s_dir/secret-keys.yaml"
    done

    log_info "  - secret-keys.yaml"
}

# ─────────────────────────────────────────────────────────────────────────────
# Headless Service - For StatefulSet DNS resolution
# ─────────────────────────────────────────────────────────────────────────────
_build_service_headless() {
    local k8s_dir="$1"

    cat > "$k8s_dir/service-headless.yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${HEADLESS_SERVICE}
  namespace: ${NAMESPACE}
  labels:
    app: ${NETWORK_NAME}
spec:
  clusterIP: None
  selector:
    app: ${NETWORK_NAME}
  ports:
    - name: p2p-tcp
      port: ${P2P_PORT}
      targetPort: ${P2P_PORT}
      protocol: TCP
    - name: p2p-udp
      port: ${P2P_PORT}
      targetPort: ${P2P_PORT}
      protocol: UDP
    - name: rpc-http
      port: ${RPC_HTTP_PORT}
      targetPort: ${RPC_HTTP_PORT}
    - name: rpc-ws
      port: ${RPC_WS_PORT}
      targetPort: ${RPC_WS_PORT}
    - name: metrics
      port: ${METRICS_PORT}
      targetPort: ${METRICS_PORT}
EOF
    log_info "  - service-headless.yaml"
}

# ─────────────────────────────────────────────────────────────────────────────
# RPC Service - ClusterIP for JSON-RPC access
# ─────────────────────────────────────────────────────────────────────────────
_build_service_rpc() {
    local k8s_dir="$1"

    cat > "$k8s_dir/service-rpc.yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${NETWORK_NAME}-rpc
  namespace: ${NAMESPACE}
  labels:
    app: ${NETWORK_NAME}
spec:
  type: ClusterIP
  selector:
    app: ${NETWORK_NAME}
  ports:
    - name: rpc-http
      port: ${RPC_HTTP_PORT}
      targetPort: ${RPC_HTTP_PORT}
    - name: rpc-ws
      port: ${RPC_WS_PORT}
      targetPort: ${RPC_WS_PORT}
EOF
    log_info "  - service-rpc.yaml"
}

# ─────────────────────────────────────────────────────────────────────────────
# StatefulSet - Besu nodes with initContainer for key selection
# ─────────────────────────────────────────────────────────────────────────────
_build_statefulset() {
    local k8s_dir="$1"

    cat > "$k8s_dir/statefulset-besu.yaml" << 'STATEFULSET_EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: NETWORK_NAME_PLACEHOLDER
  namespace: NAMESPACE_PLACEHOLDER
  labels:
    app: NETWORK_NAME_PLACEHOLDER
spec:
  serviceName: HEADLESS_SERVICE_PLACEHOLDER
  replicas: NODE_COUNT_PLACEHOLDER
  podManagementPolicy: OrderedReady
  selector:
    matchLabels:
      app: NETWORK_NAME_PLACEHOLDER
  template:
    metadata:
      labels:
        app: NETWORK_NAME_PLACEHOLDER
    spec:
      initContainers:
        - name: init-key
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              NODE_INDEX=$(echo $HOSTNAME | sed 's/NETWORK_NAME_PLACEHOLDER-//')
              echo "Initializing node-${NODE_INDEX}..."
              cp /secrets/node-${NODE_INDEX}-key /data/key
              chmod 600 /data/key
              echo "Key copied successfully"
          volumeMounts:
            - name: secrets
              mountPath: /secrets
              readOnly: true
            - name: data
              mountPath: /data
      containers:
        - name: besu
          image: BESU_IMAGE_PLACEHOLDER
          args:
            - --config-file=/etc/besu/besu.toml
          ports:
            - name: p2p-tcp
              containerPort: P2P_PORT_PLACEHOLDER
              protocol: TCP
            - name: p2p-udp
              containerPort: P2P_PORT_PLACEHOLDER
              protocol: UDP
            - name: rpc-http
              containerPort: RPC_HTTP_PORT_PLACEHOLDER
            - name: rpc-ws
              containerPort: RPC_WS_PORT_PLACEHOLDER
            - name: metrics
              containerPort: METRICS_PORT_PLACEHOLDER
          volumeMounts:
            - name: config
              mountPath: /etc/besu
              readOnly: true
            - name: data
              mountPath: /data
          resources:
            requests:
              memory: "1Gi"
              cpu: "500m"
            limits:
              memory: "2Gi"
              cpu: "1000m"
          livenessProbe:
            httpGet:
              path: /liveness
              port: rpc-http
            initialDelaySeconds: 60
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /readiness
              port: rpc-http
            initialDelaySeconds: 30
            periodSeconds: 10
      volumes:
        - name: config
          configMap:
            name: NETWORK_NAME_PLACEHOLDER-config
        - name: secrets
          secret:
            secretName: NETWORK_NAME_PLACEHOLDER-keys
  volumeClaimTemplates:
    - metadata:
        name: data
        labels:
          app: NETWORK_NAME_PLACEHOLDER
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
STATEFULSET_EOF

    # Replace placeholders with actual values
    sed -i '' \
        -e "s/NETWORK_NAME_PLACEHOLDER/${NETWORK_NAME}/g" \
        -e "s/NAMESPACE_PLACEHOLDER/${NAMESPACE}/g" \
        -e "s/HEADLESS_SERVICE_PLACEHOLDER/${HEADLESS_SERVICE}/g" \
        -e "s/NODE_COUNT_PLACEHOLDER/${NODE_COUNT}/g" \
        -e "s|BESU_IMAGE_PLACEHOLDER|${BESU_IMAGE}|g" \
        -e "s/P2P_PORT_PLACEHOLDER/${P2P_PORT}/g" \
        -e "s/RPC_HTTP_PORT_PLACEHOLDER/${RPC_HTTP_PORT}/g" \
        -e "s/RPC_WS_PORT_PLACEHOLDER/${RPC_WS_PORT}/g" \
        -e "s/METRICS_PORT_PLACEHOLDER/${METRICS_PORT}/g" \
        "$k8s_dir/statefulset-besu.yaml"

    log_info "  - statefulset-besu.yaml"
}
