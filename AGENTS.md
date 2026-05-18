# the-lab-zone-gitops — Agent Instructions

## Stack

| Camada | Tecnologia |
|---|---|
| OS | Talos Linux (sem SSH nos nós) |
| GitOps | ArgoCD wave-based, ApplicationSet matrix cluster×git |
| CNI | Cilium 1.19 (kube-proxy replacement, Hubble) |
| Ingress | Traefik + MetalLB L2 (`10.40.2.1`) |
| TLS | cert-manager + Cloudflare DNS challenge + Reflector |
| Secrets | ESO → ClusterSecretStore `infisical` + SealedSecrets (bootstrap) |
| Storage | Proxmox CSI `proxmox-lvm` (RWO, WaitForFirstConsumer, ext4) |
| Observability | VictoriaMetrics Operator (VMSingle, VMAgent, VLogs, VTraces) + Grafana |
| Auth | Authelia OIDC (`auth.infra.the-lab.zone`) |
| DNS | CoreDNS in-cluster (`10.40.2.2`), zona `the-lab.zone` |

## Estrutura do repo

```
clusters/platform/
  wave-0-cni/       — Cilium, MetalLB
  wave-1-operators/ — cert-manager, prometheus-crds, reflector, sealed-secrets, infisical-op
  wave-2-infra/     — CoreDNS, Proxmox CSI, ESO, monitoring, argo-workflows
  wave-3-secrets/   — Infisical
  wave-4-edge/      — Traefik, external-dns
  wave-5-platform/  — Authelia, Forgejo, Grafana, Valkey, Coder, Zot, Velero, OpenClaw
  wave-6-gitops/    — ArgoCD
applicationsets/    — ApplicationSet (matrix generator)
bootstrap/          — bootstrap inicial (root.yaml, repo-secret, infisical-secrets)
makefiles/          — targets modulares
```

## Convenções

- Cada app: `app.yaml` + `Chart.yaml` (umbrella) + `values.yaml` + `templates/`
- ArgoCD sem CLI instalado — usar exclusivamente `kubectl`
- Secrets sempre via ExternalSecret → ClusterSecretStore `infisical` (nunca texto puro)
- SealedSecrets apenas para bootstrap (infisical-credentials, proxmox-csi-config)
- `make template` renderiza todos os charts em `build/`
- `make validate` valida com kubeconform (inclui CRD schemas de MetalLB e ESO)
- `make yamllint` lint de YAML

## Domínios

| Subdomínio | Uso |
|---|---|
| `*.infra.the-lab.zone` | Serviços de infra (Proxmox, NAS, Infisical, Authelia, Forgejo, Zot, Grafana) |
| `*.platform.the-lab.zone` | Serviços de plataforma (ArgoCD, Coder, Argo Workflows, OpenClaw) |

## Agentes disponíveis

| Agente | Ativação | Uso |
|---|---|---|
| `@infra-reviewer` | `/review` ou menção direta | Revisar manifests, segurança, observability |
| `@k8s-investigator` | `/investigate <sintoma>` | Investigar problemas no cluster |

## Slash commands

| Comando | Descrição |
|---|---|
| `/review` | Revisa o diff atual com `@infra-reviewer` |
| `/validate <app>` | Helm lint + template + kubeconform para um chart |
| `/investigate <sintoma>` | Aciona `@k8s-investigator` com o sintoma |
| `/status` | Snapshot rápido de saúde do cluster |

## Importante

- Talos não tem shell nos nós — não sugira `ssh node` ou `kubectl exec node`
- ArgoCD sem CLI — operações via `kubectl get/patch/annotate application -n argocd`
- `prune: true` ativo — recursos removidos do Git são deletados do cluster
- MetalLB pool `platform-infra-pool` (`.1–.10`) é `autoAssign: false` — IPs fixos por annotation
- Reflector replica TLS secrets entre namespaces — não criar secrets TLS manualmente
