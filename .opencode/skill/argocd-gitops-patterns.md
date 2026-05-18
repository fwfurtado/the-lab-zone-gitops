---
name: argocd-gitops-patterns
description: ArgoCD ApplicationSet patterns, sync waves, and kubectl-based operations for the-lab-zone-gitops
---

## ApplicationSet — como funciona

O `applicationsets/cluster-apps.yaml` usa matrix generator:
1. **Cluster generator**: clusters com label `lab.the-lab.zone/managed: "true"`
2. **Git file generator**: arquivos `clusters/<cluster-name>/**/app.yaml`

Cada `app.yaml` gera um ArgoCD Application com:
- `name`: `<cluster-name>-<app.name>`
- `syncWave`: de `app.yaml` → annotation `argocd.argoproj.io/sync-wave`
- `releaseName`: `app.releaseName` (ou `app.name` se não especificado)
- Helm umbrella chart no path do diretório
- Automated sync: `selfHeal: true`, `prune: true`, `CreateNamespace=true`, `ServerSideApply=true`

## Estrutura obrigatória por app

```
clusters/platform/<wave-N-category>/<app-name>/
├── app.yaml        # metadados para o ApplicationSet
├── Chart.yaml      # umbrella chart com dependências
├── Chart.lock      # lock de dependências (commitar)
├── values.yaml     # overrides de values
└── templates/      # recursos extras (IngressRoute, ExternalSecret, etc.)
```

`app.yaml` mínimo:
```yaml
app:
  name: my-app
  namespace: my-app
  syncWave: "2"
  # releaseName: my-app  # opcional, default = name
  # project: default     # opcional, default = default
```

## Waves e dependências

| Wave | Conteúdo | Deps |
|---|---|---|
| 0 | Cilium, MetalLB | nenhuma |
| 1 | cert-manager, prometheus-crds, reflector, sealed-secrets, infisical-secrets-op | wave 0 |
| 2 | Infra: CoreDNS, Proxmox CSI, ESO, monitoring, argo-workflows, external-postgres | wave 1 |
| 3 | Infisical (secrets store) | ESO (wave 2) |
| 4 | Traefik, external-dns | MetalLB (wave 0), cert-manager (wave 1) |
| 5 | Platform: Authelia, Forgejo, Grafana, Valkey, Coder, Zot, Velero, OpenClaw, Rustdesk | Infisical (wave 3), Traefik (wave 4) |
| 6 | ArgoCD | Traefik (wave 4), Infisical (wave 3) |

## ignoreDifferences global (no ApplicationSet)

Já configurado globalmente — não precisa repetir por app:
- `ExternalSecret` status
- `StatefulSet` volumeClaimTemplates status/apiVersion/kind
- `Certificate` status

## Operações ArgoCD via kubectl (sem argocd CLI)

```bash
# Listar todas as applications
kubectl get applications -n argocd

# Status resumido
kubectl get applications -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

# Ver detalhes de uma app (sync status, condições, operationState)
kubectl get application <name> -n argocd -o yaml

# Mensagem de erro do último sync
kubectl get application <name> -n argocd \
  -o jsonpath='{.status.operationState.message}{"\n"}'

# Ver resources gerenciados pela app
kubectl get application <name> -n argocd \
  -o jsonpath='{range .status.resources[*]}{.kind}/{.name} [{.namespace}] → {.health.status}{"\n"}{end}'

# Hard refresh (força re-fetch do repo, sem sync)
kubectl annotate application <name> -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

# Trigger sync manual (equivale a argocd app sync)
kubectl patch application <name> -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Ver hooks em execução
kubectl get jobs -n <namespace>  # hooks rodam como Jobs no namespace da app

# Ver diff (requer argocd CLI — sem alternativa via kubectl puro)
# Alternativa: make template && kubectl diff -f build/<app>.yaml
```

## Padrões de sync wave dentro de um chart

Para dependências dentro do mesmo chart, use annotations nos templates:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # ExternalSecret antes do Deployment
```

Ordem típica:
- `-1`: Namespace, ServiceAccount, RBAC (se necessário antes de outros recursos)
- `0`: ExternalSecret, SealedSecret (secrets precisam existir antes dos pods)
- `1`: ClusterIssuer, Certificate (TLS antes de IngressRoute)
- `2`: Deployment/StatefulSet, IngressRoute

## Adicionando nova app

1. Criar diretório em `clusters/platform/wave-N-<category>/<app-name>/`
2. Criar `app.yaml`, `Chart.yaml`, `values.yaml`
3. `helm dependency build clusters/platform/.../` para gerar `Chart.lock`
4. `make template` para verificar rendering
5. `make validate` para kubeconform
6. Commit + push → ArgoCD detecta automaticamente via file generator

## Secrets pattern

Todo secret deve vir de:
1. **ExternalSecret** → ClusterSecretStore `infisical` → Infisical (preferido)
2. **SealedSecret** → apenas para bootstrap ou quando ESO ainda não está disponível

Nunca commitar secrets em texto puro. O GitGuardian CI vai barrar.

Padrão de path no Infisical:
```
/<namespace>/<key-name>
/<namespace>/<sub-system>/<key-name>
```

Ex: `/argocd/oidc-client-secret`, `/database/authelia/password`
