# Plano de Migracao de Storage: TrueNAS NFS -> Proxmox LVM

## Contexto

Todas as apps stateful do cluster Kubernetes (Talos Linux no Proxmox) usam a StorageClass `truenas-nfs` (Democratic-CSI, NFS via TrueNAS) como default. O Proxmox CSI ja esta deployado com a StorageClass `proxmox-lvm` (block storage, ext4, SSD, backend `local-ssd` lvmthin), porem nenhuma app a utiliza ainda. O objetivo eh migrar todos os PVCs de `truenas-nfs` para `proxmox-lvm`, eliminando a dependencia do TrueNAS para storage do cluster.

> **Nota sobre lvmthin**: O storage `local-ssd` no Proxmox eh do tipo lvmthin. O `fstype: ext4` no values.yaml esta correto -- ele define o filesystem criado dentro do LV, nao o tipo de backend. lvmthin suporta thin provisioning (overcommit de espaco), entao o espaco fisico real pode ser menor que a soma dos PVCs alocados. Monitorar uso real do thin pool eh importante.

## Inventario de PVCs a Migrar

| App | Namespace | Tamanho | Arquivo de Config |
|-----|-----------|---------|-------------------|
| VMSingle | monitoring | 50Gi | `wave-2-infra/monitoring/values.yaml` |
| VictoriaLogs | monitoring | 20Gi | `wave-2-infra/monitoring/values.yaml` |
| VictoriaTraces | monitoring | 10Gi | `wave-2-infra/monitoring/values.yaml` |
| Infisical PostgreSQL | infisical | 8Gi | `wave-2-infra/infisical/values.yaml` |
| Infisical Redis | infisical | 2Gi | `wave-2-infra/infisical/values.yaml` |
| CloudNativePG (3 instancias) | cloudnativepg | 3x 20Gi | `wave-4-platform/cloudnativepg/templates/cluster.yaml` |
| Valkey | valkey | 2Gi | `wave-4-platform/valkey/values.yaml` |
| MinIO | minio | 50Gi | `wave-4-platform/minio/values.yaml` |
| Zot | zot | 50Gi | `wave-4-platform/zot/values.yaml` |
| Grafana | grafana | 5Gi | `wave-4-platform/grafana/values.yaml` |

**Total: ~277Gi** (verificar espaco disponivel no `local-ssd` lvmthin do Proxmox)

## Diferencas Importantes entre as StorageClasses

| Aspecto | `truenas-nfs` | `proxmox-lvm` |
|---------|---------------|---------------|
| Protocolo | NFS (rede) | Block device (local) |
| Access Mode | ReadWriteMany | ReadWriteOnce |
| Volume Binding | Immediate | WaitForFirstConsumer |
| Filesystem | NFS | ext4 |
| Performance | Limitada por rede | SSD local (muito melhor) |
| Default | Sim | Nao |

## Estrategia de Migracao

**Abordagem: migracao app-por-app com downtime controlado por servico.**

Nao eh possivel alterar a `storageClass` de um PVC existente (campo imutavel). A migracao exige criar novos PVCs com `proxmox-lvm`, copiar os dados, e reconfigurar as apps.

---

### Pre-requisitos

#### 0. Criar usuario CSI no Proxmox

Executar no shell do Proxmox:

```bash
# Criar usuario
pveum user add kubernetes-csi@pve

# Criar role com permissoes para gerenciar discos
pveum role add CSI -privs "VM.Audit VM.Config.Disk Datastore.Allocate Datastore.AllocateSpace Datastore.Audit"

# Atribuir role ao usuario
pveum aclmod / -user kubernetes-csi@pve -role CSI

# Criar API token (sem privilege separation)
pveum user token add kubernetes-csi@pve csi -privsep 0
# -> Salvar o token_secret retornado no Infisical como parte do proxmox-csi-config
```

O secret `proxmox-csi-config` no Infisical deve conter um `config.yaml`:

```yaml
clusters:
  - url: https://<PROXMOX_IP>:8006/api2/json
    insecure: true
    token_id: "kubernetes-csi@pve!csi"
    token_secret: "<TOKEN_SECRET_DO_COMANDO_ACIMA>"
    region: homelab
```

#### 1. Adicionar labels de topologia nos nos do Kubernetes

O Proxmox CSI usa `local-ssd` lvmthin (storage local por no). Ele precisa dos labels de topologia para saber em qual host Proxmox provisionar o volume. **Sem esses labels, os PVCs ficarao Pending.**

Labels necessarios em cada no:

```
topology.kubernetes.io/region=<region-do-config-csi>   # ex: "homelab"
topology.kubernetes.io/zone=<nome-do-no-proxmox>       # ex: "pve"
```

> **Importante**: `region` nao eh um valor nativo do Proxmox. Eh um valor que voce define no `proxmox-csi-config` (campo `region` no config.yaml do Infisical) e deve ser **identico** ao label `topology.kubernetes.io/region` nos nos. O CSI usa esse match para associar nos K8s ao cluster Proxmox correto. Se ainda nao configurou o secret, escolha um nome (ex: `homelab`) e use o mesmo nos dois lugares.

Configurar via Talos machineconfig (para cada no):

```bash
talosctl patch machineconfig --nodes <NODE_IP> --patch '[
  {
    "op": "add",
    "path": "/machine/nodeLabels",
    "value": {
      "topology.kubernetes.io/region": "homelab",
      "topology.kubernetes.io/zone": "pve"
    }
  }
]'
```

> **Nota**: Se voce tem multiplos nos Proxmox (ex: `pve1`, `pve2`), cada VM K8s deve ter o `zone` correspondente ao host Proxmox onde ela roda.

Validar:

```bash
kubectl get nodes --show-labels | grep topology
```

#### 2. Verificar espaco no Proxmox

Confirmar que `local-ssd` (lvmthin) tem espaco suficiente. Com thin provisioning, o espaco alocado pode exceder o fisico, mas eh importante verificar o uso real:

```bash
# No shell do Proxmox
pvesm status
# ou
lvs -o lv_name,lv_size,vg_name
vgs -o vg_name,vg_free
```

#### 3. Backup completo via Velero

```bash
velero backup create pre-storage-migration --wait
```

#### 4. Trocar default StorageClass

`proxmox-lvm` vira default, `truenas-nfs` deixa de ser.

---

### Ordem de Migracao (por risco/criticidade)

**Grupo 1 -- Dados efemeros/regeneraveis (sem copia de dados necessaria)**
1. VictoriaMetrics (50Gi) -- metricas com retencao de 14d, pode reiniciar limpo
2. VictoriaLogs (20Gi) -- logs com retencao de 7d, pode reiniciar limpo
3. VictoriaTraces (10Gi) -- traces com retencao de 7d, pode reiniciar limpo
4. Grafana (5Gi) -- dashboards vem via ConfigMaps (sidecar), plugins re-baixados

**Grupo 2 -- Dados recriaveis mas que exigem migracao**
5. Zot (50Gi) -- imagens OCI podem ser re-sincronizadas, mas copia eh mais rapida
6. MinIO (50Gi) -- buckets com backups do Velero e dados do Forgejo

**Grupo 3 -- Dados criticos (exigem copia cuidadosa)**
7. Valkey (2Gi) -- cache/sessao, pode reiniciar limpo se aceitavel
8. Infisical Redis (2Gi) -- pode reiniciar limpo
9. Infisical PostgreSQL (8Gi) -- BD do Infisical, precisa de dump/restore
10. CloudNativePG (3x 20Gi) -- BD principal (Authelia, Forgejo), critico

---

### Procedimento por App

#### Para apps do Grupo 1 (dados efemeros):

```
1. Scale down a app (ou parar o pod)
2. Alterar storageClass no values.yaml para proxmox-lvm
3. Deletar o PVC antigo
4. ArgoCD sync (cria novo PVC com proxmox-lvm)
5. App inicia limpa e recomeca a coletar dados
6. Validar que a app esta funcionando
```

#### Para apps do Grupo 2 (migracao com dados):

```
1. Scale down a app
2. Criar PVC temporario com proxmox-lvm
3. Rodar Job de copia (pod com ambos PVCs montados, rsync/cp)
4. Alterar storageClass no values.yaml para proxmox-lvm
5. Deletar PVC antigo, renomear novo PVC (ou reconfigurar o claim name)
6. ArgoCD sync
7. Validar dados
```

#### Para CloudNativePG (Grupo 3):

```
1. pg_dumpall do cluster atual
2. Armazenar dump no MinIO (ja migrado neste ponto)
3. Alterar storageClass no cluster.yaml para proxmox-lvm
4. Deletar o Cluster CR (CloudNativePG recria com novo storage)
5. pg_restore dos dados
6. Recriar databases/users (authelia, forgejo) via migration-init-databases
7. Validar conectividade das apps dependentes
```

#### Para Infisical PostgreSQL:

```
1. pg_dump do banco infisicalDB
2. Scale down Infisical
3. Alterar storageClass no values.yaml para proxmox-lvm
4. Deletar PVC antigo, ArgoCD sync (recria com novo storage)
5. pg_restore do banco
6. Scale up e validar
```

---

### Alteracoes no GitOps

#### 1. Trocar default StorageClass

**`wave-2-infra/proxmox-csi/values.yaml`**: `defaultClass: true`
**`wave-2-infra/democratic-csi/values.yaml`**: `defaultClass: false`

#### 2. Atualizar storageClass em cada app

Todos os arquivos listados no inventario: trocar `truenas-nfs` -> `proxmox-lvm`

#### 3. (Opcional) Remover Democratic-CSI apos migracao completa

So depois de confirmar que nenhum PV/PVC ainda usa `truenas-nfs`.

---

### Makefile Targets (adicionar em `makefiles/migration.mk`)

Criar targets para automatizar a validacao:
- `migration-storage-check-space` -- verifica espaco no local-ssd (lvmthin)
- `migration-storage-backup` -- cria backup Velero pre-migracao
- `migration-storage-swap-default` -- troca default StorageClass
- `migration-storage-validate` -- lista todos PVCs e seus storageClasses

---

## Verificacao

Apos cada app migrada:
1. `kubectl get pvc -A` -- confirmar que PVC usa `proxmox-lvm`
2. `kubectl get pods -n <ns>` -- confirmar pods Running
3. Testar funcionalidade da app (UI, API, dados)
4. Monitorar metricas no Grafana por 24h

Apos migracao completa:
1. `kubectl get pvc -A -o custom-columns='NAME:.metadata.name,NS:.metadata.namespace,SC:.spec.storageClassName'` -- nenhum PVC com `truenas-nfs`
2. Rodar `make migration-validate-wave2 migration-validate-wave4`
3. Considerar remocao do Democratic-CSI

## Riscos e Mitigacoes

| Risco | Mitigacao |
|-------|----------|
| Espaco insuficiente no Proxmox | Verificar uso real do thin pool `local-ssd` antes de comecar |
| Thin pool cheio (lvmthin overcommit) | Monitorar uso real vs alocado; configurar alerta no Proxmox |
| Perda de dados no PostgreSQL | pg_dump antes de qualquer alteracao + backup Velero |
| MinIO com dados do Velero | Migrar MinIO antes de precisar de restore |
| `WaitForFirstConsumer` causa pods Pending | Labels de topologia nos nos + verificar scheduling |
| Sem labels de topologia | PVCs ficam Pending -- aplicar labels via talosctl antes de comecar |
| Downtime prolongado | Migrar uma app por vez, validar, seguir para proxima |
