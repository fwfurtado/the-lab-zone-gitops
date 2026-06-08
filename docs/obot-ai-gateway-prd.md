# PRD Tecnico: Obot AI Gateway

## Contexto

O Context Forge AI Gateway foi descartado para este ambiente porque a versao atual da imagem upstream exige CPU com suporte a `x86-64-v3`, e a versao antiga compativel nao entrega as capacidades operacionais esperadas para observabilidade e configuracao. O MVP passa a usar Obot como gateway central de ferramentas e runtime MCP.

LiteLLM e Obot possuem responsabilidades distintas:

| Responsabilidade | Sistema |
|---|---|
| AI model gateway, roteamento multi-provider, fallback, virtual keys, quotas, custos, OpenRouter, OpenAI, Anthropic e vLLM | LiteLLM |
| Tool gateway, MCP gateway, registry/discovery de ferramentas, runtime MCP em Kubernetes e acesso governado por clientes/agentes | Obot |

Nao e permitido mover responsabilidades de roteamento, governanca ou integracao de modelos para o Obot. LiteLLM permanece como gateway de modelos.

## Objetivo

Implantar Obot como endpoint governado para acesso a ferramentas usadas por sistemas de AI dentro da plataforma The Lab.

O objetivo de longo prazo e centralizar acesso a ferramentas para OpenHands, Claude Code, OpenCode, VS Code, Zed, agentes SRE, agentes DevOps e futuros agentes autonomos atraves de um unico endpoint governado.

## Escopo MVP

- Implantar Obot em `clusters/platform/wave-6-ai/obot/`.
- Usar namespace Kubernetes `obot`.
- Expor a UI/API em `https://obot.platform.the-lab.zone`.
- Usar o Helm chart upstream `obot/obot`, sem reimplementar recursos do chart em manifests customizados.
- Fixar versao explicita do chart e imagem, sem usar `latest`.
- Usar PostgreSQL externo existente.
- Usar PVC `proxmox-lvm` para estado local e audit logs em disco.
- Habilitar autenticacao nativa do Obot.
- Usar runtime MCP em Kubernetes, com namespace dedicado `obot-mcp`.
- Manter o roteamento de modelos exclusivamente no LiteLLM.

## Fora de Escopo

- Migrar model routing do LiteLLM para Obot.
- Publicar o servico diretamente na internet.
- Habilitar Authelia/OIDC no MVP.
- Implementar NetworkPolicy de menor privilegio no MVP.
- Automatizar registro inicial de todos os MCP servers.
- Garantir alta disponibilidade multi-replica antes de armazenamento de artefatos/audit logs em backend compartilhado.

## Decisoes

| Item | Decisao |
|---|---|
| App | `obot` |
| Namespace | `obot` |
| Sync wave | `6` |
| Host | `obot.platform.the-lab.zone` |
| Helm chart | `obot/obot` |
| Chart version | `v0.22.1` |
| Image | `ghcr.io/obot-platform/obot:v0.22.1` |
| Ingress | Traefik `IngressRoute`; ingress nativo do chart desabilitado |
| TLS | `platform-wildcard-tls` via Reflector |
| Auth | Autenticacao nativa do Obot |
| Database | PostgreSQL externo `postgres.database.svc.cluster.local:5432` |
| DB name/user | `obot` / `obot` |
| Embedded DB | Desabilitado |
| MCP runtime | Kubernetes |
| MCP namespace | `obot-mcp` |
| MCP NetworkPolicy | Desabilitada no MVP |

## Secrets

Secrets devem ser gerenciados via External Secrets Operator usando o `ClusterSecretStore` `infisical`.

| Uso | Infisical path |
|---|---|
| Database password | `/database/obot/password` |
| Encryption key | `/obot/encryption-key` |
| Bootstrap token | `/obot/bootstrap-token` |
| Owner/admin emails | `/obot/owner-emails` |

`/obot/encryption-key` deve ser gerado com formato compativel com o provider `custom` do Obot, por exemplo `openssl rand -base64 32`.

`/obot/bootstrap-token` deve ser uma string longa, aleatoria e de alta entropia. Ele sera usado apenas para bootstrap/autenticacao inicial.

`/obot/owner-emails` deve conter um ou mais emails separados por virgula.

## Banco de Dados

Obot deve usar o cluster PostgreSQL existente:

```text
postgres.database.svc.cluster.local:5432
```

Banco e usuario:

```text
database: obot
user: obot
```

O banco precisa suportar `pgvector`, conforme requisito upstream do Obot. A inicializacao deve criar o database, o usuario e tentar habilitar a extensao `vector` no database `obot`.

## Runtime MCP

Obot deve executar MCP servers pelo backend Kubernetes:

```text
OBOT_SERVER_MCPRUNTIME_BACKEND=kubernetes
OBOT_SERVER_MCPNAMESPACE=obot-mcp
```

O namespace `obot-mcp` deve ser criado pelo chart, com Pod Security Admission em modo `restricted`.

NetworkPolicy fica desabilitada no MVP para reduzir complexidade de troubleshooting. A fase futura deve habilitar e restringir egress para DNS, services internos autorizados e destinos externos permitidos.

## Observabilidade

O MVP deve validar:

- Pod `obot` em estado `Ready`.
- Health check `/api/healthz` respondendo.
- Logs estruturados suficientes para troubleshooting.
- Acesso pela UI em `https://obot.platform.the-lab.zone` via rede interna/Tailscale.

Metricas Prometheus dedicadas nao sao requisito bloqueante do MVP. Se o Obot expuser endpoint de metricas suportado oficialmente em versao futura, adicionar `ServiceMonitor`.

## Integracoes Iniciais

O MVP nao exige registro automatico de MCP servers. A validacao inicial deve ser manual, priorizando:

- MCP Inspector.
- Claude Code.
- OpenCode.
- OpenHands.
- Git/Forgejo.
- Kubernetes.
- Grafana.
- Filesystem tools controladas.

## Criterios de Aceite

- ArgoCD cria a aplicacao `obot` na wave `6`.
- Namespace `obot` existe e contem Deployment, Service, PVC, ExternalSecret e IngressRoute.
- Namespace `obot-mcp` e criado para runtime MCP.
- Secret `obot-env` e populado pelo ESO.
- Obot usa PostgreSQL externo e nao usa embedded database.
- UI/API acessivel em `https://obot.platform.the-lab.zone`.
- Primeiro owner/admin consegue autenticar usando o fluxo nativo do Obot.
- Nenhuma responsabilidade de model gateway e movida do LiteLLM para o Obot.

## Fases Futuras

- Integrar Authelia OIDC.
- Adicionar NetworkPolicies least-privilege.
- Avaliar audit logs em S3/MinIO.
- Avaliar HA multi-replica com storage compartilhado para artefatos.
- Automatizar onboarding de MCP servers internos aprovados.
- Integrar clientes adicionais como VS Code, Zed e agentes internos.
