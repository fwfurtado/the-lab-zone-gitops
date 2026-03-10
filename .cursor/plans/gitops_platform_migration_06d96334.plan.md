---
name: GitOps Platform Migration
overview: Migrate the GitOps repository from a flat directory structure to a wave-based architecture, replacing LXC services (CoreDNS, Step-CA, Caddy, Authelia, Forgejo, Zot, PostgreSQL, Valkey, Garage, Grafana) with in-cluster Kubernetes deployments managed by ArgoCD.
todos:
  - id: phase-0-prereqs
    content: "Phase 0: Create 1Password items (Authelia, Valkey, Forgejo, OIDC clients, JWK), generate Cloudflare SealedSecret, validate cluster state, confirm HA IP, document Zot/Talos registry config"
    status: completed
  - id: phase-1-restructure
    content: "Phase 1: Atomic commit -- move all components into wave-N dirs, update syncWaves, add cert-manager Cloudflare DNS-01 + wildcards + reflector, add CoreDNS/ExternalDNS/wave-4 components, modify Traefik for TLS, add complete Authelia config with OIDC clients"
    status: completed
  - id: phase-2-wave-deploy
    content: "Phase 2: Wave-by-wave validation -- wave 0 (CNI/MetalLB pools), wave 1 (certs issued, secrets replicated), wave 2 (CoreDNS at 10.40.2.2, ESO healthy), wave 3 (Traefik HTTPS, ExternalDNS Cloudflare), wave 4 (create DBs/buckets, init services), wave 5 (ArgoCD OIDC login)"
    status: completed
  - id: phase-3-dns-cutover
    content: "Phase 3: Rolling Talos machine config patches (one node at a time) to switch nameservers to [10.40.2.2, 1.1.1.1], validate each node's DNS before proceeding"
    status: completed
  - id: phase-4-decommission
    content: "Phase 4: Decommission LXCs in order (Caddy, Step-CA, Grafana, Valkey, PostgreSQL, Authelia, Forgejo, Zot, CoreDNS, Garage), update Velero S3 to in-cluster Garage, remove IaC stacks"
    status: completed
isProject: false
---

# GitOps Platform Migration Plan

## Current State vs Target State

### Directory Structure Change

All components move from `clusters/platform/<name>/` to `clusters/platform/wave-N-<category>/<name>/`.
The [ApplicationSet](applicationsets/cluster-apps.yaml) glob `clusters/{{.name}}/**/app.yaml` already supports nested directories, so no changes to the glob pattern are needed.

**CRITICAL**: The directory rename must be atomic per component (remove old path + add new path in the same commit) because the ApplicationSet generates Application names as `{{.name}}-{{.app.name}}`. Two paths producing the same app name would conflict.

### Sync Wave Renumbering


| Component                | Current Wave | Target Wave | Notes                                                |
| ------------------------ | ------------ | ----------- | ---------------------------------------------------- |
| cilium                   | 0            | 0           | No change                                            |
| prometheus-operator-crds | 0            | 0           | No change                                            |
| metallb                  | 1            | 0           | Move earlier                                         |
| sealed-secrets           | 1            | 1           | No change                                            |
| cert-manager             | 2            | 1           | Move earlier, replace Step-CA with Cloudflare DNS-01 |
| external-secrets         | 2            | 2           | No change                                            |
| democratic-csi           | 2            | 2           | No change                                            |
| monitoring               | 2            | 2           | No change (not in MIGRATION.md, keeping at wave 2)   |
| coredns                  | NEW          | 2           | New component                                        |
| traefik                  | 2            | 3           | Move later, add TLS termination                      |
| velero                   | 2            | 3           | Move later                                           |
| external-dns             | NEW          | 3           | New component (Cloudflare only)                      |
| cloudnativepg            | NEW          | 4           | New component                                        |
| valkey                   | NEW          | 4           | New component                                        |
| garage                   | NEW          | 4           | New component                                        |
| authelia                 | NEW          | 4           | New component                                        |
| forgejo                  | NEW          | 4           | New component                                        |
| zot                      | NEW          | 4           | New component                                        |
| grafana                  | NEW          | 4           | New component                                        |
| argocd                   | 3            | 5           | Move to last wave                                    |


---

## Identified Risks

### Risk 1: Split-horizon DNS without RFC2136

- **Problem**: CoreDNS `file` plugin is read-only. MIGRATION.md references RFC2136 for ExternalDNS -> CoreDNS, but CoreDNS has no built-in RFC2136 receiver. Also, ExternalDNS only supports one provider per instance.
- **Resolution**: Split-horizon works naturally via wildcards without RFC2136. CoreDNS serves `*.platform.the-lab.zone` and `*.infra.the-lab.zone` as static A records pointing to `10.40.2.1` (Traefik). This covers 100% of cluster services because every service uses one of these two subdomains. ExternalDNS writes only to Cloudflare for external access. Internal traffic resolves at CoreDNS and never leaves the network.

```
Internal resolution (host on 10.40.0.0/21):
  query -> CoreDNS (10.40.2.2)
        -> forgejo.infra.the-lab.zone -> *.infra -> 10.40.2.1

External resolution (host outside network):
  query -> Cloudflare
        -> forgejo.infra.the-lab.zone -> A 10.40.2.1
```

- **Edge case**: Third-level subdomains (e.g., `api.forgejo.infra.the-lab.zone`) are not covered by `*.infra` wildcard. Add manually to zone ConfigMap if ever needed (unlikely in homelab).
- **File changes**: No `tsig-sealedsecret.yaml`. No `transfer` plugin in CoreDNS. ExternalDNS is Cloudflare-only with no RFC2136 `extraArgs`. CoreDNS zone ConfigMap has static records for physical infra + wildcards for cluster services.

### Risk 2: Velero S3 backend points to external Garage (wave 3) but Garage is wave 4

- **Impact**: During the transition, Velero needs a working S3 backend.
- **Mitigation**: Keep Velero pointing to the external Garage LXC (`10.40.1.11:3900`) during waves 0-4. Update Velero's `s3Url` to the in-cluster Garage only after wave 4 is validated. Do NOT decommission the Garage LXC until Velero is confirmed working with the new backend.

### Risk 3: CloudNativePG backup references Garage (both wave 4)

- **Impact**: If `Cluster` CRD is created before Garage pod is running, backup configuration may fail validation.
- **Mitigation**: Deploy CNPG Cluster initially without barman backup config. Add backup configuration after Garage is confirmed running and buckets are created.

### Risk 4: Cross-namespace TLS secret sharing

- **Impact**: cert-manager creates wildcard TLS secrets in `cert-manager` namespace. IngressRoutes in `authelia`, `forgejo`, `zot`, `grafana`, `argocd` namespaces reference these secrets by name but they don't exist there.
- **Mitigation**: Deploy [kubernetes-reflector](https://github.com/EmberStack/kubernetes-reflector) as part of wave 1. Add reflector annotations to Certificate resources to auto-replicate secrets to consuming namespaces (`traefik,authelia,forgejo,argocd,zot,grafana`).

### Risk 5: Authelia requires complete configuration

- **Problem**: The MIGRATION.md Authelia values.yaml was a skeleton. Authelia requires OIDC provider config (clients for ArgoCD, Grafana, Forgejo), access control rules, authentication backend, session config, storage config, notification provider, HMAC secret, and JWK for signing OIDC tokens.
- **Resolution**: Complete Authelia values.yaml provided by user, including:
  - File-based authentication backend with bcrypt passwords
  - Access control: bypass for auth.infra, two_factor for argocd.platform (SRE group), one_factor for `*.platform` and `*.infra`
  - Session via Valkey (`valkey-master.valkey.svc.cluster.local`)
  - Storage via CloudNativePG (`platform-postgres-rw.cloudnativepg.svc.cluster.local`)
  - Filesystem notifier (no SMTP for homelab)
  - OIDC clients: `argocd`, `grafana`, `forgejo` with RS256 JWK signing
  - All secrets from 1Password via ExternalSecret (`authelia-secrets` + `authelia-oidc-jwks`)
- **1Password items needed**: Authelia Postgres password, Valkey password, OIDC hmac-secret, OIDC jwt-secret, OIDC JWK private key (RSA 4096 PEM), 3x OIDC client secrets (ArgoCD, Grafana, Forgejo)

### Risk 6: Zot registry mirror cutover

- **Impact**: Talos nodes may be configured to use the Zot LXC as a container registry mirror. Changing Zot's IP/endpoint will break image pulls.
- **Mitigation**: After Zot is running in-cluster with an IngressRoute, run `make zot-sync` pointing to the new endpoint. Update Talos machine config to point to the new registry endpoint only after `zot-sync` completes. Keep Zot LXC running until all nodes are confirmed using the new endpoint.

### Risk 7: DNS cutover briefly breaks resolution

- **Impact**: When Talos nodes switch from LXC CoreDNS (`10.40.1.82`) to in-cluster CoreDNS (`10.40.2.2`), there's a brief window where DNS may not resolve.
- **Mitigation**: Apply Talos machine config patches one node at a time (rolling). Include `1.1.1.1` as fallback nameserver. Validate each node before proceeding to the next.

### Risk 8: Monitoring remote-write target

- **Impact**: The monitoring stack writes to `10.40.1.60:8428` (VictoriaMetrics on TrueNAS). These IPs are referenced directly.
- **Mitigation**: No action needed -- these IPs remain stable (TrueNAS stays). Just verify connectivity after DNS cutover.

---

## Phase 0 -- Prerequisites (no data migration)

All services start fresh in the cluster. No `pg_dump`, `gitea dump`, or Grafana export needed.

### 1Password Items to Create

Items that already exist (no action):

- `Cloudflare/the-lab.zone` at `op://development/Cloudflare/the-lab.zone`
- `Velero Garage S3` with `access-key-id` and `secret-access-key`
- `1Password SDK SA` credential (for SealedSecret)
- `Argo CD` with `client-secret` (for Dex OIDC)

New items to create in vault `homelab`:

- `Authelia Postgres` -- field: `password` (`openssl rand -hex 32`)
- `Forgejo Postgres` -- field: `password` (`openssl rand -hex 32`)
- `Valkey` -- field: `password` (`openssl rand -hex 32`)
- `Authelia OIDC` -- fields: `hmac-secret` + `jwt-secret` (each `openssl rand -hex 32`)
- `Authelia OIDC JWK` -- field: `private key` (RSA 4096 PEM via `openssl genrsa 4096`)
- `ArgoCD Authelia OAuth` -- field: `client-secret` (`openssl rand -hex 32`, must match existing `Argo CD/client-secret` or update both)
- `Grafana Authelia OAuth` -- field: `client-secret` (`openssl rand -hex 32`)
- `Forgejo Authelia OAuth` -- field: `client-secret` (`openssl rand -hex 32`)

### SealedSecret Generation

Before ESO is available (wave 2), two SealedSecrets are needed:

- **Cloudflare API token** for cert-manager (wave 1) -- generated via `op read` + `kubeseal`
- **1Password credentials** for external-secrets (wave 2) -- already exists in repo at [onepassword-credentials-sealedsecret.yaml](clusters/platform/external-secrets/templates/onepassword-credentials-sealedsecret.yaml)

### Pre-flight Validations

- `op whoami` -- 1Password CLI authenticated
- `kubeseal --fetch-cert` -- sealed-secrets controller reachable
- `kubectl get nodes` -- cluster access confirmed
- All current ArgoCD apps Synced/Healthy
- Confirm Home Assistant IP for the DNS zone file (placeholder `10.40.0.x`)
- Document Zot LXC registry mirror config: `talosctl get machineconfig -o yaml | grep -A5 registries`

### Wave 4 Post-Deploy Initialization

After wave 4 deploys, these steps complete the fresh setup:

- **CloudNativePG**: `kubectl exec` on primary pod to `CREATE DATABASE`/`CREATE USER` for `authelia` and `forgejo` (passwords from 1Password items created above)
- **Garage**: Layout assign runs automatically (PostSync Job). Then `kubectl exec` to `garage bucket create forgejo`, `velero`, `postgres-backups`
- **Authelia**: Auto-creates schema on first start. User defined in `userDatabase` values (bcrypt hash in values.yaml)
- **Forgejo**: Deploy with `INSTALL_LOCK=true`. Auto-creates schema on first start
- **Grafana**: Starts empty. Datasources configured via values.yaml. Dashboards imported via UI or provisioned later
- **Zot**: Starts empty. Populate via `make zot-sync` pointing to new endpoint before Talos registry mirror cutover

---

## Phase 1 -- Repository Restructuring

Single atomic commit that:

1. Moves all existing components into wave directories
2. Updates all `app.yaml` files with new syncWave numbers
3. Modifies cert-manager (remove step-issuer, add Cloudflare DNS-01 + ClusterIssuer + Certificates)
4. Adds kubernetes-reflector to wave-1-tls
5. Modifies MetalLB IP pool (split into platform-pool + platform-infra-pool)
6. Modifies Traefik (add TLS termination, HTTPS redirect, authelia middleware, SSH passthrough)
7. Adds all new wave 2 components (coredns)
8. Adds all new wave 3 components (external-dns)
9. Adds all new wave 4 components (cloudnativepg, valkey, garage, authelia, forgejo, zot, grafana)
10. Moves ArgoCD to wave 5, adds IngressRoute with TLS
11. Updates ApplicationSet with cert-manager ignoreDifferences

### Key files to modify (existing)

- [metallb/app.yaml](clusters/platform/metallb/app.yaml): syncWave "1" -> "0"
- [metallb/templates/ip-pool.yaml](clusters/platform/metallb/templates/ip-pool.yaml): split into two pools
- [cert-manager/Chart.yaml](clusters/platform/cert-manager/Chart.yaml): remove step-issuer dependency
- [cert-manager/values.yaml](clusters/platform/cert-manager/values.yaml): Cloudflare DNS-01 config
- [cert-manager/app.yaml](clusters/platform/cert-manager/app.yaml): syncWave "2" -> "1"
- [cert-manager/templates/external-secrets.yaml](clusters/platform/cert-manager/templates/external-secrets.yaml): REMOVE (step-ca provisioner password)
- [traefik/values.yaml](clusters/platform/traefik/values.yaml): TLS termination, replicas, SSH port
- [traefik/templates/middleware.yaml](clusters/platform/traefik/templates/middleware.yaml): add authelia forwardauth
- [traefik/app.yaml](clusters/platform/traefik/app.yaml): syncWave "2" -> "3"
- [velero/app.yaml](clusters/platform/velero/app.yaml): syncWave "2" -> "3"
- [argocd/app.yaml](clusters/platform/argocd/app.yaml): syncWave "3" -> "5"
- [argocd/templates/ingress.yaml](clusters/platform/argocd/templates/ingress.yaml): add TLS secretName
- [applicationsets/cluster-apps.yaml](applicationsets/cluster-apps.yaml): add cert-manager ignoreDifferences

### New files to create (~50+ files across 9 new components + templates)

All wave 4 components with complete Chart.yaml, values.yaml, app.yaml, and templates/ directories.

---

## Phase 2 -- Deploy Wave by Wave

ArgoCD's automated sync with the ApplicationSet handles deployment automatically once the commit hits `main`. The wave ordering is controlled by `argocd.argoproj.io/sync-wave` annotations.

For each wave:

1. Verify all apps in the wave reach Synced/Healthy
2. Run specific validation commands
3. Confirm before proceeding (ArgoCD will auto-sync, but we validate between waves)

**Wave 0**: Cilium, MetalLB (new IP pools), prometheus-operator-crds
**Wave 1**: cert-manager (Cloudflare DNS-01 + wildcards), sealed-secrets, kubernetes-reflector
**Wave 2**: CoreDNS (new, IP 10.40.2.2), external-secrets, democratic-csi, monitoring
**Wave 3**: Traefik (TLS termination), external-dns (Cloudflare only), velero
**Wave 4**: cloudnativepg, valkey, garage, authelia, forgejo, zot, grafana
**Wave 5**: ArgoCD (self-manages last)

---

## Phase 3 -- DNS Cutover

1. Validate in-cluster CoreDNS is serving correctly: `dig @10.40.2.2 nas.the-lab.zone`
2. Apply Talos machine config patch (one node at a time) to set nameservers to `[10.40.2.2, 1.1.1.1]`
3. Validate each node's DNS resolution after patch
4. After all nodes are patched, verify cluster-wide DNS resolution
5. Keep CoreDNS LXC running as a passive fallback for 48h

---

## Phase 4 -- LXC Decommissioning

Since all services start fresh (no data migration), decommissioning is straightforward. Order (safest first):

1. **Caddy** -- already replaced by Traefik TLS termination
2. **Step-CA** -- already replaced by cert-manager + Let's Encrypt
3. **Grafana** -- after in-cluster Grafana confirmed accessible
4. **Valkey** -- after Authelia confirmed using in-cluster Valkey
5. **PostgreSQL** -- after Authelia + Forgejo confirmed working with CloudNativePG
6. **Authelia** -- after in-cluster Authelia verified with OIDC for ArgoCD + Grafana
7. **Forgejo** -- after in-cluster Forgejo confirmed accessible (repos start fresh)
8. **Zot** -- after `make zot-sync` completes and Talos registry mirrors updated
9. **CoreDNS** -- after 48h with in-cluster CoreDNS + all Talos patches confirmed
10. **Garage** -- after Velero S3 backend switched to in-cluster Garage and verified

Each decommission: stop LXC -> validate services -> wait 24h -> remove from IaC repo.
**Never decommission**: Tailscale LXC (backdoor recovery).
