---
description: Snapshot de saúde do cluster — ArgoCD apps, pods com problema, PVCs, ExternalSecrets
agent: k8s-investigator
---

Faça um snapshot rápido de saúde do cluster. Colete:

1. **ArgoCD apps com problema:**
!`kubectl get applications -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' | grep -v "Synced.*Healthy"`

2. **Pods não Running/Completed:**
!`kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded' --no-headers 2>/dev/null | grep -v Completed`

3. **PVCs não Bound:**
!`kubectl get pvc -A --field-selector='status.phase!=Bound' --no-headers`

4. **ExternalSecrets com erro:**
!`kubectl get externalsecret -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].type,STATUS:.status.conditions[0].status' | grep -v "Ready.*True"`

Resumo em no máximo 10 linhas. Se tudo OK, diga isso.
