.PHONY: all generate build deploy verify clean status logs info light all-light \
        dashboard-start dashboard-stop network-start network-stop network-status

# Variables (loaded from config/network.env)
SHELL := /bin/bash
-include config/network.env
export

# Main targets
all: generate build deploy verify

# Light mode (single Paladin node for low-resource PCs)
light: PALADIN_NODE_COUNT=1
light: generate build deploy verify

all-light: light

generate:
	@echo "🔑 Phase 1: Generating keys and genesis for $(NETWORK_NAME)..."
	@./scripts/01-generate.sh

build:
	@echo "🔧 Phase 2: Building configurations..."
	@./scripts/02-build.sh

deploy:
	@echo "🚀 Phase 3: Deploying $(NODE_COUNT) nodes to cluster..."
	@./scripts/03-deploy.sh

verify:
	@echo "✅ Phase 4: Verifying network..."
	@./scripts/04-verify.sh

# Utilities
status:
	@kubectl get pods -n $(NAMESPACE)
	@kubectl get svc -n $(NAMESPACE)

logs:
	@kubectl logs -n $(NAMESPACE) -l app=besu --tail=50 -f

logs-paladin:
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=paladin --tail=50 -f

shell-besu:
	@kubectl exec -it -n $(NAMESPACE) $(NETWORK_NAME)-0 -- /bin/sh

shell-paladin:
	@kubectl exec -it -n $(NAMESPACE) paladin-node-0-0 -- /bin/sh

port-forward-rpc:
	@kubectl port-forward -n $(NAMESPACE) svc/$(NETWORK_NAME)-rpc 8545:8545

port-forward-paladin:
	@kubectl port-forward -n $(NAMESPACE) svc/paladin-node-0 8548:8548

# Dashboard management (Paladin UI port-forward)
dashboard-start:
	@./scripts/dashboard.sh start

dashboard-stop:
	@./scripts/dashboard.sh stop

# Network start/stop (without destroying)
network-start:
	@./scripts/network-ctl.sh start

network-stop:
	@./scripts/network-ctl.sh stop

network-status:
	@./scripts/network-ctl.sh status

clean:
	@echo "🧹 Phase 5: Cleaning up $(NETWORK_NAME)..."
	@./scripts/05-clean.sh --force

reset: clean all

# Info
info:
	@echo "Network: $(NETWORK_NAME)"
	@echo "Nodes: $(NODE_COUNT)"
	@echo "Chain ID: $(CHAIN_ID)"
	@echo "Namespace: $(NAMESPACE)"
