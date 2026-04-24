# Cluster-kubernetes

GitOps-managed Kubernetes cluster configuration using Flux CD. This repository is the single source of truth for all workloads, infrastructure, and secrets running on the cluster.

## Overview

The cluster hosts a diverse set of self-hosted services: AI agents, workflow automation, file sharing, gaming servers, and a full observability stack. All deployments are declarative and reconciled automatically via Flux CD.

**GitOps sync**: every 1 minute (GitRepository) / 10 minutes (Kustomizations)  
**Secrets**: encrypted at rest with [SOPS](https://github.com/mozilla/sops) + PGP  
**External access**: Cloudflare Tunnels + Tailscale VPN

---

## Services

### Applications

| Service | Description | Domain |
|---|---|---|
| **OpenClaw** | AI agent platform with Ollama (local LLMs) + Chromium sidecars | `openclaw.wololoaeyoyo.com` |
| **n8n** | Workflow automation with PostgreSQL backend and LaTeX support | `n8n.wololoaeyoyo.com` |
| **Resume Web** | Personal resume / portfolio site (Next.js) | `resume.wololoaeyoyo.com` |
| **Chibi Safe** | Self-hosted file sharing platform | — |
| **Discord Bot** | HR Music Bot for Discord | — |
| **Minecraft** | Game server via Helm | — |

### Infrastructure

| Component | Purpose | Version |
|---|---|---|
| **Flux CD** | GitOps controller | v2 |
| **MetalLB** | Bare-metal load balancer (BGP/L2) | 0.15.2 |
| **Longhorn** | Distributed block storage | 1.9.1 |
| **Cert-Manager** | TLS certificate automation | 1.16.3 |
| **Cloudflare Tunnel** | Secure external ingress | 0.0.18 |
| **Tailscale** | VPN mesh networking | — |
| **NGINX** | Reverse proxy (3 replicas) | — |

### Security & Secrets

| Component | Purpose | Version |
|---|---|---|
| **Vault** | Secret management | 0.30.1 |
| **External Secrets** | Sync secrets from external stores | 0.19.2 |
| **SOPS** | Secret encryption for GitOps | — |

### Observability (LGTM Stack)

| Component | Purpose |
|---|---|
| **Grafana Alloy** | Metrics and logs collection |
| **Grafana** | Dashboards |
| **Loki** | Log aggregation |
| **Mimir** | Long-term metrics storage |
| **Tempo** | Distributed tracing |
| **Pyroscope** | Continuous profiling |

---

## Repository Structure

```
.
├── cluster/
│   ├── flux-system/        # Flux bootstrap configuration
│   ├── helmrepositories/   # Helm chart sources
│   ├── kustomization/      # Kustomize overlays per service
│   └── namespaces/         # Namespace definitions (20 namespaces)
├── openclaw/               # AI agent platform manifests
├── openclaw-operator/      # OpenClaw operator
├── n8n/                    # Workflow automation
├── personal-web-site/      # Resume / portfolio site (Next.js)
├── minecraft/              # Minecraft server
├── chibi-safe/             # File sharing
├── bot-discord/            # Discord music bot
├── nginx/                  # Reverse proxy
├── metallb/                # Load balancer
├── cloudflare/             # Tunnel ingress
├── tailscale/              # VPN
├── vault/                  # Secret management
├── external-secrets/       # External secrets sync
├── cert-manager/           # TLS automation
├── longhorn/               # Storage
├── lgtm/                   # Observability stack
├── reloader/               # Config change restarter
└── .sops.yaml              # SOPS encryption config
```

---

## Prerequisites

- A running Kubernetes cluster
- `kubectl` configured against the cluster
- `flux` CLI installed
- `sops` + PGP key for secret decryption
- `helm` 3.x

---

## Bootstrap

1. **Import the SOPS PGP key** on the cluster node(s):
   ```sh
   gpg --import private.key
   ```

2. **Create the SOPS secret** in the `flux-system` namespace:
   ```sh
   gpg --export-secret-keys --armor <KEY_ID> |
     kubectl create secret generic sops-gpg \
       --namespace=flux-system \
       --from-file=sops.asc=/dev/stdin
   ```

3. **Bootstrap Flux** pointing at this repository:
   ```sh
   flux bootstrap github \
     --components-extra=image-reflector-controller,image-automation-controller \
     --owner=wololo-aeyoyo \
     --repository=cluster-kubernetes \
     --branch=main \
     --path=cluster \
     --personal
   ```

Flux will reconcile all kustomizations and deploy every service automatically.

---

## Adding a New Service

1. Create a directory with your Kubernetes manifests.
2. Add a `Kustomization` resource under `cluster/kustomization/`.
3. Add a `Namespace` under `cluster/namespaces/` if needed.
4. Commit and push — Flux picks up the change within 1 minute.

For secrets, encrypt them before committing:
```sh
sops --encrypt --in-place secret.yaml
```

---

## Tech Stack

- **Container runtime**: Kubernetes
- **GitOps**: Flux CD v2 + Kustomize + Helm
- **Secrets**: SOPS (PGP) + Vault + External Secrets Operator
- **Storage**: Longhorn
- **Networking**: MetalLB, Cloudflare Tunnels, Tailscale, NGINX
- **Observability**: Grafana, Loki, Mimir, Tempo, Pyroscope, Alloy
- **AI/ML**: Ollama (local LLMs: kimi-k2.5, gemma4), OpenAI, Anthropic Claude
