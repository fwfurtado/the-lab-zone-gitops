# The Lab Zone - GitOps

GitOps repository for **The Lab Zone** homelab Kubernetes cluster, managed with [ArgoCD](https://argo-cd.readthedocs.io/) and [Helm](https://helm.sh/).

All cluster state is declared in this repo. ArgoCD watches the `main` branch and automatically syncs every application using the **App of Apps** pattern via `ApplicationSet`.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Deployed Applications](#deployed-applications)
- [Sync Wave Order](#sync-wave-order)
- [Bootstrap](#bootstrap)
- [How It Works](#how-it-works)
- [Per-App Convention](#per-app-convention)
- [Secrets Management](#secrets-management)
- [Networking](#networking)
- [Storage](#storage)
- [Observability](#observability)
- [CI / Linting](#ci--linting)
- [Local Development](#local-development)
- [Prerequisites](#prerequisites)

## Architecture Overview

The homelab follows a split architecture: **stateless platform services** run inside a Talos Kubernetes cluster on Proxmox, while **stateful applications** (Gitea, Authentik, Grafana, Victoria Metrics/Logs, Garage, etc.) run as Docker containers on TrueNAS. Infrastructure services (Traefik, Tailscale) run as LXC containers on Proxmox, outside the cluster.

```
┌──────────────────────────────────────────────────────────────┐
│                        GitHub (main)                         │
│  the-lab-zone-gitops                                         │
└────────────────────────────┬─────────────────────────────────┘
                             │ watches
                             ▼
┌──────────────────────────────────────────────────────────────┐
│                     ArgoCD (in-cluster)                       │
│  bootstrap Application → ApplicationSet → per-app Applications│
└────────────────────────────┬─────────────────────────────────┘
                             │ syncs
                             ▼
┌──────────────────────────────────────────────────────────────┐
│              Kubernetes Cluster (Talos Linux)                 │
│                                                              │
│  wave 0: cilium, prometheus-operator-crds                    │
│  wave 1: metallb, sealed-secrets                             │
│  wave 2: democratic-csi, external-secrets, monitoring,       │
│          traefik                                             │
│  wave 3: argocd                                              │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                   Proxmox (LXC containers)                   │
│  traefik, tailscale                                          │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                   TrueNAS (Docker containers)                │
│  gitea, authentik, grafana, victoria metrics/logs,           │
│  garage, zot registry, gitea runners                         │
└──────────────────────────────────────────────────────────────┘
```

## Repository Structure

```
.
├── .github/workflows/       # CI pipelines (yamllint, editorconfig, GitGuardian)
├── applicationsets/          # ArgoCD ApplicationSet definitions
│   └── cluster-apps.yaml    # Matrix generator: clusters × git paths
├── bootstrap/                # Initial cluster bootstrapping
│   ├── repo-secret.tpl.yaml # ArgoCD repo secret (1Password-injected template)
│   └── root.yaml            # Root Application pointing to applicationsets/
├── clusters/                 # Per-cluster application definitions
│   └── platforms/            # "platforms" cluster
│       ├── argocd/
│       ├── cilium/
│       ├── democratic-csi/
│       ├── external-secrets/
│       ├── metallb/
│       ├── monitoring/
│       ├── prometheus-operator-crds/
│       ├── sealed-secrets/
│       └── traefik/
├── makefiles/                # Modular Make targets
│   ├── argo.mk               # ArgoCD install & port-forward
│   ├── bootstrap.mk          # Bootstrap secrets & root app
│   └── yamllint.mk           # YAML linting
├── Makefile                  # Main Makefile (template, validate, clean)
├── .editorconfig             # Editor formatting rules
├── .yamllint                 # yamllint configuration
└── .gitignore
```

## Deployed Applications

| Application | Namespace | Description |
|---|---|---|
| **Cilium** | `kube-system` | CNI plugin with Hubble observability UI (kube-proxy replacement) |
| **Prometheus Operator CRDs** | `prometheus-operator-crds` | ServiceMonitor / PodMonitor CRDs for metrics |
| **MetalLB** | `metallb-system` | Bare-metal LoadBalancer (L2 mode) |
| **Sealed Secrets** | `sealed-secrets` | Encrypt secrets for safe Git storage + UI |
| **Democratic-CSI** | `democratic-csi` | CSI driver for TrueNAS NFS provisioning |
| **External Secrets** | `external-secrets` | Sync secrets from 1Password into Kubernetes |
| **Monitoring** | `monitoring` | VictoriaMetrics Operator + VictoriaLogs Collector; ships metrics and logs to TrueNAS |
| **Traefik** | `traefik` | In-cluster ingress controller & reverse proxy |
| **ArgoCD** | `argocd` | GitOps continuous delivery |

## Sync Wave Order

Applications are deployed in a specific order using ArgoCD sync waves to respect dependencies:

| Wave | Applications | Purpose |
|---|---|---|
| **0** | Cilium, Prometheus Operator CRDs | Core networking & CRD foundations |
| **1** | MetalLB, Sealed Secrets | LoadBalancer IPs & secret encryption |
| **2** | Democratic-CSI, External Secrets, Monitoring, Traefik | Storage, secrets sync, observability & ingress |
| **3** | ArgoCD | GitOps platform (needs Traefik ingress, External Secrets for repo creds) |

## Bootstrap

Bootstrapping sets up ArgoCD and the initial secrets so the cluster can begin self-managing from Git.

### Prerequisites

- `kubectl` configured for the target cluster
- `helm` v3+
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) authenticated
- `openssl` and `ssh-keygen`
- `kubeseal` (for re-sealing secrets)

### Steps

**1. Install ArgoCD**

```bash
make argocd
```

This installs ArgoCD via Helm, waits for it to be ready, and starts a port-forward to `https://localhost:8080`.

**2. Bootstrap the cluster**

```bash
make bootstrap
```

This runs three steps in sequence:

1. **`bootstrap-secrets`** — Injects the GitHub repo credentials from 1Password and creates the ArgoCD repository Secret
2. **`bootstrap-sealed-secrets-key`** — Reads the Sealed Secrets RSA private key from 1Password and creates the TLS secret in the `sealed-secrets` namespace
3. **`bootstrap-app`** — Applies the root Application (`bootstrap/root.yaml`) which points ArgoCD to the `applicationsets/` directory

From this point, ArgoCD takes over. The `ApplicationSet` discovers all `app.yaml` files under `clusters/` and creates an ArgoCD Application for each one.

## How It Works

### App of Apps with ApplicationSet

The root Application (`bootstrap/root.yaml`) syncs the `applicationsets/` directory. Inside, `cluster-apps.yaml` uses a **matrix generator** that combines:

1. **Cluster generator** — selects clusters labeled `lab.the-lab.zone/managed: "true"`
2. **Git file generator** — finds all `clusters/<cluster-name>/**/app.yaml` files

For each match, an ArgoCD Application is created with:

- Automated sync with self-heal and pruning
- Server-side apply enabled
- `CreateNamespace=true`
- Sync wave from the `app.yaml` metadata
- Helm release name from `app.yaml`

### Adding a New Application

1. Create a new directory under `clusters/platforms/<app-name>/`
2. Add the required files:
   - `app.yaml` — metadata (name, namespace, syncWave, releaseName)
   - `Chart.yaml` — Helm chart with dependencies
   - `values.yaml` — value overrides
   - `templates/` — additional Kubernetes manifests (optional)
3. Commit and push to `main`
4. ArgoCD automatically detects and deploys the new application

Example `app.yaml`:

```yaml
app:
  name: my-app
  namespace: my-app
  syncWave: "2"
  releaseName: my-app
```

## Per-App Convention

Each application under `clusters/platforms/` follows a consistent structure:

```
<app-name>/
├── app.yaml          # ArgoCD metadata (name, namespace, syncWave, releaseName)
├── Chart.yaml        # Helm chart definition with upstream dependencies
├── Chart.lock        # Locked dependency versions
├── values.yaml       # Helm value overrides
└── templates/        # Additional K8s manifests (Ingress, ExternalSecret, etc.)
```

- **`app.yaml`** is read by the ApplicationSet generator to create the ArgoCD Application.
- **`Chart.yaml`** wraps upstream Helm charts as dependencies (umbrella chart pattern).
- **`templates/`** contains cluster-specific resources like IngressRoutes, ExternalSecrets, VMAgent CRDs, and namespaces.

## Secrets Management

Secrets are managed through a layered approach:

| Layer | Tool | Purpose |
|---|---|---|
| **Source of truth** | [1Password](https://1password.com/) | Vault `homelab` stores all secrets |
| **Runtime sync** | [External Secrets Operator](https://external-secrets.io/) | Syncs 1Password items into K8s Secrets via `ClusterSecretStore` |
| **Git-safe secrets** | [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) | Encrypts the 1Password service account token for ESO bootstrap |
| **Bootstrap injection** | [1Password CLI](https://developer.1password.com/docs/cli/) (`op inject`) | Injects secrets during initial bootstrap |

**Flow:** 1Password → External Secrets Operator → Kubernetes Secrets

Applications that use ExternalSecrets: Democratic-CSI (TrueNAS driver config).

## Networking

| Component | Details |
|---|---|
| **CNI** | Cilium (kube-proxy replacement, Hubble enabled) |
| **Load Balancer** | MetalLB L2 mode, IP pool: `10.40.2.1–10.40.2.254` |
| **Ingress** | Traefik (in-cluster), bound to `10.40.2.1` via MetalLB |
| **Edge proxy** | Traefik (LXC on Proxmox), handles TLS termination via Cloudflare DNS challenge |
| **Base domain** | `the-lab.zone` with subdomains: `infra`, `platform`, `tooling`, `apps`, `k8s`, `web` |

### Traffic Flow

External requests hit the Traefik LXC container (`10.40.0.50`), which terminates TLS using Let's Encrypt certificates via Cloudflare DNS challenge. For in-cluster services, the LXC proxy forwards HTTP traffic to the in-cluster Traefik at `10.40.2.1` (MetalLB IP), which routes to the appropriate pod. For TrueNAS services, the LXC proxy forwards directly to the service IP on the `10.40.1.x` subnet.

### In-Cluster Service Endpoints

| Service | URL |
|---|---|
| ArgoCD | `argocd.platform.the-lab.zone` |
| Hubble UI | `hubble.platform.the-lab.zone` |
| Traefik Dashboard | `traefik.platform.the-lab.zone` |

> **Note:** TLS termination is handled by the Traefik LXC proxy. In-cluster traffic uses HTTP.

## Storage

| Component | Details |
|---|---|
| **CSI Driver** | Democratic-CSI with TrueNAS NFS backend |
| **Default StorageClass** | `truenas-nfs` (Retain policy, immediate binding) |

## Observability

Observability uses a split architecture: the **collection layer** runs inside the Kubernetes cluster, while the **storage and visualization layer** runs on TrueNAS.

### In-Cluster (monitoring chart)

| Component | Purpose |
|---|---|
| **VictoriaMetrics Operator** | Manages VMAgent, VMServiceScrape, VMNodeScrape CRDs; auto-converts Prometheus ServiceMonitor/PodMonitor |
| **VMAgent** | Scrapes all discovered targets and remote-writes metrics to TrueNAS VMsingle |
| **VictoriaLogs Collector** | DaemonSet that tails container logs from every node and ships them to TrueNAS VictoriaLogs |

### On TrueNAS (Docker containers)

| Component | Address | Purpose |
|---|---|---|
| **VMsingle** | `10.40.1.60:8428` | Metrics storage (receives remote-write from VMAgent) |
| **VictoriaLogs** | `10.40.1.60:9428` | Log storage (receives logs from collector) |
| **Grafana** | `10.40.1.50` | Dashboards & visualization |

Prometheus `ServiceMonitor` and `PodMonitor` CRDs are installed at wave 0 so all applications can expose metrics from the start. The VictoriaMetrics Operator auto-converts these into VMServiceScrape/VMPodScrape objects.

## CI / Linting

GitHub Actions run on every push and pull request to `main`:

| Workflow | Description |
|---|---|
| **yamllint** | Lints changed YAML files with `yamllint --strict` |
| **editorconfig** | Checks changed files against `.editorconfig` rules |
| **GitGuardian** | Scans for leaked secrets |

## Local Development

### Render all Helm templates

```bash
make template
```

Outputs rendered manifests to the `build/` directory.

### Validate manifests

```bash
make validate
```

Renders and validates all charts with [kubeconform](https://github.com/yannh/kubeconform) against Kubernetes and CRD schemas.

### Lint YAML files

```bash
make yamllint
```

Runs yamllint across `applicationsets/`, `bootstrap/`, `clusters/`, and `.github/`.

### Clean build artifacts

```bash
make clean
```

### Re-seal 1Password token

```bash
make bootstrap-seal-onepassword-local
```

Generates a new `SealedSecret` for the 1Password service account token using the cluster's Sealed Secrets key from 1Password.

## Prerequisites

| Tool | Purpose |
|---|---|
| `kubectl` | Kubernetes CLI |
| `helm` v3+ | Helm chart management |
| `op` (1Password CLI) | Secret injection during bootstrap |
| `kubeseal` | Seal secrets for Sealed Secrets |
| `kubeconform` | Manifest validation |
| `yamllint` | YAML linting |
| `openssl` / `ssh-keygen` | Key management for Sealed Secrets bootstrap |
