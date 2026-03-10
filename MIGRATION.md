# Platform Cluster GitOps Migration Plan

## Contexto

Migração do repositório `fwfurtado/the-lab-zone-gitops` para uma arquitetura onde
o cluster de plataforma é a fonte de verdade para todos os serviços, eliminando LXCs
desnecessários e simplificando a stack.

### O que muda

| Antes | Depois |
|---|---|
| CoreDNS (LXC) | CoreDNS (Deployment no cluster) |
| Step-CA (LXC) | Eliminado — cert-manager + Cloudflare DNS-01 |
| Caddy (LXC) | Eliminado — Traefik faz TLS termination |
| Authelia (LXC) | Authelia (Helm no cluster) |
| Forgejo (LXC) | Forgejo (Helm no cluster) |
| Zot (LXC) | Zot (Helm no cluster) |
| PostgreSQL (LXC) | CloudNativePG (Operator no cluster) |
| Valkey (LXC) | Valkey (Helm no cluster) |
| Garage (LXC) | Garage (StatefulSet no cluster) |
| Grafana (LXC) | Grafana (Helm no cluster) |
| Traefik (HTTP only, sem TLS) | Traefik (TLS termination com cert-manager) |

### O que permanece fora do cluster

| Serviço | Motivo |
|---|---|
| Tailscale (LXC) | Backdoor de recuperação — não pode depender do cluster |
| Home Assistant OS | Máquina dedicada, automação local não deve depender do cluster |
| TrueNAS | Storage físico, consumido via Democratic CSI |

---

## Estrutura de diretórios alvo

```
clusters/
└── platform/
    ├── wave-0-cni/
    │   ├── cilium/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   └── values.yaml
    │   ├── metallb/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       ├── namespace.yaml
    │   │       └── ip-pool.yaml
    │   └── prometheus-operator-crds/
    │       ├── app.yaml
    │       └── Chart.yaml
    │
    ├── wave-1-tls/
    │   ├── cert-manager/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       ├── cloudflare-sealedsecret.yaml
    │   │       ├── cluster-issuer.yaml
    │   │       └── wildcards.yaml
    │   └── sealed-secrets/
    │       ├── app.yaml
    │       ├── Chart.yaml
    │       ├── values.yaml
    │       └── templates/
    │           ├── deployment.yaml
    │           └── service.yaml
    │
    ├── wave-2-infra/
    │   ├── coredns/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       ├── namespace.yaml
    │   │       └── zone-configmap.yaml
    │   ├── external-secrets/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       ├── cluster-secret-store.yaml
    │   │       └── onepassword-credentials-sealedsecret.yaml
    │   └── democratic-csi/
    │       ├── app.yaml
    │       ├── Chart.yaml
    │       ├── values.yaml
    │       └── templates/
    │           ├── namespace.yaml
    │           └── truenas-driver-config-external-secret.yaml
    │
    ├── wave-3-ingress/
    │   ├── traefik/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       ├── namespace.yaml
    │   │       ├── tls-store.yaml
    │   │       ├── middleware.yaml
    │   │       └── forgejo-ssh-ingressroutetcp.yaml
    │   ├── external-dns/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       └── tsig-sealedsecret.yaml
    │   └── velero/
    │       ├── app.yaml
    │       ├── Chart.yaml
    │       ├── values.yaml
    │       └── templates/
    │           └── garage-credentials-external-secret.yaml
    │
    ├── wave-4-platform/
    │   ├── cloudnativepg/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       └── cluster.yaml
    │   ├── valkey/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   └── values.yaml
    │   ├── garage/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       └── layout-job.yaml
    │   ├── authelia/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       ├── external-secret.yaml
    │   │       └── ingressroute.yaml
    │   ├── forgejo/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       ├── external-secret.yaml
    │   │       └── ingressroute.yaml
    │   ├── zot/
    │   │   ├── app.yaml
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       └── ingressroute.yaml
    │   └── grafana/
    │       ├── app.yaml
    │       ├── Chart.yaml
    │       ├── values.yaml
    │       └── templates/
    │           ├── external-secret.yaml
    │           └── ingressroute.yaml
    │
    └── wave-5-gitops/
        └── argocd/
            ├── app.yaml
            ├── Chart.yaml
            ├── values.yaml
            └── templates/
                ├── external-secret.yaml
                └── ingressroute.yaml
```

---

## Waves e dependências

```
Wave 0 — CNI e rede (sem dependências externas)
  ├── cilium
  ├── metallb
  └── prometheus-operator-crds

Wave 1 — TLS (depende de wave 0)
  ├── sealed-secrets
  └── cert-manager
       ├── ClusterIssuer (Cloudflare DNS-01)
       └── Certificates wildcard (*.infra, *.platform)
       NOTA: usa SealedSecret para o token da Cloudflare neste wave,
             migra para ExternalSecret após wave 2 subir

Wave 2 — Infra base (depende de wave 1)
  ├── coredns          → IP fixo: 10.40.2.2
  ├── external-secrets → ClusterSecretStore: 1Password
  └── democratic-csi   → StorageClass: truenas-nfs

Wave 3 — Ingress e backup (depende de wave 2)
  ├── traefik      → IP fixo: 10.40.2.1, TLS via wildcard secrets
  ├── external-dns → RFC2136 → CoreDNS + Cloudflare
  └── velero       → S3 backend: Garage

Wave 4 — Serviços de plataforma (depende de wave 3)
  ├── cloudnativepg  → Cluster Postgres de 3 instâncias
  ├── valkey         → usado pelo Authelia
  ├── garage         → S3 para Forgejo, Velero, assets
  ├── authelia       → depende de CloudNativePG + Valkey
  ├── forgejo        → depende de CloudNativePG + Garage
  ├── zot            → image registry
  └── grafana        → dashboards

Wave 5 — GitOps (depende de wave 4)
  └── argocd         → gerencia a si mesmo por último
```

---

## Implementação por wave

### Wave 0 — CNI e rede

#### metallb — adicionar pool de IPs fixos para infra

Adicionar um segundo `IPAddressPool` com `autoAssign: false` para os serviços de
infraestrutura crítica (CoreDNS e Traefik) que precisam de IPs fixos e previsíveis.
Os nodes dos outros clusters apontarão para esses IPs.

```yaml
# clusters/platform/wave-0-cni/metallb/templates/ip-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: platform-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.40.2.11-10.40.2.254
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: platform-infra-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.40.2.1-10.40.2.10
  autoAssign: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: platform-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - platform-pool
    - platform-infra-pool
```

---

### Wave 1 — TLS

#### cert-manager — novo componente

Substitui o Step-CA. Emite certificados via Cloudflare DNS-01 challenge.
Não precisa de infraestrutura externa para funcionar.

```yaml
# clusters/platform/wave-1-tls/cert-manager/Chart.yaml
apiVersion: v2
name: cert-manager
version: 0.0.0
dependencies:
  - name: cert-manager
    version: "1.17.0"
    repository: https://charts.jetstack.io
```

```yaml
# clusters/platform/wave-1-tls/cert-manager/values.yaml
cert-manager:
  crds:
    enabled: true
  serviceMonitor:
    enabled: true
  dns01RecursiveNameserversOnly: true
  dns01RecursiveNameservers: "1.1.1.1:53,1.0.0.1:53"
```

```yaml
# clusters/platform/wave-1-tls/cert-manager/app.yaml
app:
  name: cert-manager
  namespace: cert-manager
  syncWave: "1"
```

O token da Cloudflare precisa existir antes do ClusterIssuer. Como o External Secrets
ainda não está disponível no wave 1, usar SealedSecret gerado via:

```bash
# Gerar o SealedSecret do token da Cloudflare
CF_TOKEN=$(op read "op://development/Cloudflare/the-lab.zone")
kubectl -n cert-manager create secret generic cloudflare-api-token \
  --from-literal=api-token="$CF_TOKEN" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
  > clusters/platform/wave-1-tls/cert-manager/templates/cloudflare-sealedsecret.yaml
```

```yaml
# clusters/platform/wave-1-tls/cert-manager/templates/cluster-issuer.yaml
# sync-wave: "1" garante que sobe depois do cert-manager estar pronto
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  acme:
    email: fwfurtado@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-cloudflare-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

```yaml
# clusters/platform/wave-1-tls/cert-manager/templates/wildcards.yaml
# sync-wave: "2" garante que o ClusterIssuer já existe
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: infra-wildcard
  namespace: cert-manager
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  secretName: infra-wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
    - "*.infra.the-lab.zone"
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: platform-wildcard
  namespace: cert-manager
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  secretName: platform-wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
    - "*.platform.the-lab.zone"
```

Os Secrets dos wildcards precisam ser copiados para os namespaces que os consomem
(traefik, authelia, etc.). Usar o `reflector` ou `ClusterSecret` do cert-manager,
ou referenciar diretamente via `secretTemplate` no Certificate apontando para o
namespace correto. A opção mais simples para homelab é usar o
[kubernetes-reflector](https://github.com/EmberStack/kubernetes-reflector):

```yaml
# Adicionar annotation nos Certificates para replicar automaticamente
metadata:
  annotations:
    reflector.v1.k8s.emberstack.com/reflection-allowed: "true"
    reflector.v1.k8s.emberstack.com/reflection-auto-enabled: "true"
    reflector.v1.k8s.emberstack.com/reflection-auto-namespaces: "traefik,authelia,forgejo,argocd"
```

Alternativamente, adicionar o reflector como dependência do cert-manager no Chart.yaml.

---

### Wave 2 — Infra base

#### coredns — novo componente

Substitui o CoreDNS LXC. Roda como Deployment com IP fixo via MetalLB.
É o DNS autoritativo para `the-lab.zone` dentro da rede.

```yaml
# clusters/platform/wave-2-infra/coredns/Chart.yaml
apiVersion: v2
name: coredns
version: 0.0.0
dependencies:
  - name: coredns
    version: "1.39.1"
    repository: https://coredns.github.io/helm-charts
```

```yaml
# clusters/platform/wave-2-infra/coredns/values.yaml
coredns:
  replicaCount: 2

  service:
    type: LoadBalancer
    loadBalancerIP: "10.40.2.2"
    annotations:
      metallb.universe.tf/loadBalancerIPs: "10.40.2.2"
      metallb.universe.tf/address-pool: platform-infra-pool

  serviceMonitor:
    enabled: true

  # O Corefile é gerado a partir dos servers abaixo
  servers:
    # Zona autoritativa para the-lab.zone
    - zones:
        - zone: the-lab.zone.
      port: 53
      plugins:
        - name: errors
        - name: log
        - name: file
          parameters: /etc/coredns/zones/the-lab.zone
          configBlock: |-
            reload 30s
        # Habilita RFC2136 para o ExternalDNS atualizar registros
        - name: transfer
          configBlock: |-
            to *
    # Upstream para tudo fora de the-lab.zone
    - zones:
        - zone: .
      port: 53
      plugins:
        - name: errors
        - name: forward
          parameters: ". 1.1.1.1 1.0.0.1"
        - name: cache
          parameters: "30"
        - name: log

  # Monta o ConfigMap da zona como volume
  extraVolumes:
    - name: zone-file
      configMap:
        name: coredns-zone
  extraVolumeMounts:
    - name: zone-file
      mountPath: /etc/coredns/zones
```

```yaml
# clusters/platform/wave-2-infra/coredns/templates/zone-configmap.yaml
# Registros estáticos — infraestrutura física que nunca muda de IP.
# O ExternalDNS gerencia registros dinâmicos do cluster via RFC2136,
# mas não toca neste arquivo.
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-zone
  namespace: dns
data:
  the-lab.zone: |
    $ORIGIN the-lab.zone.
    $TTL 300

    @ IN SOA dns.the-lab.zone. admin.the-lab.zone. (
          2024010101 ; serial — incrementar a cada mudança
          3600       ; refresh
          900        ; retry
          604800     ; expire
          300 )      ; minimum

    ; Nameserver
    @    IN NS  dns.the-lab.zone.
    dns  IN A   10.40.2.2

    ; Infraestrutura física
    proxmox IN A 10.40.0.200
    nas     IN A 10.40.0.4
    ha      IN A 10.40.0.x   ; substituir pelo IP real do Home Assistant

    ; Wildcards para o cluster de plataforma
    ; O Traefik responde por todos os subdomínios via IngressRoute
    *.platform  IN A 10.40.2.1
    *.infra     IN A 10.40.2.1
```

```yaml
# clusters/platform/wave-2-infra/coredns/app.yaml
app:
  name: coredns
  namespace: dns
  syncWave: "2"
```

#### external-secrets — ajustes

Após o wave 2 subir, migrar o SealedSecret do token da Cloudflare para ExternalSecret.
Isso é feito substituindo o arquivo
`clusters/platform/wave-1-tls/cert-manager/templates/cloudflare-sealedsecret.yaml`
por um ExternalSecret e removendo o SealedSecret do repositório.

```yaml
# clusters/platform/wave-1-tls/cert-manager/templates/cloudflare-external-secret.yaml
# Substituir cloudflare-sealedsecret.yaml por este após ESO estar rodando
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: onepassword
    kind: ClusterSecretStore
  target:
    name: cloudflare-api-token
    creationPolicy: Owner
  data:
    - secretKey: api-token
      remoteRef:
        key: "Cloudflare/the-lab.zone"
```

---

### Wave 3 — Ingress e backup

#### traefik — mudanças significativas

O Traefik passa a fazer TLS termination usando os wildcards do cert-manager.
Remove a dependência do Caddy LXC completamente.

```yaml
# clusters/platform/wave-3-ingress/traefik/values.yaml
traefik:
  deployment:
    replicas: 2

  service:
    type: LoadBalancer
    annotations:
      metallb.universe.tf/loadBalancerIPs: "10.40.2.1"
      metallb.universe.tf/address-pool: platform-infra-pool

  ports:
    web:
      port: 8000
      exposedPort: 80
      # Redireciona HTTP para HTTPS
      redirectTo:
        port: websecure
    websecure:
      port: 8443
      exposedPort: 443
      tls:
        enabled: true
    # SSH passthrough para o Forgejo
    ssh:
      port: 2222
      exposedPort: 22
      protocol: TCP
      expose:
        default: true

  providers:
    kubernetesCRD:
      enabled: true
      allowCrossNamespace: true
    kubernetesIngress:
      enabled: true
      allowEmptyServices: true

  # Dashboard exposto via IngressRoute (ver templates/ingress.yaml)
  ingressRoute:
    dashboard:
      enabled: false  # gerenciado manualmente via template

  logs:
    general:
      level: INFO
      format: json
    access:
      enabled: true

  metrics:
    prometheus:
      service:
        enabled: true
      serviceMonitor:
        enabled: true

  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi
```

```yaml
# clusters/platform/wave-3-ingress/traefik/templates/tls-store.yaml
# TLSStore default — Traefik usa este certificado quando nenhum outro é especificado
apiVersion: traefik.io/v1alpha1
kind: TLSStore
metadata:
  name: default
  namespace: traefik
spec:
  defaultCertificate:
    secretName: platform-wildcard-tls
```

```yaml
# clusters/platform/wave-3-ingress/traefik/templates/middleware.yaml
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: default-headers
  namespace: traefik
spec:
  headers:
    browserXssFilter: true
    contentTypeNosniff: true
    frameDeny: true
    stsIncludeSubdomains: true
    stsPreload: true
    stsSeconds: 31536000
    customFrameOptionsValue: "SAMEORIGIN"
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authelia-forwardauth
  namespace: traefik
spec:
  forwardAuth:
    address: http://authelia.authelia.svc.cluster.local/api/verify?rd=https://auth.infra.the-lab.zone
    trustForwardHeader: true
    authResponseHeaders:
      - Remote-User
      - Remote-Groups
      - Remote-Name
      - Remote-Email
```

```yaml
# clusters/platform/wave-3-ingress/traefik/templates/forgejo-ssh-ingressroutetcp.yaml
# TCP routing para SSH do Forgejo — substitui o layer4 do Caddy
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: forgejo-ssh
  namespace: traefik
spec:
  entryPoints:
    - ssh
  routes:
    - match: HostSNI(`*`)
      services:
        - name: forgejo-ssh
          namespace: forgejo
          port: 22
```

#### external-dns — novo componente

Atualiza automaticamente o CoreDNS (via RFC2136) e a Cloudflare quando Services
ou IngressRoutes são criados no cluster.

```yaml
# clusters/platform/wave-3-ingress/external-dns/Chart.yaml
apiVersion: v2
name: external-dns
version: 0.0.0
dependencies:
  - name: external-dns
    version: "1.15.0"
    repository: https://kubernetes-sigs.github.io/external-dns
```

```yaml
# clusters/platform/wave-3-ingress/external-dns/values.yaml
external-dns:
  provider:
    name: cloudflare

  # Fontes que o ExternalDNS monitora
  sources:
    - service
    - ingress
    - traefik-proxy  # monitora IngressRoute do Traefik
    - crd            # monitora DNSEndpoint para registros manuais

  # Filtra apenas o domínio do homelab
  domainFilters:
    - the-lab.zone

  # Cloudflare como provider primário (registros públicos)
  env:
    - name: CF_API_TOKEN
      valueFrom:
        secretKeyRef:
          name: cloudflare-api-token
          key: api-token

  # RFC2136 como provider secundário (CoreDNS interno)
  # Requer webhook ou configuração de extraArgs dependendo da versão
  extraArgs:
    - --provider=cloudflare
    - --cloudflare-proxied=false
    # RFC2136 para CoreDNS interno
    - --rfc2136-host=10.40.2.2
    - --rfc2136-port=53
    - --rfc2136-zone=the-lab.zone
    - --rfc2136-tsig-keyname=externaldns-key
    - --rfc2136-tsig-secret-alg=hmac-sha256
    - --rfc2136-tsig-secret=$(TSIG_SECRET)

  serviceMonitor:
    enabled: true
```

```yaml
# clusters/platform/wave-3-ingress/external-dns/templates/tsig-sealedsecret.yaml
# Gerar via: kubectl create secret generic externaldns-tsig \
#   --from-literal=tsig-secret="$(openssl rand -base64 32)" \
#   --dry-run=client -o yaml | kubeseal --format yaml
# (substituir pelo SealedSecret gerado)
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: externaldns-tsig
  namespace: external-dns
spec:
  encryptedData:
    tsig-secret: <sealed-value>
  template:
    metadata:
      name: externaldns-tsig
      namespace: external-dns
```

```yaml
# clusters/platform/wave-3-ingress/external-dns/app.yaml
app:
  name: external-dns
  namespace: external-dns
  syncWave: "3"
```

#### velero — ajuste de backend

Migrar o backend S3 do Velero para o Garage que rodará dentro do cluster no wave 4.
No primeiro deploy, pode apontar temporariamente para o Garage externo se ainda existir.

```yaml
# clusters/platform/wave-3-ingress/velero/app.yaml
app:
  name: velero
  namespace: velero
  syncWave: "3"
```

---

### Wave 4 — Serviços de plataforma

#### cloudnativepg — novo componente

Operator que gerencia clusters Postgres. Precisa subir antes de Authelia e Forgejo.

```yaml
# clusters/platform/wave-4-platform/cloudnativepg/Chart.yaml
apiVersion: v2
name: cloudnativepg
version: 0.0.0
dependencies:
  - name: cloudnativepg
    version: "0.23.0"
    repository: https://cloudnative-pg.github.io/charts
```

```yaml
# clusters/platform/wave-4-platform/cloudnativepg/templates/cluster.yaml
# sync-wave: "1" garante que o operator sobe antes do Cluster
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: platform-postgres
  namespace: cloudnativepg
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  instances: 3

  storage:
    size: 20Gi
    storageClass: truenas-nfs

  monitoring:
    enablePodMonitor: true

  backup:
    barmanObjectStore:
      destinationPath: s3://postgres-backups
      endpointURL: http://garage.garage.svc.cluster.local:3900
      s3Credentials:
        accessKeyId:
          name: garage-postgres-credentials
          key: access-key
        secretAccessKey:
          name: garage-postgres-credentials
          key: secret-key
    retentionPolicy: "7d"
```

```yaml
# clusters/platform/wave-4-platform/cloudnativepg/app.yaml
app:
  name: cloudnativepg
  namespace: cloudnativepg
  syncWave: "4"
```

#### valkey — novo componente

Usado pelo Authelia para sessões e cache.

```yaml
# clusters/platform/wave-4-platform/valkey/Chart.yaml
apiVersion: v2
name: valkey
version: 0.0.0
dependencies:
  - name: valkey
    version: "2.2.2"
    repository: https://charts.bitnami.com/bitnami
```

```yaml
# clusters/platform/wave-4-platform/valkey/values.yaml
valkey:
  architecture: standalone

  auth:
    enabled: true
    existingSecret: valkey-credentials
    existingSecretPasswordKey: password

  master:
    persistence:
      enabled: true
      size: 2Gi
      storageClass: truenas-nfs
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi

  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
```

```yaml
# clusters/platform/wave-4-platform/valkey/app.yaml
app:
  name: valkey
  namespace: valkey
  syncWave: "4"
```

#### garage — novo componente

S3 compatível usado por Forgejo, Velero e assets estáticos.
O Garage precisa de configuração pós-deploy para definir o layout dos nós.

```yaml
# clusters/platform/wave-4-platform/garage/Chart.yaml
apiVersion: v2
name: garage
version: 0.0.0
dependencies:
  - name: garage
    version: "0.9.4"
    repository: https://garagehq.deuxfleurs.fr/_releases/charts
```

```yaml
# clusters/platform/wave-4-platform/garage/values.yaml
garage:
  replicaCount: 1  # single node para homelab

  service:
    type: LoadBalancer
    annotations:
      metallb.universe.tf/address-pool: platform-pool

  persistence:
    enabled: true
    size: 50Gi
    storageClass: truenas-nfs

  garage:
    replicationMode: "1"  # single node

  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
```

```yaml
# clusters/platform/wave-4-platform/garage/templates/layout-job.yaml
# Job que roda após o Garage subir para configurar o layout do nó
# Necessário porque o Garage precisa de "garage layout assign" após inicializar
apiVersion: batch/v1
kind: Job
metadata:
  name: garage-layout-init
  namespace: garage
  annotations:
    argocd.argoproj.io/sync-wave: "1"
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: garage-cli
          image: dxflrs/garage:v0.9.4
          command:
            - /bin/sh
            - -c
            - |
              NODE_ID=$(garage node id -q | head -1)
              garage layout assign -z dc1 -c 1G $NODE_ID
              garage layout apply --version 1
```

```yaml
# clusters/platform/wave-4-platform/garage/app.yaml
app:
  name: garage
  namespace: garage
  syncWave: "4"
```

#### authelia — migração do LXC

```yaml
# clusters/platform/wave-4-platform/authelia/Chart.yaml
apiVersion: v2
name: authelia
version: 0.0.0
dependencies:
  - name: authelia
    version: "0.10.5"
    repository: https://charts.authelia.com
```

```yaml
# clusters/platform/wave-4-platform/authelia/values.yaml
authelia:
  domain: the-lab.zone

  ingress:
    enabled: false  # gerenciado via IngressRoute no templates/

  storage:
    postgres:
      enabled: true
      host: platform-postgres-rw.cloudnativepg.svc.cluster.local
      port: 5432
      database: authelia
      username: authelia
      password:
        secret:
          name: authelia-db-credentials
          key: password

  session:
    redis:
      enabled: true
      host: valkey-master.valkey.svc.cluster.local
      port: 6379
      password:
        secret:
          name: valkey-credentials
          key: password

  serviceMonitor:
    enabled: true
```

```yaml
# clusters/platform/wave-4-platform/authelia/templates/ingressroute.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: authelia
  namespace: authelia
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`auth.infra.the-lab.zone`)
      kind: Rule
      services:
        - name: authelia
          port: 80
  tls:
    secretName: infra-wildcard-tls
```

```yaml
# clusters/platform/wave-4-platform/authelia/app.yaml
app:
  name: authelia
  namespace: authelia
  syncWave: "4"
```

#### forgejo — migração do LXC

```yaml
# clusters/platform/wave-4-platform/forgejo/Chart.yaml
apiVersion: v2
name: forgejo
version: 0.0.0
dependencies:
  - name: forgejo
    version: "10.1.0"
    repository: https://codeberg.org/forgejo-contrib/forgejo-helm
```

```yaml
# clusters/platform/wave-4-platform/forgejo/values.yaml
forgejo:
  # Desabilita o Postgres e Redis embutidos — usando CloudNativePG e Valkey
  postgresql-ha:
    enabled: false
  postgresql:
    enabled: false
  redis-cluster:
    enabled: false
  redis:
    enabled: false

  gitea:
    config:
      database:
        DB_TYPE: postgres
        HOST: platform-postgres-rw.cloudnativepg.svc.cluster.local:5432
        NAME: forgejo
        USER: forgejo
      cache:
        ADAPTER: redis
        HOST: redis://:$(VALKEY_PASSWORD)@valkey-master.valkey.svc.cluster.local:6379/0
      storage:
        STORAGE_TYPE: minio
        MINIO_ENDPOINT: garage.garage.svc.cluster.local:3900
        MINIO_BUCKET: forgejo
        MINIO_USE_SSL: false

  service:
    ssh:
      type: ClusterIP
      port: 22

  serviceMonitor:
    enabled: true
```

```yaml
# clusters/platform/wave-4-platform/forgejo/templates/ingressroute.yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: forgejo
  namespace: forgejo
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`git.infra.the-lab.zone`)
      kind: Rule
      services:
        - name: forgejo-http
          port: 3000
  tls:
    secretName: infra-wildcard-tls
```

```yaml
# clusters/platform/wave-4-platform/forgejo/app.yaml
app:
  name: forgejo
  namespace: forgejo
  syncWave: "4"
```

#### zot — migração do LXC

```yaml
# clusters/platform/wave-4-platform/zot/Chart.yaml
apiVersion: v2
name: zot
version: 0.0.0
dependencies:
  - name: zot
    version: "0.1.60"
    repository: https://zotregistry.dev/helm-charts
```

```yaml
# clusters/platform/wave-4-platform/zot/values.yaml
zot:
  replicaCount: 1

  persistence:
    enabled: true
    size: 50Gi
    storageClass: truenas-nfs

  serviceMonitor:
    enabled: true
```

```yaml
# clusters/platform/wave-4-platform/zot/templates/ingressroute.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: zot
  namespace: zot
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`registry.infra.the-lab.zone`)
      kind: Rule
      services:
        - name: zot
          port: 5000
  tls:
    secretName: infra-wildcard-tls
```

```yaml
# clusters/platform/wave-4-platform/zot/app.yaml
app:
  name: zot
  namespace: zot
  syncWave: "4"
```

#### grafana — migração do LXC

```yaml
# clusters/platform/wave-4-platform/grafana/Chart.yaml
apiVersion: v2
name: grafana
version: 0.0.0
dependencies:
  - name: grafana
    version: "8.8.2"
    repository: https://grafana.github.io/helm-charts
```

```yaml
# clusters/platform/wave-4-platform/grafana/values.yaml
grafana:
  serviceMonitor:
    enabled: true

  persistence:
    enabled: true
    size: 5Gi
    storageClass: truenas-nfs

  grafana.ini:
    server:
      root_url: https://grafana.infra.the-lab.zone
    auth:
      signout_redirect_url: https://auth.infra.the-lab.zone/logout
      oauth_auto_login: true
    auth.generic_oauth:
      enabled: true
      name: Authelia
      icon: signin
      client_id: grafana
      client_secret: $__env{GRAFANA_OAUTH_SECRET}
      scopes: openid profile email groups
      auth_url: https://auth.infra.the-lab.zone/api/oidc/authorization
      token_url: https://auth.infra.the-lab.zone/api/oidc/token
      api_url: https://auth.infra.the-lab.zone/api/oidc/userinfo
      role_attribute_path: contains(groups, 'admins') && 'Admin' || 'Viewer'
```

```yaml
# clusters/platform/wave-4-platform/grafana/templates/ingressroute.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: grafana
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`grafana.infra.the-lab.zone`)
      kind: Rule
      services:
        - name: grafana
          port: 80
  tls:
    secretName: infra-wildcard-tls
```

```yaml
# clusters/platform/wave-4-platform/grafana/app.yaml
app:
  name: grafana
  namespace: grafana
  syncWave: "4"
```

---

### Wave 5 — GitOps

#### argocd — ajustes

Migrar o Dex para usar Authelia como OIDC provider (que agora está no cluster).
Adicionar IngressRoute com TLS.

```yaml
# clusters/platform/wave-5-gitops/argocd/values.yaml
argo-cd:
  dex:
    enabled: true
  configs:
    params:
      server.insecure: true
      server.login.prompt.enabled: false
    cm:
      admin.enabled: false
      url: https://argocd.platform.the-lab.zone
      dex.config: |
        connectors:
          - type: oidc
            id: authelia
            name: Authelia
            config:
              issuer: https://auth.infra.the-lab.zone
              clientID: argocd
              clientSecret: $argocd-oidc:dex.authelia.clientSecret
              insecureEnableGroups: true
              scopes:
                - openid
                - profile
                - email
                - groups
    rbac:
      policy.default: role:readonly
      policy.csv: |
        g, sre, role:admin
      scopes: "[groups, email]"
```

```yaml
# clusters/platform/wave-5-gitops/argocd/templates/ingressroute.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`argocd.platform.the-lab.zone`)
      kind: Rule
      services:
        - name: argocd-server
          port: 80
  tls:
    secretName: platform-wildcard-tls
```

```yaml
# clusters/platform/wave-5-gitops/argocd/app.yaml
app:
  name: argocd
  namespace: argocd
  syncWave: "5"
  releaseName: argocd
```

---

## ApplicationSet

O ApplicationSet precisa ser atualizado para refletir a nova estrutura de diretórios
com os prefixos `wave-N-*`.

```yaml
# applicationsets/cluster-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-apps
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - matrix:
        generators:
          - clusters:
              selector:
                matchLabels:
                  lab.the-lab.zone/managed: "true"
          - git:
              repoURL: https://github.com/fwfurtado/the-lab-zone-gitops
              revision: main
              files:
                - path: "clusters/{{.name}}/**/app.yaml"
  template:
    metadata:
      name: "{{.name}}-{{.app.name}}"
      labels:
        lab.the-lab.zone/cluster: "{{.name}}"
        lab.the-lab.zone/component: "{{.app.name}}"
      annotations:
        argocd.argoproj.io/sync-wave: "{{.app.syncWave}}"
    spec:
      project: "{{ default \"default\" .app.project }}"
      ignoreDifferences:
        - group: external-secrets.io
          kind: ExternalSecret
          jsonPointers:
            - /status
        - group: apps
          kind: StatefulSet
          jqPathExpressions:
            - .spec.volumeClaimTemplates[].status
            - .spec.volumeClaimTemplates[].apiVersion
            - .spec.volumeClaimTemplates[].kind
        # cert-manager atualiza o status dos Certificates
        - group: cert-manager.io
          kind: Certificate
          jsonPointers:
            - /status
      source:
        repoURL: https://github.com/fwfurtado/the-lab-zone-gitops
        targetRevision: main
        path: "{{.path.path}}"
        helm:
          releaseName: "{{ default .app.name .app.releaseName }}"
      destination:
        server: "{{.server}}"
        namespace: "{{.app.namespace}}"
      syncPolicy:
        automated:
          selfHeal: true
          prune: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
```

---

## Ajustes no repositório IaC

No repositório `fwfurtado/the-lab-zone-iac`, remover os stacks dos LXCs que foram
migrados para o cluster:

```bash
# Stacks a remover após migração confirmada
stacks/caddy.yaml
stacks/technitium.yaml  # se estava sendo usado como CoreDNS
# Manter:
stacks/tailscale.yaml
```

Atualizar o patch do Talos para que os nodes apontem para o novo CoreDNS no cluster:

```yaml
# Em stacks/platform.yaml, adicionar nos talos_config_patches:
- |
  machine:
    network:
      nameservers:
        - 10.40.2.2  # CoreDNS no cluster
        - 1.1.1.1    # fallback durante bootstrap
```

---

## Ordem de execução da migração

### Fase 1 — Preparação (sem downtime)

1. Criar a nova estrutura de diretórios no repositório gitops
2. Manter os componentes existentes funcionando em paralelo
3. Gerar os SealedSecrets necessários (Cloudflare token, TSIG key)
4. Fazer o PR com toda a estrutura nova, sem remover os componentes antigos ainda

### Fase 2 — Deploy dos waves 0-3

1. Aplicar wave 0 (MetalLB com novo pool de IPs)
2. Aplicar wave 1 (cert-manager + wildcards)
3. Validar que os certificados foram emitidos: `kubectl get certificates -A`
4. Aplicar wave 2 (CoreDNS com IP `10.40.2.2`)
5. Validar resolução DNS: `dig @10.40.2.2 argocd.platform.the-lab.zone`
6. Aplicar wave 3 (Traefik com TLS + ExternalDNS)
7. Validar acesso HTTPS: `curl -v https://argocd.platform.the-lab.zone`

### Fase 3 — Deploy wave 4

1. Aplicar CloudNativePG e aguardar cluster Postgres estar `Ready`
2. Criar databases e usuários para cada app (Authelia, Forgejo)
3. Aplicar Valkey e Garage
4. Aplicar Authelia, Forgejo, Zot, Grafana
5. Validar cada serviço via HTTPS

### Fase 4 — Cutover e limpeza

1. Atualizar DNS dos nodes Talos para `10.40.2.2` via patch do Talos
2. Desligar LXCs migrados um a um, validando após cada remoção
3. Remover stacks do repositório IaC
4. Remover componentes antigos do repositório gitops (traefik sem TLS, etc.)

---

## Checklist de validação

```
Wave 0
  [ ] Cilium pods Running
  [ ] MetalLB speaker pods Running
  [ ] IPAddressPool platform-infra-pool criado

Wave 1
  [ ] cert-manager pods Running
  [ ] ClusterIssuer letsencrypt-cloudflare Ready
  [ ] Certificate infra-wildcard Ready
  [ ] Certificate platform-wildcard Ready
  [ ] Sealed Secrets controller Running

Wave 2
  [ ] CoreDNS pods Running (2 réplicas)
  [ ] CoreDNS acessível em 10.40.2.2:53
  [ ] dig @10.40.2.2 nas.infra.the-lab.zone retorna 10.40.0.4
  [ ] dig @10.40.2.2 argocd.platform.the-lab.zone retorna 10.40.2.1
  [ ] External Secrets operator Running
  [ ] ClusterSecretStore onepassword Ready
  [ ] Democratic CSI pods Running

Wave 3
  [ ] Traefik pods Running
  [ ] Traefik acessível em 10.40.2.1:443
  [ ] curl -v https://argocd.platform.the-lab.zone retorna 200
  [ ] ExternalDNS pods Running
  [ ] Registros sendo criados na Cloudflare
  [ ] Velero pods Running

Wave 4
  [ ] CloudNativePG operator Running
  [ ] Cluster platform-postgres com 3 instâncias Ready
  [ ] Valkey pod Running
  [ ] Garage pod Running e layout configurado
  [ ] Authelia acessível em https://auth.infra.the-lab.zone
  [ ] Forgejo acessível em https://git.infra.the-lab.zone
  [ ] Zot acessível em https://registry.infra.the-lab.zone
  [ ] Grafana acessível em https://grafana.infra.the-lab.zone

Wave 5
  [ ] ArgoCD acessível em https://argocd.platform.the-lab.zone
  [ ] Login via Authelia funcionando
  [ ] Todos os apps em Synced/Healthy
```
