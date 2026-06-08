# PRD Tecnico: ToolHive

## 1. Resumo

Este PRD define a implantacao do ToolHive no cluster Kubernetes GitOps do The Lab Zone, dentro da wave de AI.

O objetivo e entregar uma camada governada para execucao, publicacao e consumo de servidores MCP, usando o ToolHive Kubernetes Operator e os charts oficiais da Stacklok. ToolHive deve complementar os gateways ja existentes na wave de AI, sem assumir responsabilidades de roteamento de modelos ou Knowledge RAG.

Responsabilidades por sistema:

| Responsabilidade | Sistema |
|---|---|
| AI model gateway, roteamento multi-provider, fallback, virtual keys, quotas e custos | LiteLLM |
| Knowledge RAG, ingestao, retrieval vetorial/grafo e API/UI RAG | LightRAG |
| Vector database | Qdrant |
| Knowledge graph database | Neo4j |
| Tool gateway, MCP runtime em Kubernetes, catalogo/governanca MCP e endpoints governados para agentes | ToolHive |
| Tool gateway e runtime MCP ja implantado para avaliacao/uso inicial | Obot |

ToolHive nao substitui LiteLLM, LightRAG, Qdrant ou Neo4j. ToolHive deve ser implantado como runtime e plano de governanca MCP, com integracao futura com agentes e clientes que precisam consumir ferramentas aprovadas.

Decisoes iniciais propostas:

- ToolHive deve ser implantado em `clusters/platform/wave-6-ai/toolhive/`.
- A aplicacao deve usar um umbrella chart local.
- O umbrella chart deve declarar dependencias para os charts oficiais OCI da Stacklok:
  - `oci://ghcr.io/stacklok/toolhive/toolhive-operator-crds`
  - `oci://ghcr.io/stacklok/toolhive/toolhive-operator`
- A versao inicial proposta deve seguir a release estavel mais recente validada no momento da implementacao. Em 2026-06-08, a release upstream observada e `v0.29.1`, publicada em 2026-06-04.
- A versao final do chart e das imagens deve ser fixada no `Chart.yaml` e no `values.yaml`; nao usar `latest`.
- O namespace do operator deve ser `toolhive-system`, conforme documentacao oficial.
- O runtime/workloads MCP devem usar namespace dedicado `toolhive-mcp`.
- A sync wave deve ser `6`.
- O operator deve iniciar em modo `namespace`, limitado ao namespace `toolhive-mcp`.
- CRDs devem ser gerenciadas pelo chart oficial de CRDs, nao por manifest copiado manualmente.
- Recursos ToolHive devem ser expostos por Traefik ja no MVP.
- Endpoints MCP expostos no MVP nao devem usar `forwardAuth` do Authelia; o acesso deve ficar limitado a rede interna/Tailscale.
- Autenticacao OIDC nativa no ToolHive deve ser tratada como fase 2, usando Authelia como provider OIDC.
- Endpoints expostos devem ficar acessiveis somente pela rede interna/Tailscale no MVP.
- MCP servers iniciais devem ser gerenciados no mesmo app/chart `toolhive`, sem app separado no MVP.
- Secrets devem usar External Secrets Operator com `ClusterSecretStore` `infisical`.
- Observabilidade deve usar VictoriaMetrics/Grafana via metricas Prometheus e/ou OpenTelemetry quando suportado pelo chart/CRDs.
- Audit logs devem ficar habilitados no MVP se o chart/operador suportar configuracao direta sem backend externo adicional.

## 2. Fontes oficiais usadas

- Repositorio oficial: `https://github.com/stacklok/toolhive`
- Documentacao oficial: `https://docs.stacklok.com/`
- Guia Kubernetes Operator: `https://docs.stacklok.com/toolhive/guides-k8s`
- Deploy do operator: `https://docs.stacklok.com/toolhive/guides-k8s/deploy-operator`
- Referencia de CRDs: `https://docs.stacklok.com/toolhive/reference/crds`
- Telemetria e metricas: `https://docs.stacklok.com/toolhive/guides-k8s/telemetry-and-metrics`
- Audit logging: `https://docs.stacklok.com/toolhive/guides-k8s/logging`

## 3. Objetivos

### 3.1 Objetivos de produto

- Centralizar a execucao governada de servidores MCP usados por agentes e IDEs.
- Reduzir uso de MCPs locais nao governados em maquinas de desenvolvimento.
- Permitir que clientes como Claude Code, Codex CLI, OpenCode, VS Code, Zed e agentes internos consumam ferramentas aprovadas.
- Fornecer um caminho Kubernetes-native para publicar ferramentas internas com isolamento por container.
- Permitir catalogo e agrupamento de ferramentas por finalidade, risco e publico consumidor.
- Preparar a plataforma para Virtual MCP Servers, permitindo expor um unico endpoint MCP composto por multiplos backends.
- Manter rastreabilidade operacional de execucao, logs, metricas e auditoria de ferramentas.

### 3.2 Objetivos tecnicos

- Implantar ToolHive como workload Kubernetes gerenciado por ArgoCD.
- Usar apenas charts oficiais da Stacklok como dependencias do umbrella chart local.
- Fixar versoes do chart e imagens.
- Instalar e manter CRDs ToolHive via chart oficial.
- Habilitar o operator no namespace `toolhive-system`.
- Criar namespace `toolhive-mcp` para MCP workloads.
- Configurar RBAC de menor privilegio viavel no MVP.
- Configurar resources, probes e limites iniciais para operator e workloads MCP.
- Integrar logs e metricas com a stack de observabilidade existente.
- Definir padrao GitOps para `MCPServer`, `MCPRemoteProxy`, `MCPServerEntry`, `MCPGroup`, `MCPToolConfig`, `MCPTelemetryConfig` e `VirtualMCPServer`.
- Documentar o contrato de consumo para clientes MCP.

## 4. Fora de escopo

- Migrar roteamento de modelos do LiteLLM para ToolHive.
- Substituir Obot automaticamente antes de uma avaliacao comparativa.
- Expor qualquer servidor MCP publico na internet.
- Permitir que usuarios criem servidores MCP arbitrarios fora de GitOps.
- Armazenar chaves ou tokens em texto puro no Git.
- Criar todos os MCP servers possiveis no MVP.
- Habilitar multi-tenancy completa por usuario/equipe no MVP.
- Automatizar approval workflow de novos MCP servers no MVP.
- Deploy de Stacklok Enterprise.
- Usar SSH nos nos Talos para troubleshooting.

## 5. Arquitetura alvo

### 5.1 Componentes

| Componente | Funcao | Namespace proposto |
|---|---|---|
| ToolHive Operator CRDs | Define APIs Kubernetes do ToolHive | cluster-scoped |
| ToolHive Operator | Reconcilia CRs e cria workloads MCP | `toolhive-system` |
| MCP workloads | Servidores MCP containerizados e proxies | `toolhive-mcp` |
| Virtual MCP Server | Endpoint agregado de multiplos MCP backends | `toolhive-mcp` |
| Registry Server | Catalogo de MCP servers aprovados, se habilitado | `toolhive-mcp` ou `toolhive-system` |
| Traefik IngressRoute | Exposicao HTTPS de endpoints MCP/portal/gateway | `toolhive-mcp` |
| ESO/Infisical | Secrets para auth, tokens e backends | namespaces consumidores |
| VictoriaMetrics/Grafana | Observabilidade | `monitoring`/stack existente |

### 5.2 Fluxo esperado

1. ArgoCD sincroniza o umbrella chart `toolhive`.
2. O umbrella chart instala/atualiza CRDs oficiais.
3. O umbrella chart instala o ToolHive Operator.
4. O chart local cria namespace, ExternalSecrets e recursos auxiliares da plataforma.
5. Recursos MCP sao adicionados por GitOps em templates locais ou apps dedicados.
6. O operator reconcilia `MCPServer`, `MCPRemoteProxy`, `MCPGroup` e `VirtualMCPServer`.
7. Clientes MCP acessam endpoints internos ou expostos via Traefik, conforme politica de autenticacao.

## 6. Kubernetes e GitOps

### 6.1 Localizacao

ToolHive deve ser adicionado em:

```text
clusters/platform/wave-6-ai/toolhive/
```

Estrutura esperada:

```text
toolhive/
  app.yaml
  Chart.yaml
  values.yaml
  templates/
    external-secret.yaml
    ingressroute.yaml
    namespace-mcp.yaml
    telemetry.yaml
    mcp-groups.yaml
    mcp-tool-configs.yaml
    virtual-mcp-server.yaml
```

Nem todos os templates precisam existir no primeiro commit. O MVP deve incluir apenas os recursos necessarios para boot seguro e validacao funcional.

### 6.2 ArgoCD

`app.yaml` proposto:

```yaml
app:
  name: toolhive
  namespace: toolhive-system
  syncWave: "6"
```

Requisitos:

- ArgoCD deve renderizar o umbrella chart com `--include-crds` quando aplicavel ao padrao do repositorio.
- A remocao do app deve ser tratada com cuidado porque `prune: true` pode remover recursos ToolHive gerenciados pelo Git.
- CRDs devem usar politica de retencao do chart oficial quando disponivel, para evitar delecao acidental de CRs.
- Caso o chart oficial de CRDs nao funcione corretamente como dependencia Helm no fluxo atual, a implementacao deve dividir em dois apps GitOps:
  - `toolhive-crds`, wave `6`, sync antes do operator.
  - `toolhive`, wave `6`, operator e recursos de runtime.

### 6.3 Umbrella chart

`Chart.yaml` alvo:

```yaml
apiVersion: v2
name: toolhive
description: ToolHive MCP platform for The Lab Zone
type: application
version: 0.1.0
appVersion: "v0.29.1"
dependencies:
  - name: toolhive-operator-crds
    alias: operatorCrds
    version: "0.29.1"
    repository: oci://ghcr.io/stacklok/toolhive
  - name: toolhive-operator
    alias: operator
    version: "0.29.1"
    repository: oci://ghcr.io/stacklok/toolhive
```

Notas:

- A versao `0.29.1` deve ser confirmada com `helm show chart` antes da implementacao.
- Se o chart usar prefixo `v` na versao Helm, usar exatamente o formato publicado.
- `appVersion` deve acompanhar a imagem ToolHive fixada.
- Dependencias devem ser atualizadas com o fluxo ja usado no repo para charts OCI.

## 7. Configuracao proposta

### 7.1 Operator

Configuracao inicial proposta:

| Item | Valor proposto |
|---|---|
| Namespace | `toolhive-system` |
| Replicas | `1` no MVP |
| RBAC | `namespace` |
| Allowed namespaces | `toolhive-mcp` |
| Runner image | `ghcr.io/stacklok/toolhive:v0.29.1` |
| Resources request | `100m`, `256Mi` |
| Resources limit | `500m`, `1Gi` |
| Ingress nativo | desabilitado |

Justificativa:

- O modo `namespace` reduz blast radius no MVP.
- Modo `namespace` significa que o operator so pode criar e reconciliar workloads ToolHive nos namespaces permitidos, inicialmente `toolhive-mcp`.
- Modo `cluster` significa que o operator pode criar e reconciliar workloads ToolHive em qualquer namespace do cluster; isso e util quando times/apps diferentes vao hospedar MCPs nos seus proprios namespaces, mas aumenta o escopo de permissao do operator.
- O MCP Kubernetes readonly ainda pode consultar o cluster inteiro mesmo com o operator em modo `namespace`, desde que o MCP server use uma ServiceAccount propria com `ClusterRole` readonly. O escopo do operator e o escopo da ferramenta Kubernetes sao decisoes separadas.
- Uma replica e suficiente para validacao inicial.
- O namespace separado evita misturar operator e MCP workloads.
- O operator pode ser movido para modo `cluster` depois, se houver necessidade real de MCPs por namespace de aplicacao.

### 7.2 MCP runtime

Configuracao inicial proposta:

| Item | Valor proposto |
|---|---|
| Namespace | `toolhive-mcp` |
| Pod Security Admission | `baseline` enforce, `restricted` audit/warn |
| StorageClass | `proxmox-lvm` quando houver PVC |
| Resources default | request `50m/128Mi`, limit `500m/512Mi` |
| NetworkPolicy | fora do bloqueio inicial; adicionar em fase futura |
| Egress externo | permitido no MVP para simplificar `Fetch/GoFetch`; restringir em fase futura |

### 7.3 Endpoints

Host proposto:

```text
toolhive.platform.the-lab.zone
```

Requisitos:

- Endpoints HTTP expostos devem usar Traefik `IngressRoute`.
- TLS deve usar `platform-wildcard-tls` replicado por Reflector.
- O MVP deve expor ToolHive por Traefik desde o inicio.
- A exposicao externa deve ser limitada a rede interna/Tailscale, conforme padrao dos apps de plataforma.
- O endpoint nao deve ficar publico na internet no MVP.
- ToolHive nao deve expor uma UI no MVP; `https://toolhive.platform.the-lab.zone` e um endpoint MCP, nao uma pagina web.
- O endpoint principal para clientes MCP deve ser `https://toolhive.platform.the-lab.zone/mcp`.
- Endpoints operacionais esperados no vMCP incluem `/health`, `/ping`, `/status`, `/metrics` e `/api/backends/health`.

## 8. Autenticacao e autorizacao

Decisao MVP:

- Endpoints ToolHive expostos por Traefik nao devem usar middleware `forwardAuth` do Authelia.
- O `VirtualMCPServer` inicial deve usar `incomingAuth.type: anonymous`.
- A protecao do MVP depende de exposicao somente por rede interna/Tailscale.
- O middleware `forwardAuth` do Traefik/Authelia foi removido porque clientes MCP como Zed, Claude Code, Codex CLI e OpenCode nao lidam bem com fluxo browser/redirect HTML no endpoint MCP.

Fase 2:

- Habilitar autenticacao OIDC nativa do ToolHive/MCP no `VirtualMCPServer`, usando Authelia como provider OIDC.
- Criar client OIDC dedicado para ToolHive no Authelia.
- Gerenciar client secret e demais secrets por ESO/Infisical.
- Trocar `incomingAuth.type: anonymous` por configuracao OIDC nativa suportada pelos CRDs ToolHive.
- Validar login/token flow em clientes MCP alvo antes de tornar autenticacao obrigatoria para todos os consumidores.

Recomendacao inicial:

- Para qualquer endpoint MCP exposto fora da rede interna/Tailscale, exigir autenticacao OIDC nativa no ToolHive.
- Para servidores MCP com capacidade mutante, exigir autorizacao explicita por usuario/grupo ou webhook antes de expor a agentes.
- Segredos de backend devem ser injetados por ESO, com tokens por servidor/ferramenta quando necessario.

## 9. Secrets

Secrets devem ser gerenciados via External Secrets Operator usando `ClusterSecretStore` `infisical`.

Paths propostos:

| Uso | Infisical path |
|---|---|
| OIDC client secret, se Authelia/OIDC for habilitado | `/toolhive/oidc-client-secret` |
| Gateway/session secret, se requerido pelo chart | `/toolhive/session-secret` |
| Webhook auth secret, se usado | `/toolhive/webhook-auth-secret` |
| Token para MCP Git/Forgejo | `/toolhive/mcp/forgejo/token` |
| Token para MCP Grafana | `/toolhive/mcp/grafana/token` |
| Token de acesso Kubernetes, se nao usar ServiceAccount dedicado | `/toolhive/mcp/kubernetes/token` |

Requisitos:

- Nenhum token de MCP server deve aparecer em `values.yaml`.
- MCP servers que acessam Kubernetes devem preferir ServiceAccount dedicada e RBAC minimo.
- MCP servers que acessam APIs externas devem receber secrets por ExternalSecret local ao namespace `toolhive-mcp`.

## 10. MCP servers iniciais

### 10.1 MVP recomendado

| MCP server | Tipo | Finalidade | Risco | Status |
|---|---|---|---|---|
| Stacklok Docs Search | remoto/local | Consulta a docs ToolHive/Stacklok | baixo | obrigatorio no MVP |
| Fetch/GoFetch | local | Fetch HTTP livre no MVP | medio | obrigatorio no MVP |
| Kubernetes readonly | local | Investigacao readonly do cluster inteiro via API Kubernetes | alto | obrigatorio no MVP |
| Grafana readonly | remoto/local | Consulta dashboards/metricas | medio | obrigatorio no MVP |
| Forgejo readonly | remoto/local | Consulta repos/issues/repos | medio | fora do MVP |
| Filesystem | local | Acesso a documentos controlados | alto | fora do MVP |

Fetch/GoFetch deve ficar sem allowlist no MVP. A implementacao deve deixar a estrutura de allowlist documentada em comentario no `values.yaml` ou no recurso `MCPServer`, para habilitacao futura sem redesenhar o chart.

### 10.2 Fora do MVP

- MCP servers com escrita em Kubernetes.
- MCP servers com acesso amplo a filesystem.
- MCP servers com acesso a secrets.
- MCP servers que executam comandos arbitrarios.
- MCP servers que fazem deploy, delete ou patch sem approval externo.

## 11. Virtual MCP Server

Um Virtual MCP Server e um endpoint MCP agregado. Em vez de cada cliente configurar varios servidores MCP separados, o ToolHive pode publicar um unico endpoint que combina backends como docs/search, fetch, Kubernetes readonly e Grafana readonly. Ele tambem permite aplicar configuracao comum, filtragem de tools e politicas de acesso no ponto de entrada.

Analogia pratica: `MCPServer` e um servidor/ferramenta individual; `VirtualMCPServer` e uma fachada/gateway que agrupa varios `MCPServer` e entrega um endpoint unico para os clientes.

O MVP deve incluir um Virtual MCP Server unico para consumidores internos:

```text
https://toolhive.platform.the-lab.zone/mcp/lab-tools
```

Composicao inicial proposta:

- Documentacao Stacklok/ToolHive.
- Fetch/GoFetch sem allowlist no MVP.
- Kubernetes readonly com escopo de leitura no cluster inteiro.
- Grafana readonly.

Requisitos:

- Usar `MCPGroup` para agrupar MCP servers por dominio.
- Usar `MCPToolConfig` para filtrar/renomear ferramentas perigosas ou ruidosas.
- Nao expor ferramentas mutantes no Virtual MCP Server inicial.
- Documentar nomes finais de tools aceitas por clientes.

## 12. Observabilidade

Requisitos MVP:

- Logs do operator acessiveis via `kubectl -n toolhive-system logs`.
- Logs dos workloads MCP acessiveis via `kubectl -n toolhive-mcp logs`.
- Metricas Prometheus habilitadas quando suportadas oficialmente.
- `ServiceMonitor` criado se o chart ou workloads expuserem endpoint Prometheus estavel.
- Telemetria OpenTelemetry deve ser considerada para VTraces se o operator suportar exportador OTLP sem componentes adicionais.
- Dashboards Grafana podem ser fase posterior, mas labels e metricas precisam nascer consistentes.

Sinais minimos:

- Status de reconciliacao do operator.
- Pods MCP criados, prontos e reiniciando.
- Latencia e erro por endpoint MCP.
- Taxa de chamadas por servidor/tool quando disponivel.
- Eventos de autorizacao negada.

## 13. Audit logging

Requisitos MVP:

- Habilitar formato de log estruturado quando suportado.
- Registrar criacao/atualizacao/remocao de MCP workloads via operator.
- Registrar chamadas a endpoints MCP, pelo menos em nivel de gateway/proxy quando suportado.
- Evitar registrar payloads sensiveis, tokens, headers de autorizacao ou secrets.
- Direcionar logs para o pipeline existente de VLogs se a stack ja coletar stdout de pods.

Decisao:

- Audit logging completo deve ser tratado como requisito de hardening.
- O MVP pode ser aceito com logs operacionais basicos de pods/operator, deixando auditoria completa de acesso/uso MCP para uma fase seguinte.
- Logs basicos do operator, gateway/proxy e MCP workloads continuam obrigatorios no MVP.

Fase futura:

- Armazenamento dedicado de audit logs.
- Retencao explicita por classe de evento.
- Alertas para ferramentas mutantes, falhas de autorizacao e acesso fora do padrao.

## 14. Seguranca

Requisitos:

- Nao executar workloads privilegiados no MVP.
- Habilitar Pod Security Admission `baseline` no namespace `toolhive-mcp`, mantendo `restricted` em audit/warn.
- ToolHive v0.29.1 gera o proxy runner sem todos os campos exigidos por PSA `restricted`; migrar `enforce` para `restricted` deve ser reavaliado quando o upstream permitir configurar `seccompProfile` e `capabilities.drop` no proxy runner gerado.
- Usar imagens fixadas por tag.
- Preferir imagens upstream oficiais ou mantidas por projetos confiaveis.
- Definir requests/limits para todos os MCP workloads.
- Bloquear ferramentas mutantes por padrao.
- Usar RBAC Kubernetes readonly para MCP Kubernetes inicial.
- Separar secrets por MCP server.
- Nao compartilhar secrets de administracao entre servidores MCP.
- Revisar cada novo MCP server em PR antes de merge.

Questoes de seguranca a decidir antes da implementacao:

- Nenhuma questao aberta de seguranca bloqueia o PRD.
- O MCP Kubernetes readonly nao deve receber permissao `get/list/watch` em `secrets` no MVP.
- Kubernetes RBAC nao oferece uma permissao forte de `list metadata-only` para Secrets em clientes genericos; liberar `list secrets` pode permitir retorno de `data`.
- Acesso metadata-only a Secrets deve ser reavaliado em fase futura se o MCP server ou uma camada proxy suportar ferramenta especifica que remova `data`/`stringData` antes de expor a resposta.

## 15. Relacao com Obot

Obot ja existe como gateway/runtime MCP na wave de AI. ToolHive deve ser tratado inicialmente como plataforma MCP paralela para avaliacao tecnica e hardening.

Requisitos:

- Nao remover Obot no MVP ToolHive.
- Nao migrar consumidores automaticamente.
- Comparar ToolHive e Obot em:
  - modelo de autenticacao;
  - RBAC e isolamento;
  - facilidade GitOps;
  - suporte a Virtual MCP/gateway;
  - observabilidade;
  - audit logging;
  - experiencia de clientes como Claude Code, Codex CLI, OpenCode, VS Code e Zed.
- Definir uma decisao futura de consolidacao apos validacao operacional.

## 16. Criterios de aceite

- ArgoCD cria a aplicacao `toolhive` na wave `6`.
- Namespace `toolhive-system` existe e contem o ToolHive Operator `Ready`.
- CRDs `toolhive.stacklok.dev` existem e sao reconhecidas pela API Kubernetes.
- Namespace `toolhive-mcp` existe com labels/annotations de Pod Security definidas.
- Operator esta limitado ao namespace escolhido, se modo `namespace` for adotado.
- Pelo menos um `MCPServer` ou `MCPRemoteProxy` de baixo risco e reconciliado com sucesso.
- Pelo menos um endpoint MCP e validado por cliente compativel.
- Nenhum secret aparece em texto puro no Git.
- `make template` renderiza o chart sem erro.
- `make validate` passa ou documenta schemas CRD ausentes que precisem ser adicionados ao fluxo de kubeconform.
- Logs do operator e dos MCP workloads estao visiveis.
- Se metrics forem habilitadas, VictoriaMetrics descobre os targets.

## 17. Plano de implementacao

### Fase 0 - Confirmacao de decisoes

- Confirmar detalhes de OIDC/Authelia exigidos pelo chart/recurso adotado.
- Confirmar formato exato dos valores Helm publicados para a versao escolhida dos charts oficiais.

### Fase 1 - Bootstrap ToolHive

- Criar `clusters/platform/wave-6-ai/toolhive/`.
- Criar `app.yaml`.
- Criar `Chart.yaml` com dependencias oficiais.
- Criar `values.yaml` minimo para operator e CRDs.
- Criar namespace `toolhive-mcp`.
- Configurar RBAC/allowed namespaces.
- Validar renderizacao Helm.

### Fase 2 - OIDC nativo, seguranca e observabilidade

- Adicionar ExternalSecrets necessarios.
- Configurar Authelia como provider OIDC para ToolHive.
- Criar client OIDC dedicado para ToolHive e armazenar secrets no Infisical.
- Habilitar autenticacao OIDC nativa do ToolHive no `VirtualMCPServer`.
- Validar clientes MCP alvo usando o fluxo OIDC nativo antes de bloquear o endpoint anonimo.
- Habilitar logs estruturados.
- Habilitar metricas/ServiceMonitor quando suportado.
- Definir labels consistentes para Grafana/VictoriaMetrics.
- Configurar Pod Security no namespace runtime.

### Fase 3 - Primeiro MCP server

- Adicionar MCP server de baixo risco.
- Validar reconciliacao do operator.
- Validar endpoint interno.
- Validar consumo por cliente MCP.
- Registrar runbook minimo de troubleshooting.

### Fase 4 - Virtual MCP e exposicao

- Adicionar `MCPGroup`.
- Adicionar `MCPToolConfig`.
- Criar `VirtualMCPServer`.
- Expor via Traefik se autenticacao estiver definida.
- Validar cliente externo autorizado.

## 18. Estado das decisoes

Todas as decisoes de produto e operacao necessarias para iniciar a implementacao do MVP estao fechadas neste PRD.

Decisoes que ainda devem ser confirmadas tecnicamente durante a implementacao:

- Formato exato das versoes Helm publicadas para `toolhive-operator-crds` e `toolhive-operator`.
- Campos finais de `values.yaml` suportados pelos charts oficiais na versao escolhida.
- Campos exatos de OIDC nativo suportados pelos CRDs ToolHive para substituir `incomingAuth.type: anonymous` em fase 2.
