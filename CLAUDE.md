# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

GitOps-managed Kubernetes cluster using Flux CD v2. Every change committed to `main` is automatically reconciled by Flux (GitRepository polls every 1 min, Kustomizations reconcile every 10 min).

## Common Commands

```sh
# Force Flux to immediately reconcile everything
flux reconcile kustomization flux-system --with-source

# Reconcile a specific service
flux reconcile kustomization minecraft-kustomization

# Check sync status of all kustomizations
flux get kustomizations

# Encrypt a secret before committing
sops --encrypt --in-place secret.yaml

# Decrypt a secret to inspect it (requires PGP key)
sops --decrypt secret.yaml

# Check cluster state
kubectl get pods -A
kubectl get helmreleases -A
```

## Repository Architecture

### GitOps Flow

Flux's root path is `./cluster`. Everything starts from `cluster/flux-system/gotk-sync.yaml`. Flux reads `cluster/` and reconciles:
- `cluster/namespaces/` — Namespace definitions applied first
- `cluster/helmrepositories/` — Helm chart sources
- `cluster/kustomization/` — One Flux `Kustomization` CRD per service, each pointing to a root-level directory (e.g., `path: ./minecraft`)

Each root-level directory (e.g., `minecraft/`, `n8n/`, `lgtm/`) contains the actual Kubernetes manifests for that service.

### Adding a New Service

1. Create `<service>/` directory with manifests
2. Add `cluster/kustomization/<service>-kustomization.yaml` (Flux `Kustomization` pointing to `./service`)
3. Add `cluster/namespaces/<service>-namespace.yaml` if needed
4. Add `cluster/helmrepositories/<service>-repo.yaml` if it needs a Helm chart
5. Commit and push — Flux picks up within 1 minute

### Secrets: Two-Layer Architecture

**Layer 1 — Bootstrap (SOPS+PGP)**: Used for the Vault token that unlocks everything else. Files with `sops:` metadata are encrypted at rest. SOPS encrypts only `data`, `stringData`, `secret`, and `secureJsonData` fields (see `.sops.yaml`). Flux decrypts via the `sops-gpg` secret in `flux-system`.

**Layer 2 — Runtime (Vault + External Secrets Operator)**: All other secrets are fetched from Vault at `https://vault.wololoaeyoyo.com` via `ExternalSecret` resources. The single `ClusterSecretStore` named `vault-backend-access` (in `external-secrets/clusterSecret/`) authenticates to Vault using the SOPS-encrypted token. Vault paths use KV v2 format: `<service>/data/<path>` with `property: data.<key>`.

Example ExternalSecret pattern:
```yaml
spec:
  secretStoreRef:
    name: vault-backend-access
    kind: ClusterSecretStore
  data:
    - secretKey: MY_KEY
      remoteRef:
        key: myservice/data/secrets
        property: data.MY_KEY
```

### Networking / Ingress

- **Public internet**: Cloudflare Tunnels (`cloudflare/` and `cloudflare-tunnel-mer/`)
- **VPN access**: Tailscale — uses a `ProxyGroup` (type: `ingress`) in the `tailscale` namespace. Expose a service via Tailscale by setting `spec.type: LoadBalancer` and `spec.loadBalancerClass: tailscale.com/tailscale` with annotation `tailscale.com/hostname: "<name>"` on the Service.
- **Internal LB**: MetalLB (bare-metal L2/BGP)
- **Reverse proxy**: NGINX (3 replicas in `nginx/`)
- **Domain**: `*.wololoaeyoyo.com`

### Helm-based Services

HelmReleases reference a `HelmRepository` source and pass values via a `ConfigMap` using `valuesFrom`. Pattern:
```yaml
spec:
  valuesFrom:
    - kind: ConfigMap
      name: <service>-configmap
      valuesKey: values.yaml
```

### OpenClaw (AI Agent Platform)

Uses a custom CRD `OpenClawInstance` from the `openclaw-operator`. The instance runs Ollama as a sidecar (pulling `kimi-k2.5:cloud` and `gemma4:e2b`), with a Chromium sidecar for browser automation. Model fallback chain: `ollama/kimi-k2.5:cloud` → `ollama/gemma4` → `anthropic/claude-sonnet-4-20250514`. Secrets (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OLLAMA_API_KEY`) come from the `openclaw-api-keys` ExternalSecret.

### Observability (LGTM Stack)

All components live under `lgtm/`:
- **Alloy**: collects node metrics (node_exporter) and logs, forwards to Mimir and Loki
- **Mimir**: receives metrics at `http://mimir-mimir-gateway.mimir.svc.cluster.local/api/v1/push`
- **Loki**: log aggregation
- **Tempo**: distributed tracing
- **Pyroscope**: continuous profiling
- **Grafana**: dashboards at `grafana.wololoaeyoyo.com`

### Storage

Longhorn provides distributed block storage. PVCs reference Longhorn as the storage class for stateful workloads (n8n, chibi-safe, gotify, openclaw, etc.).
