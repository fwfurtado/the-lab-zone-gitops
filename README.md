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
│  wave 1: cloudnative-pg, garage, metallb, sealed-secrets     │
│  wave 2: democratic-csi, external-secrets, traefik,          │
│          victoria-stack                                       │
│  wave 3: argocd, authentik                                   │
│  wave 4: gitea                                               │
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
│       ├── authentik/
│       ├── cilium/
│       ├── cloudnative-pg/
│       ├── democratic-csi/
│       ├── external-secrets/
│       ├── garage/
│       ├── gitea/
│       ├── metallb/
│       ├── prometheus-operator-crds/
│       ├── sealed-secrets/
│       ├── traefik/
│       └── victoria-stack/
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
| **Cilium** | `kube-system` | CNI plugin with Hubble observability UI |
| **Prometheus Operator CRDs** | `prometheus-operator-crds` | ServiceMonitor / PodMonitor CRDs for metrics |
| **CloudNative-PG** | `cloudnative-pg` | PostgreSQL operator for in-cluster databases |
| **Garage** | `garage` | S3-compatible distributed object storage + Web UI |
| **MetalLB** | `metallb-system` | Bare-metal LoadBalancer (L2 mode) |
| **Sealed Secrets** | `sealed-secrets` | Encrypt secrets for safe Git storage |
| **Democratic-CSI** | `democratic-csi` | CSI driver for TrueNAS NFS provisioning |
| **External Secrets** | `external-secrets` | Sync secrets from 1Password into Kubernetes |
| **Traefik** | `traefik` | Ingress controller & reverse proxy |
| **Victoria Metrics Stack** | `monitoring` | Metrics, logs, traces & Grafana dashboards |
| **ArgoCD** | `argocd` | GitOps continuous delivery |
| **Authentik** | `authentik` | Identity Provider (SSO/OAuth2/SAML) |
| **Gitea** | `gitea` | Self-hosted Git service with OAuth via Authentik |

## Sync Wave Order

Applications are deployed in a specific order using ArgoCD sync waves to respect dependencies:

| Wave | Applications | Purpose |
|---|---|---|
| **0** | Cilium, Prometheus Operator CRDs | Core networking & CRD foundations |
| **1** | CloudNative-PG, Garage, MetalLB, Sealed Secrets | Operators & infrastructure services |
| **2** | Democratic-CSI, External Secrets, Traefik, Victoria Stack | Storage, secrets, ingress & observability |
| **3** | ArgoCD, Authentik | GitOps platform & identity provider |
| **4** | Gitea | Applications depending on all infrastructure |

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
  syncWave: "3"
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
└── templates/        # Additional K8s manifests (Ingress, ExternalSecret, CNPG, etc.)
```

- **`app.yaml`** is read by the ApplicationSet generator to create the ArgoCD Application.
- **`Chart.yaml`** wraps upstream Helm charts as dependencies (umbrella chart pattern).
- **`templates/`** contains cluster-specific resources like Ingress rules, CNPG database clusters, ExternalSecrets, and namespaces.



## Secrets Management

Secrets are managed through a layered approach:

| Layer | Tool | Purpose |
|---|---|---|
| **Source of truth** | [1Password](https://1password.com/) | Vault `homelab` stores all secrets |
| **Runtime sync** | [External Secrets Operator](https://external-secrets.io/) | Syncs 1Password items into K8s Secrets via `ClusterSecretStore` |
| **Git-safe secrets** | [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) | Encrypts the 1Password service account token for ESO bootstrap |
| **Bootstrap injection** | [1Password CLI](https://developer.1password.com/docs/cli/) (`op inject`) | Injects secrets during initial bootstrap |

**Flow:** 1Password → External Secrets Operator → Kubernetes Secrets

Applications that use ExternalSecrets: Authentik, Garage, Gitea (OAuth), Democratic-CSI (TrueNAS config).

## Networking

| Component | Details |
|---|---|
| **CNI** | Cilium (kube-proxy replacement, Hubble enabled) |
| **Load Balancer** | MetalLB L2 mode, IP pool: `10.40.2.1–10.40.2.254` |
| **Ingress** | Traefik, bound to `10.40.2.1` via MetalLB |
| **Base domain** | `platform.the-lab.zone` |

### Service Endpoints

| Service | URL |
|---|---|
| ArgoCD | `argocd.platform.the-lab.zone` |
| Authentik | `auth.platform.the-lab.zone` |
| Gitea | `git.platform.the-lab.zone` |
| Garage | `garage.platform.the-lab.zone` |
| Grafana | `grafana.platform.the-lab.zone` |
| Victoria Metrics | `vms.platform.the-lab.zone` |
| Hubble UI | `hubble.platform.the-lab.zone` |
| Traefik Dashboard | `traefik.platform.the-lab.zone` |

> **Note:** TLS termination is handled externally (Traefik LXC proxy). In-cluster traffic uses HTTP.

## Storage

| Component | Details |
|---|---|
| **CSI Driver** | Democratic-CSI with TrueNAS NFS backend |
| **Storage Class** | `truenas-nfs` |
| **Databases** | CloudNative-PG (PostgreSQL) for Authentik (3 replicas, 5Gi) and Gitea (1 replica, 20Gi) |
| **Object Storage** | Garage (S3-compatible) |

## Observability

The **Victoria Metrics Stack** provides full observability:

| Component | Purpose |
|---|---|
| Victoria Metrics | Metrics collection & storage |
| Victoria Logs | Log aggregation |
| Victoria Traces | Distributed tracing (receives traces from Traefik) |
| Grafana | Dashboards & visualization |

Prometheus `ServiceMonitor` and `PodMonitor` CRDs are installed at wave 0 so all applications can expose metrics from the start.

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
