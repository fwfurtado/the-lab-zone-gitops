# PRD Tecnico: Context Forge AI Gateway

## 1. Resumo

Este PRD define a implementacao do Context Forge AI Gateway no cluster Kubernetes GitOps do The Lab Zone, dentro da wave de AI.

Context Forge deve ser introduzido como gateway central para ferramentas MCP, A2A e REST-based tools usadas por agentes e clientes de AI. Ele deve atuar como camada de registro, descoberta, governanca, auditoria e controle de acesso para ferramentas, sem assumir responsabilidades de roteamento de modelos.

LiteLLM e Context Forge possuem responsabilidades distintas e complementares:

| Responsabilidade | Sistema |
|---|---|
| AI model gateway, model routing, provider governance, fallback, virtual keys, quotas e cost tracking | LiteLLM |
| Tool gateway, MCP gateway, MCP registry, MCP discovery, tool governance, tool audit, tool access control, A2A gateway e REST tool gateway | Context Forge |

Decisao arquitetural obrigatoria:

- Nao e permitido mover responsabilidades de roteamento, governanca ou integracao de modelos para o Context Forge.
- LiteLLM permanece exclusivamente responsavel por acesso a modelos, roteamento multi-provider, fallback, quotas, custos e integracoes com OpenRouter, OpenAI, Anthropic e vLLM.
- Context Forge centraliza descoberta, registro, governanca e acesso a ferramentas.

O objetivo de longo prazo e tornar Context Forge o endpoint governado unico para acesso a ferramentas por OpenHands, Claude Code, OpenCode, VS Code, Zed, agentes SRE, agentes DevOps e futuros agentes autonomos.

## 2. Objetivos

### 2.1 Objetivos de produto

- Disponibilizar um gateway central para ferramentas MCP, A2A e REST.
- Centralizar registro e descoberta de ferramentas usadas por clientes e agentes de AI.
- Fornecer ponto unico de governanca para tool access dentro da plataforma The Lab.
- Permitir validacao inicial com Claude Code, OpenCode, OpenHands e MCP Inspector.
- Permitir onboarding manual de ferramentas no MVP via Admin UI.
- Preparar a plataforma para centralizar futuramente acesso a Forgejo, Kubernetes, Grafana, Git tools, filesystem tools, Neo4j, LightRAG, OpenTofu e servicos internos.

### 2.2 Objetivos tecnicos

- Implantar Context Forge como workload Kubernetes gerenciado por ArgoCD.
- Usar o Helm chart upstream `charts/mcp-stack` do projeto Context Forge.
- Empacotar ou vendorizar o chart no repositorio seguindo o padrao usado pelo LiteLLM.
- Fixar versao estavel explicita, sem uso de tags flutuantes como `latest`.
- Implantar em `clusters/platform/wave-6-ai/context-forge/`.
- Usar namespace Kubernetes `context-forge`.
- Usar ArgoCD sync wave `6`.
- Expor a aplicacao em `context-forge.platform.the-lab.zone`.
- Desabilitar ingress nativo do chart e criar Traefik `IngressRoute` proprio.
- Usar PostgreSQL externo existente.
- Usar Valkey existente com database Redis dedicado.
- Gerenciar credenciais via Infisical e External Secrets Operator.
- Habilitar Admin UI.
- Habilitar autenticacao nativa do Context Forge no MVP.
- Habilitar health checks, metrics Prometheus, ServiceMonitor e logs JSON.
- Habilitar auditoria minima sem persistir payloads, prompts, request bodies ou contexto.

## 3. Fora de escopo

- Roteamento de modelos LLM.
- Governanca de modelos LLM.
- Fallback de modelos.
- Virtual keys de modelo.
- Cost tracking de modelos.
- Qualquer substituicao de LiteLLM.
- Registro automatico de MCP servers no MVP.
- OIDC/SSO com Authelia no MVP.
- Authelia forward-auth no MVP.
- Fine-grained RBAC no MVP.
- Multi-user, teams, hierarquia organizacional e permissoes por ferramenta no MVP.
- Deploy de PgAdmin.
- Deploy de Redis Commander.
- Custom plugins no MVP.
- OpenTelemetry, Jaeger, Phoenix e distributed tracing no MVP.
- NetworkPolicy least-privilege no MVP.
- Exposicao publica direta na internet.
- Execucao de MCP servers via `stdio` dentro dos pods.
- WebSocket como transporte no MVP.

## 4. Consumidores previstos

### 4.1 Prioridade 1

| Consumidor | Uso esperado |
|---|---|
| Claude Code | Consumo de ferramentas por endpoint MCP governado |
| OpenCode | Consumo de ferramentas por endpoint MCP governado |
| OpenHands | Consumo de ferramentas por endpoint MCP/A2A governado |
| MCP Inspector | Validacao funcional, troubleshooting e testes de compatibilidade |

### 4.2 Prioridade 2

| Consumidor | Uso esperado |
|---|---|
| VS Code | Consumo de ferramentas MCP em fase posterior ao MVP inicial |
| Zed | Consumo de ferramentas MCP em fase posterior ao MVP inicial |

### 4.3 Futuro

| Consumidor | Uso esperado |
|---|---|
| OpenWebUI | Integracao futura com ferramentas governadas |
| Agentes SRE internos | Acesso controlado a ferramentas operacionais |
| Agentes DevOps internos | Acesso controlado a ferramentas de automacao |
| Futuros agentes autonomos | Acesso a ferramentas atraves de endpoint governado unico |

## 5. Requisitos funcionais

### 5.1 Gateway MCP, A2A e REST

- Context Forge deve atuar como gateway central para ferramentas MCP.
- Context Forge deve permitir registro, descoberta e administracao de gateways/ferramentas.
- Context Forge deve suportar A2A gateway conforme capacidades do produto.
- Context Forge deve suportar REST tool gateway conforme capacidades do produto.
- Ferramentas devem ser registradas manualmente no MVP.
- LiteLLM nao deve ser registrado como MCP server.
- Context Forge nao deve receber responsabilidades de chamadas diretas a modelos.

### 5.2 Admin UI

- Admin UI deve permanecer habilitada.
- Admin UI deve ser acessivel por `https://context-forge.platform.the-lab.zone`.
- Admin UI deve ser usada para validacao, onboarding inicial, troubleshooting, registro de ferramentas e administracao de gateways.
- O bootstrap do administrador deve usar `PLATFORM_ADMIN_EMAIL` e `PLATFORM_ADMIN_PASSWORD`.
- Credenciais de bootstrap devem vir de Infisical via External Secrets Operator.

### 5.3 Autenticacao

- MVP deve usar autenticacao nativa do Context Forge.
- MVP deve usar uma unica conta administrativa.
- Authelia forward-auth nao deve ser usado no MVP.
- OIDC com Authelia fica reservado para fase posterior.
- A exposicao externa deve pressupor acesso apenas por rede interna e Tailscale VPN.
- Context Forge nao deve ser exposto diretamente a internet publica no MVP.

### 5.4 Registro inicial de ferramentas

O MVP nao exige registro automatico de MCP servers. A validacao deve ser feita por cadastro manual.

Alvos iniciais de validacao:

| Alvo | Status no MVP |
|---|---|
| Forgejo | Validacao manual |
| Kubernetes | Validacao manual |
| Grafana | Validacao manual |
| Git tools | Validacao manual |
| Filesystem tools | Validacao manual, com escopo restrito |

Integracoes futuras:

| Alvo | Status |
|---|---|
| Neo4j | Futuro |
| LightRAG | Futuro |
| OpenTofu | Futuro |
| Servicos internos adicionais | Futuro |

### 5.5 Protocolos e transportes

Transportes habilitados no MVP:

- HTTP.
- SSE.
- Streamable HTTP.

Transportes desabilitados no MVP:

- `stdio`.
- WebSocket.

Justificativa:

- Context Forge deve se comunicar com MCP services externos ao pod.
- O gateway nao deve spawnar processos MCP dentro dos pods Kubernetes.
- Desabilitar `stdio` reduz risco operacional e superficie de execucao arbitraria.

### 5.6 Plugins

- Framework de plugins pode permanecer habilitado se for padrao do produto/chart.
- Nenhum plugin customizado deve ser implantado no MVP.
- Plugins customizados devem exigir PRD ou decisao tecnica separada.

## 6. Arquitetura Kubernetes e GitOps

### 6.1 Localizacao

A aplicacao deve ser adicionada em:

```text
clusters/platform/wave-6-ai/context-forge/
```

Estrutura esperada:

```text
clusters/platform/wave-6-ai/context-forge/
  app.yaml
  Chart.yaml
  Chart.lock
  values.yaml
  charts/
  templates/
    external-secret.yaml
    ingressroute.yaml
    servicemonitor.yaml
```

### 6.2 ArgoCD

`app.yaml` deve definir:

```yaml
app:
  name: context-forge
  namespace: context-forge
  syncWave: "6"
```

### 6.3 Helm

- A implementacao deve usar o chart upstream `charts/mcp-stack`.
- O chart deve ser empacotado ou vendorizado no repositorio, seguindo o padrao usado em `clusters/platform/wave-6-ai/litellm/`.
- Funcionalidade nativa do chart nao deve ser reimplementada por manifests customizados sem necessidade.
- Manifests customizados devem ser limitados a integracao com o padrao local, como `ExternalSecret`, Traefik `IngressRoute` e `ServiceMonitor`.
- A versao do chart e da imagem deve ser validada no momento da implementacao.
- Tags flutuantes como `latest`, `main`, `main-latest` ou equivalentes nao devem ser usadas.

### 6.4 Namespace

Context Forge deve ser instalado no namespace:

```text
context-forge
```

### 6.5 Ingress

- O ingress nativo do chart deve permanecer desabilitado.
- Deve ser criado um Traefik `IngressRoute` proprio.
- Host oficial:

```text
context-forge.platform.the-lab.zone
```

- TLS deve usar o secret wildcard replicado pela plataforma:

```text
platform-wildcard-tls
```

- Authelia forward-auth nao deve ser associado ao `IngressRoute` no MVP.
- O acesso externo deve depender da rede interna e da Tailscale VPN.

## 7. Persistencia e dependencias

### 7.1 PostgreSQL

Context Forge deve usar o PostgreSQL externo existente.

Endpoint:

```text
postgres.database.svc.cluster.local:5432
```

Database:

```text
context_forge
```

User:

```text
context_forge
```

Requisitos:

- PostgreSQL interno do chart deve permanecer desabilitado.
- Credenciais devem ser gerenciadas por Infisical.
- A string de conexao deve ser materializada via External Secrets Operator.
- O PRD assume que database e user serao provisionados antes ou durante a implementacao conforme padrao operacional do cluster.
- Backups devem depender da estrategia existente do PostgreSQL externo, sem backup especifico adicional no MVP.

### 7.2 Valkey

Context Forge deve usar o Valkey existente.

Endpoint:

```text
valkey-primary.valkey.svc.cluster.local:6379
```

Database Redis dedicado:

```text
5
```

Alocacao atual:

| DB | Consumidor |
|---|---|
| 3 | LightRAG |
| 4 | LiteLLM |
| 5 | Context Forge |

Requisitos:

- Redis/Valkey interno do chart deve permanecer desabilitado se o chart oferecer esse componente.
- Senha deve vir de Infisical.
- A URL Redis deve usar DB `5`.
- Context Forge nao deve compartilhar DB Redis com LiteLLM ou LightRAG.

### 7.3 UIs auxiliares

Os seguintes componentes devem permanecer desabilitados:

- PgAdmin.
- Redis Commander.

Justificativa:

- O cluster ja possui observabilidade e operacao centralizadas.
- Essas UIs aumentam superficie de exposicao sem serem necessarias para o MVP.

## 8. Secrets

Secrets devem ser gerenciados por Infisical via External Secrets Operator.

Secret Kubernetes esperado:

```text
context-forge-env
```

Remote refs esperadas:

| Chave logica | Remote ref sugerida |
|---|---|
| Admin email | `/context-forge/platform-admin-email` |
| Admin password | `/context-forge/platform-admin-password` |
| Database password | `/database/context-forge/password` |
| Valkey password | `/valkey/password` |
| JWT secret ou equivalente | `/context-forge/jwt-secret` |
| Encryption secret ou equivalente | `/context-forge/encryption-secret` |

Os nomes exatos das variaveis de ambiente devem ser validados contra a versao fixada do chart e da aplicacao durante a implementacao.

## 9. Seguranca

### 9.1 SSRF

- SSRF protection deve permanecer habilitado.
- Como Context Forge precisa conectar a servicos internos, destinos internos devem ser explicitamente permitidos.
- Allowlist deve cobrir apenas redes e endpoints necessarios para integracoes MCP aprovadas.

CIDRs a validar durante a implementacao:

- Kubernetes Service Network.
- Kubernetes Pod Network.
- Endpoints internos especificos requeridos por MCP integrations.

Requisito:

- O PRD nao autoriza desabilitar SSRF protection para facilitar integracao.
- Qualquer allowlist deve ser documentada em `values.yaml`.

### 9.2 RBAC

MVP:

- Uma unica conta administrativa.
- Sem teams.
- Sem separacao multi-user.
- Sem permissoes por ferramenta.
- Sem hierarquia organizacional.

Fase futura:

- RBAC fino por usuario, time e ferramenta.
- Separacao de consumidores.
- Politicas por categoria de ferramenta.

### 9.3 NetworkPolicy

NetworkPolicy deve permanecer desabilitada no MVP.

Justificativa:

- Reduzir complexidade de rollout e troubleshooting inicial.
- Validar primeiro conectividade com clientes e MCP servers.

Fase futura:

- Implementar NetworkPolicies least-privilege permitindo apenas Traefik, PostgreSQL, Valkey, monitoring stack e destinos MCP autorizados.

### 9.4 Dados sensiveis

- Prompts nao devem ser persistidos em auditoria.
- Conteudo de payload de ferramentas nao deve ser persistido em auditoria.
- Request bodies nao devem ser persistidos em auditoria.
- Context data nao deve ser persistido em auditoria.
- Secrets nunca devem ser gravados no Git em texto puro.

## 10. Observabilidade

### 10.1 Health checks

A aplicacao deve expor e usar probes para:

- `/health`.
- `/ready`.

Os caminhos exatos devem ser confirmados contra a versao fixada durante a implementacao.

### 10.2 Metricas

- Prometheus metrics devem ser habilitadas.
- Deve ser criado `ServiceMonitor`.
- Se o endpoint de metricas exigir token/JWT, a autenticacao do `ServiceMonitor` deve usar secret Kubernetes gerenciado por ESO.

### 10.3 Logs

- Logs devem ser estruturados em JSON.
- Logs devem registrar eventos operacionais e administrativos sem payload sensivel.

### 10.4 Tracing

Ficam fora do MVP:

- OpenTelemetry.
- Jaeger.
- Phoenix.
- Distributed tracing.

## 11. Auditoria

Auditoria deve ser habilitada com escopo minimo.

Eventos obrigatorios:

| Evento | Deve auditar |
|---|---|
| Tool creation | Sim |
| Tool modification | Sim |
| Tool deletion | Sim |
| Gateway creation | Sim |
| Gateway modification | Sim |
| Gateway deletion | Sim |
| Administrative login | Sim |
| Configuration changes | Sim |

Dados excluidos:

- Prompt contents.
- Tool payload contents.
- Request bodies.
- Context data.
- Secrets.

## 12. Requisitos de configuracao inicial

Configuracao esperada no MVP:

| Item | Decisao |
|---|---|
| Host | `context-forge.platform.the-lab.zone` |
| Namespace | `context-forge` |
| Sync wave | `6` |
| Chart | Upstream `charts/mcp-stack` |
| Postgres interno | Desabilitado |
| Redis interno | Desabilitado se existente no chart |
| PostgreSQL externo | `postgres.database.svc.cluster.local:5432` |
| Database | `context_forge` |
| User | `context_forge` |
| Valkey | `valkey-primary.valkey.svc.cluster.local:6379/5` |
| PgAdmin | Desabilitado |
| Redis Commander | Desabilitado |
| Native chart ingress | Desabilitado |
| Traefik IngressRoute | Habilitado |
| Authelia forward-auth | Desabilitado no MVP |
| OIDC | Futuro |
| Admin UI | Habilitada |
| RBAC fino | Futuro |
| NetworkPolicy | Desabilitada no MVP |
| SSRF protection | Habilitada |
| Metrics | Habilitadas |
| ServiceMonitor | Habilitado |
| Logs | JSON |
| Audit | Minimo, sem payload |

## 13. Validacao do MVP

O MVP sera considerado pronto quando:

- Chart upstream estiver integrado ao repositorio com versao fixada.
- `make template` renderizar o chart sem erro.
- `make validate` passar com kubeconform para os manifests gerados.
- ArgoCD criar a aplicacao `context-forge` na wave `6`.
- Pods do Context Forge ficarem `Ready`.
- PostgreSQL interno do chart estiver desabilitado.
- Valkey interno ou Redis interno do chart estiver desabilitado, se existir.
- PgAdmin e Redis Commander estiverem desabilitados.
- Admin UI estiver acessivel em `https://context-forge.platform.the-lab.zone` pela rede interna/Tailscale.
- Login com admin local funcionar.
- Health checks responderem.
- ServiceMonitor existir e apontar para o endpoint correto.
- Logs sairem em formato estruturado.
- Auditoria minima registrar eventos administrativos sem payload sensivel.
- Pelo menos um gateway/tool de teste for registrado manualmente.
- MCP Inspector conseguir validar conectividade basica com o gateway.

## 14. Fases futuras

Fases posteriores podem incluir:

- OIDC com Authelia.
- RBAC fino por usuario, time e ferramenta.
- Registro automatico de MCP servers aprovados.
- NetworkPolicies least-privilege.
- OpenTelemetry e distributed tracing.
- Dashboards Grafana dedicados.
- Integracao com Neo4j.
- Integracao com LightRAG.
- Integracao com OpenTofu.
- Integracao com agentes SRE e DevOps autonomos.
- Politicas por categoria de ferramenta.
- Catalogo governado de ferramentas internas.

## 15. Referencias locais

- PRD LiteLLM: `docs/litellm-prd.md`.
- PRD LightRAG: `docs/lightrag-qdrant-neo4j-prd.md`.
- PRD Neo4j: `docs/neo4j-knowledge-rag-prd.md`.
- Implementacao LiteLLM: `clusters/platform/wave-6-ai/litellm/`.
- Implementacao LightRAG: `clusters/platform/wave-6-ai/lightrag/`.
- Implementacao Qdrant: `clusters/platform/wave-6-ai/qdrant/`.
- Implementacao Neo4j: `clusters/platform/wave-6-ai/neo4j/`.

