# Breizh

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

A local development environment for deploying a private **Hyperledger Besu 25.x** network with **Paladin** on **k3s (Rancher Desktop)**.

> **⚠️ WARNING**: This project is for **development and testing purposes only**. Do not use in production.

## 🚀 Features

* **Consensus**: QBFT (4 nodes minimum).
* **Privacy**: Integrated Paladin with `noto`, `zeto`, and `pente` domains.
* **Gas**: Zero gas fees (EIP-1559 `zeroBaseFee` + `min-gas-price=0`).
* **Storage**: Efficient Bonsai storage format.
* **Architecture**: Besu StatefulSet + Paladin Operator.

## 📋 Prerequisites

* **Rancher Desktop** (running k3s)
  * Resources: 8GB+ RAM, 4+ CPUs
* **Tools**: `docker`, `kubectl`, `helm`, `jq`, `make`

## 🛠️ Quick Start

This project uses a `Makefile` to automate the deployment lifecycle.

### 1. Generate & Build

Generate validator keys, genesis file, and Kubernetes manifests.

```bash
make generate   # Generate keys and genesis
make build      # Build K8s manifests and configs
```

### 2. Deploy

Deploy the network to your local k3s cluster.

```bash
make deploy     # Deploy Besu and Paladin
```

### 3. Verify

Check if the network is up and peering correctly.

```bash
make verify     # Check peers, block production, and health
```

### One-liner

Run the entire sequence:

```bash
make all
```

## ⚙️ Configuration

Key network variables can be customized in `config/network.env`:

* `NETWORK_NAME`: Name of the network/namespace (default: `besu-paladin`)
* `NODE_COUNT`: Number of validator nodes (default: `4`)
* `CHAIN_ID`: Chain ID (default: `1337`)

## 🏗️ Architecture

```mermaid
graph TD
    subgraph K3s["k3s Cluster"]
        subgraph NS["Namespace: besu-paladin"]
            subgraph Besu["Besu StatefulSet"]
                B0[besu-0]
                B1[besu-1]
                B2[besu-2]
                B3[besu-3]
            end
            HL[Headless Service]
            subgraph Paladin["Paladin Operator"]
                P0[paladin-0] --> B0
                P1[paladin-1] --> B1
                P2[paladin-2] --> B2
                P3[paladin-3] --> B3
            end
        end
    end
    User -->|port-forward| HL
```

## 🧹 Cleanup

To remove the network and generated files:

```bash
make clean      # Delete namespace and generated files
```
