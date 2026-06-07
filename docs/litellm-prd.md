# PRD Tecnico: LiteLLM

## 1. Resumo

Este PRD define a implementacao do LiteLLM como gateway central de modelos LLM no cluster Kubernetes GitOps do The Lab Zone, dentro da wave de AI.

O objetivo e entregar uma camada OpenAI-compatible para consumidores internos e externos, com Admin UI, Virtual Keys, budgets, rate limits, spend tracking, fallback simples e observabilidade desde o MVP.

LiteLLM deve centralizar o acesso a modelos locais e cloud, desacoplando os consumidores dos providers reais. Consumidores devem chamar apenas aliases internos, permitindo trocar Ollama por vLLM ou adicionar providers cloud sem alterar configuracoes de clientes.

A arquitetura alvo usa os componentes existentes da plataforma:

| Responsabilidade | Sistema |
|---|---|
| Gateway OpenAI-compatible, autenticacao por virtual keys, policies e roteamento | LiteLLM |
| Modelos locais no MVP | Ollama |
| Provider cloud de fallback | OpenRouter |
| Persistencia administrativa, virtual keys, budgets e spend tracking | Postgres externo existente |
| Rate limiting e cache operacional | Valkey existente |
| Exposicao HTTPS | Traefik |
| Secrets | Infisical via External Secrets Operator |
| Observabilidade | VictoriaMetrics Operator e Grafana |

Decisoes principais:

- LiteLLM deve ser implantado em `clusters/platform/wave-6-ai/litellm/`.
- A aplicacao deve usar o chart oficial do LiteLLM como dependencia Helm.
- A implementacao inicial usa chart oficial `1.88.0` em `oci://ghcr.io/berriai/litellm-helm`.
- A imagem inicial usa `ghcr.io/berriai/litellm-database:1.88.0`.
- O namespace deve ser `litellm`.
- A sync wave deve ser `6`.
- A API e a Admin UI devem ser expostas em `https://litellm.platform.the-lab.zone`.
- A API deve usar apenas LiteLLM Virtual Keys, sem Authelia, OIDC ou autenticacao adicional.
- A Admin UI deve ser protegida pela Master Key do LiteLLM, sem Authelia e sem OIDC no MVP.
- O Postgres externo existente deve armazenar estado administrativo, virtual keys, budgets, spend tracking e metadados operacionais.
- Valkey existente deve ser usado para rate limiting e cache operacional.
- Response caching deve ficar desabilitado no MVP.
- Prompts, completions e conversas nao devem ser armazenados.
- LightRAG deve usar LiteLLM como gateway principal para chat LLM e embeddings.
- Consumidores devem usar apenas aliases internos aprovados.
- A implementacao nao deve usar tags `latest`, `main-latest`, `main-stable` ou equivalentes flutuantes.

## 2. Objetivos

### 2.1 Objetivos de produto

- Centralizar acesso a modelos locais e cloud.
- Fornecer endpoint OpenAI-compatible para ferramentas locais, remotas, IDEs, notebooks e agentes.
- Permitir que LightRAG, OpenHands, Claude Code, OpenCode, Zed, VSCode, JetBrains IDEs e uso manual via API consumam modelos com a mesma interface.
- Permitir troca futura de Ollama para vLLM sem alterar consumidores.
- Permitir fallback automatico de modelos locais para cloud via OpenRouter.
- Controlar custos, quotas e rate limits por consumidor.
- Medir uso por chave virtual, time, modelo e provider.
- Reduzir risco operacional evitando exposicao direta de chaves dos providers aos consumidores.

### 2.2 Objetivos tecnicos

- Implantar LiteLLM como workload Kubernetes gerenciado por ArgoCD.
- Usar o chart oficial do LiteLLM com versao fixada.
- Usar imagem LiteLLM com tag fixada e assinatura verificavel.
- Configurar `DATABASE_URL` para Postgres externo.
- Configurar Master Key e Salt Key via Infisical.
- Configurar OpenRouter API key via Infisical.
- Configurar endpoints locais Ollama por variaveis e config versionada.
- Configurar aliases internos no `config.yaml` do LiteLLM.
- Configurar fallbacks simples no `config.yaml`.
- Configurar retries e timeouts conservadores.
- Habilitar virtual keys, budgets, spend tracking e rate limits.
- Habilitar ServiceMonitor e metricas para VictoriaMetrics.
- Expor via Traefik IngressRoute HTTPS.
- Documentar contrato de consumo para clientes OpenAI-compatible.

## 3. Fora de escopo

- Least Cost Routing avancado.
- Roteamento por qualidade.
- Roteamento por tipo de tarefa.
- Auditoria ou persistencia de prompts, completions e conversas.
- SSO/OIDC para Admin UI.
- Authelia na API ou na Admin UI.
- Providers diretos OpenAI, Anthropic, Gemini ou Groq no MVP.
- Deploy de vLLM no MVP.
- HPA.
- HA avancado.
- Response caching.
- Denylist obrigatoria.
- Forgejo Actions, agentes SRE autonomos e Coder como consumidores iniciais.
- Backup adicional especifico do LiteLLM alem da estrategia existente do Postgres externo.

## 4. Consumidores previstos

### 4.1 MVP

| Consumidor | Uso esperado |
|---|---|
| LightRAG | Gateway principal para chat LLM e embeddings |
| OpenHands | Consumo via OpenAI-compatible API |
| Claude Code | Consumo via OpenAI-compatible API |
| OpenCode | Consumo via OpenAI-compatible API |
| Zed | Uso local/remoto via endpoint OpenAI-compatible |
| VSCode | Uso local/remoto via endpoint OpenAI-compatible |
| JetBrains IDEs | Uso local/remoto via endpoint OpenAI-compatible |
| Uso manual via API | Testes, notebooks e chamadas administrativas |

### 4.2 Fase posterior

| Consumidor | Uso esperado |
|---|---|
| Forgejo Actions | Automacoes CI/CD com virtual keys dedicadas |
| Agentes SRE autonomos | Uso operacional com budgets e rate limits especificos |
| Coder | Workspaces com consumo controlado por chave |

## 5. Requisitos funcionais

### 5.1 Gateway OpenAI-compatible

- LiteLLM deve expor endpoints compativeis com OpenAI em `https://litellm.platform.the-lab.zone`.
- Clientes devem configurar o base URL para `https://litellm.platform.the-lab.zone`.
- Clientes devem autenticar com `Authorization: Bearer <virtual-key>`.
- Consumidores nao devem receber chaves reais de Ollama, OpenRouter ou outros providers.
- Consumidores nao devem usar nomes reais de modelos.
- O endpoint deve suportar chat completions.
- O endpoint deve suportar embeddings.
- O endpoint deve suportar streaming quando suportado pelo provider/modelo.
- O endpoint deve retornar erros em formato compativel com clientes OpenAI sempre que possivel.

### 5.2 Admin UI

- Admin UI deve ficar habilitada no MVP.
- Admin UI deve ser acessivel no mesmo host `https://litellm.platform.the-lab.zone`.
- Admin UI deve ser protegida pela Master Key do LiteLLM.
- Admin UI nao deve usar Authelia no MVP.
- Admin UI nao deve usar OIDC no MVP.
- Admin UI deve permitir administrar virtual keys, teams, budgets e modelos conforme recursos OSS disponiveis.

### 5.3 Virtual Keys

- Cada consumidor do MVP deve receber uma virtual key dedicada.
- Virtual keys devem ter allowlist de modelos/aliases.
- Virtual keys devem ter budgets e rate limits quando aplicavel.
- Virtual keys nao devem ser armazenadas em texto puro no Git.
- Virtual keys devem ser criadas via Admin UI ou API administrativa apos o deploy inicial.
- Master Key deve ser usada apenas para administracao e bootstrap.

### 5.4 Budgets e spend tracking

- LiteLLM deve rastrear custo, tokens, modelo, provider, virtual key, time e status da chamada.
- Budgets devem ser aplicaveis por virtual key.
- Budgets devem ser aplicaveis por team.
- O PRD nao fixa valores iniciais de budget; eles devem ser definidos durante bootstrap operacional.
- O banco deve armazenar metadados necessarios para spend tracking, sem armazenar prompts/completions.

### 5.5 Rate limits

- Rate limits devem ser habilitados no MVP.
- A configuracao inicial deve ser conservadora.
- Rate limits devem ser aplicaveis por virtual key e/ou team.
- Rate limits por deployment/modelo podem ser usados para proteger Ollama local.
- Valkey deve ser usado para suportar rate limiting e evitar depender apenas do Postgres.

### 5.6 Fallback

- Fallback simples deve ser habilitado no MVP.
- O padrao deve ser provider local primeiro e OpenRouter como fallback cloud.
- Fallback deve ocorrer apos retries configurados.
- Fallback deve ser configurado por alias/model group, nao por consumidor.
- Fallback avancado por custo, qualidade ou tipo de tarefa fica fora do MVP.

### 5.7 Retry e timeout

- Retries devem ser habilitados no MVP.
- Timeouts devem ser configurados no `config.yaml`.
- Timeouts devem evitar chamadas presas em providers locais ou cloud.
- Valores finais devem ser ajustados apos teste de carga basico, mas o MVP deve iniciar com valores conservadores.

## 6. Providers e modelos

### 6.1 Providers do MVP

| Provider | Uso | Status |
|---|---|---|
| Ollama interno | Chat, multimodal e embeddings locais | Obrigatorio no MVP |
| OpenRouter | Fallback cloud, comparacao e continuidade operacional | Obrigatorio no MVP |
| OpenAI direto | Nao usar | Fora do MVP |
| Anthropic direto | Nao usar | Fora do MVP |
| Gemini direto | Nao usar | Fora do MVP |
| Groq | Nao usar | Fora do MVP |
| vLLM | Provider futuro previsto no design | Fora do deploy MVP |

### 6.2 Modelos locais

Chat:

- `qwen3:32b`
- `qwen3:30b-a3b`
- `deepseek-r1:32b`

Multimodal:

- `gemma3:27b`

Embeddings:

- `bge-m3`
- `embeddinggemma` opcional

### 6.3 Modelos cloud

OpenRouter deve estar habilitado no MVP, mas modelos cloud especificos podem ser configurados posteriormente.

Embeddings cloud candidatos:

- `openai/text-embedding-3-large`
- `google/gemini-embedding-2-preview`

O PRD nao exige usar OpenAI direto nem Gemini direto. Esses modelos devem ser acessados via OpenRouter quando suportado e operacionalmente adequado.

## 7. Aliases internos

Consumidores nunca devem usar nomes reais de modelos. Todos os clientes devem usar aliases internos.

### 7.1 Aliases obrigatorios

Chat:

- `lab-chat-default`
- `lab-chat-fast`
- `lab-chat-reasoning`
- `lab-chat-cloud`
- `lab-chat-fallback`

Multimodal:

- `lab-vision-default`

Embeddings:

- `lab-embedding-default`
- `lab-embedding-cloud`
- `lab-embedding-fallback`

### 7.2 Mapeamento inicial

| Alias | Mapeamento inicial |
|---|---|
| `lab-chat-default` | `qwen3:32b` local |
| `lab-chat-fast` | `qwen3:30b-a3b` local |
| `lab-chat-reasoning` | `deepseek-r1:32b` local |
| `lab-chat-cloud` | Modelo OpenRouter configurado em runtime |
| `lab-chat-fallback` | `qwen3:32b` local com fallback para OpenRouter |
| `lab-vision-default` | `gemma3:27b` local |
| `lab-embedding-default` | `bge-m3` local |
| `lab-embedding-cloud` | `openai/text-embedding-3-large` ou `google/gemini-embedding-2-preview` via OpenRouter |
| `lab-embedding-fallback` | `bge-m3` local com fallback para embedding cloud |

### 7.3 Exemplo conceitual de config

Este exemplo e ilustrativo. A implementacao deve validar os campos contra a versao fixada do chart e do LiteLLM.

```yaml
model_list:
  - model_name: lab-chat-default
    litellm_params:
      model: ollama/qwen3:32b
      api_base: os.environ/OLLAMA_API_BASE

  - model_name: lab-chat-fast
    litellm_params:
      model: ollama/qwen3:30b-a3b
      api_base: os.environ/OLLAMA_API_BASE

  - model_name: lab-chat-reasoning
    litellm_params:
      model: ollama/deepseek-r1:32b
      api_base: os.environ/OLLAMA_API_BASE

  - model_name: lab-chat-cloud
    litellm_params:
      model: openrouter/<configured-cloud-model>
      api_key: os.environ/OPENROUTER_API_KEY

  - model_name: lab-chat-fallback
    litellm_params:
      model: ollama/qwen3:32b
      api_base: os.environ/OLLAMA_API_BASE

  - model_name: lab-embedding-default
    litellm_params:
      model: ollama/bge-m3
      api_base: os.environ/OLLAMA_API_BASE

litellm_settings:
  num_retries: 2
  request_timeout: 60
  fallbacks:
    - lab-chat-fallback:
        - lab-chat-cloud
    - lab-embedding-fallback:
        - lab-embedding-cloud
```

## 8. Integracao com LightRAG

LightRAG deve usar LiteLLM como gateway principal para:

- Chat LLM.
- Embeddings.

Objetivos:

- Centralizar autenticacao.
- Centralizar configuracao de modelos.
- Coletar metricas de uso.
- Aplicar budgets e rate limits.
- Permitir troca de provider sem alterar a configuracao de consumidores.

Requisitos:

- LightRAG deve usar `https://litellm.platform.the-lab.zone` ou service interno do LiteLLM como base URL.
- A preferencia operacional e usar service interno para workloads Kubernetes, evitando sair pela borda.
- LightRAG deve usar virtual key propria.
- LightRAG deve usar aliases `lab-chat-*` e `lab-embedding-*`.
- LightRAG nao deve usar nomes reais de modelos locais ou cloud.
- Mudancas no chart do LightRAG devem ser tratadas como fase de implementacao apos o deploy do LiteLLM.

## 9. Persistencia

### 9.1 Postgres

LiteLLM deve usar o Postgres externo existente:

```text
postgres.database.svc.cluster.local:5432
```

Database:

```text
litellm
```

User:

```text
litellm
```

Requisitos:

- Credenciais devem vir de Infisical.
- `DATABASE_URL` deve ser montado via Secret Kubernetes gerenciado por External Secrets Operator.
- O banco deve armazenar virtual keys, teams, budgets, spend tracking e metadados operacionais.
- O banco nao deve armazenar prompts, completions ou conversas no MVP.
- Backup e restore devem seguir a estrategia existente do Postgres externo.

### 9.2 Valkey

LiteLLM deve usar o Valkey existente:

```text
valkey-primary.valkey.svc.cluster.local:6379
```

Database sugerido:

```text
4
```

Uso habilitado:

- Rate limiting.
- Cache operacional.

Uso desabilitado:

- Response caching.

Requisitos:

- Senha deve vir de Infisical.
- A URL Redis/Valkey deve ser montada via Secret Kubernetes.
- Chaves devem usar prefixo ou namespace logico do LiteLLM quando suportado.

## 10. Secrets

Secrets devem vir de Infisical via External Secrets Operator e ClusterSecretStore `infisical`.

Secret Kubernetes alvo:

```text
litellm-env
```

Remote refs esperadas:

| Secret key | Remote ref sugerido |
|---|---|
| `LITELLM_MASTER_KEY` | `/litellm/master-key` |
| `LITELLM_SALT_KEY` | `/litellm/salt-key` |
| `DATABASE_URL` | `/litellm/database-url` |
| `OPENROUTER_API_KEY` | `/litellm/openrouter-api-key` |
| `REDIS_URL` | `/litellm/redis-url` |
| `OLLAMA_API_BASE` | `/litellm/ollama-api-base` |

Requisitos:

- Master Key deve comecar com `sk-`.
- Salt Key deve ser criada antes de adicionar modelos e nao deve ser rotacionada sem plano especifico, pois e usada para criptografia/decriptografia de credenciais do LiteLLM.
- Nenhum provider API key deve aparecer em `values.yaml`, `config.yaml`, manifests ou docs com valor real.

## 11. Kubernetes e GitOps

### 11.1 Localizacao

LiteLLM deve ser adicionado em:

```text
clusters/platform/wave-6-ai/litellm/
```

Estrutura esperada:

```text
litellm/
  app.yaml
  Chart.yaml
  values.yaml
  templates/
    external-secret.yaml
    ingressroute.yaml
    servicemonitor.yaml
```

O chart oficial do LiteLLM deve ser usado como dependencia Helm no `Chart.yaml`. Templates proprios devem cobrir recursos que o chart oficial nao modele de forma compativel com o padrao do repo, como `ExternalSecret`, `IngressRoute` Traefik e `ServiceMonitor`.

### 11.2 App metadata

`app.yaml` esperado:

```yaml
app:
  name: litellm
  namespace: litellm
  syncWave: "6"
```

### 11.3 Chart oficial

Requisitos:

- Usar o chart oficial do LiteLLM.
- Fixar a versao do chart.
- Fixar a tag da imagem.
- Nao usar `latest`, `main-latest`, `main-stable` ou tags flutuantes.
- Validar valores suportados pela versao fixada antes da implementacao.
- Registrar no `values.yaml` a versao da imagem e o chart efetivamente usados.

Observacao de documentacao:

- A documentacao oficial marca o Helm chart como beta.
- A documentacao oficial mostra o chart OCI em `docker.litellm.ai/berriai/litellm-helm`.
- A implementacao validou que `docker.litellm.ai/berriai/litellm-helm:1.1.0` nao estava publicado e adotou o chart oficial publicado no GHCR em `oci://ghcr.io/berriai/litellm-helm:1.88.0`.
- A implementacao deve validar upgrades futuros com `helm show chart` ou `helm pull` antes do commit.

### 11.4 Deployment

Requisitos de runtime:

| Campo | Valor |
|---|---|
| Replicas | `2` |
| HPA | Desabilitado no MVP |
| Requests CPU | `250m` |
| Requests memory | `512Mi` |
| Limits CPU | `1000m` |
| Limits memory | `1Gi` |
| Port | `4000` |
| Update strategy | Rolling update, se suportado pelo chart |

Observacao:

- A documentacao oficial recomenda recursos maiores para producao. O sizing do MVP e intencionalmente menor para homelab, com 2 replicas e baixo consumo. Se houver latencia elevada, memory pressure ou CPU throttling, o sizing deve ser revisto.

### 11.5 Health checks

Requisitos:

- Liveness probe deve usar endpoint de health suportado pela versao fixada.
- Readiness probe deve usar endpoint de health suportado pela versao fixada.
- A documentacao oficial referencia endpoints como `/health/liveliness` e `/health/readiness`; a implementacao deve validar esses paths contra a versao fixada.

## 12. Exposicao e seguranca de borda

### 12.1 Endpoint externo

Host:

```text
litellm.platform.the-lab.zone
```

URL:

```text
https://litellm.platform.the-lab.zone
```

Requisitos:

- Expor via Traefik IngressRoute.
- Usar TLS wildcard `platform-wildcard-tls`.
- Usar middleware de headers padrao quando aplicavel.
- Nao aplicar middleware Authelia.
- Nao aplicar OIDC.

### 12.2 API

Protecao:

- Apenas LiteLLM Virtual Keys.

Nao utilizar:

- Authelia.
- OIDC.
- Basic auth adicional.
- Chaves reais dos providers em clientes.

### 12.3 Admin UI

Protecao:

- Master Key do LiteLLM.

Nao utilizar:

- Authelia.
- OIDC.
- Recursos Enterprise de SSO.

Risco aceito:

- A Admin UI fica exposta publicamente em HTTPS e protegida pela Master Key. Este risco e aceito no MVP para preservar compatibilidade e simplicidade operacional. A Master Key deve ser forte e armazenada apenas em Infisical.

## 13. Logging, privacidade e retencao

Nao armazenar:

- Prompts.
- Completions.
- Conversas.
- Codigo fonte.
- Segredos.
- Credenciais.
- Documentos privados.

Permitir armazenar:

- Modelo utilizado.
- Provider utilizado.
- Latencia.
- Tokens.
- Custos.
- Chave virtual.
- Team.
- Status.
- Erros.
- Metricas operacionais.

Motivacoes:

- Evitar vazamento de codigo fonte.
- Evitar armazenamento de segredos.
- Evitar armazenamento de credenciais.
- Evitar armazenamento de documentos privados.
- Reduzir impacto de LGPD.
- Simplificar backup e retencao.
- Reduzir crescimento do banco.

Auditoria de conteudo:

- Fora do MVP.
- Pode ser implementada posteriormente com politica dedicada de retencao, consentimento e acesso.

## 14. Observabilidade

Observabilidade e obrigatoria no MVP.

Requisitos:

- ServiceMonitor habilitado.
- Prometheus scraping via VictoriaMetrics Operator.
- Dashboard Grafana.
- Metricas de requests, erros, latencia, tokens, custo e provider quando suportadas.
- Metricas por modelo/alias quando suportadas.
- Metricas por virtual key/team devem ser avaliadas com cuidado para evitar cardinalidade excessiva.

Alertas minimos:

| Alerta | Condicao esperada |
|---|---|
| Pod indisponivel | Nenhuma replica ready |
| Taxa de erro elevada | 5xx ou provider errors acima do limiar definido |
| Latencia elevada | P95 acima do limiar definido |
| Falha de conexao com Postgres | Erros recorrentes de DB |
| Falha de conexao com Valkey | Erros recorrentes de Redis/Valkey |

## 15. Backup e DR

LiteLLM nao exige backup adicional especifico no MVP.

Persistencia relevante:

- Postgres externo.

RPO:

```text
24 horas
```

RTO:

```text
4 horas
```

Requisitos:

- Backup deve seguir estrategia existente do Postgres externo.
- Restore deve recuperar virtual keys, teams, budgets e spend tracking.
- Config versionada em Git deve permitir recriar o workload.
- Secrets devem permanecer em Infisical.

## 16. Seguranca de supply chain

Requisitos:

- Usar imagem oficial com tag fixada.
- Evitar pacotes Python instalados em runtime.
- Evitar builds dinamicos a partir de PyPI no cluster.
- Preferir imagem oficial assinada.
- Verificar assinatura da imagem com cosign durante implementacao ou pipeline, quando possivel.
- Usar chave publica fixa recomendada pela documentacao oficial quando aplicavel.
- Registrar digest ou tag fixada no `values.yaml`.

Motivacao:

- LiteLLM manipula chaves de providers e metadados sensiveis de consumo.
- O gateway fica exposto externamente.
- Tags flutuantes e instalacoes dinamicas aumentam risco de drift e supply chain.

## 17. Politicas iniciais

### 17.1 Teams

Teams iniciais sugeridos:

| Team | Consumidores |
|---|---|
| `rag` | LightRAG |
| `devtools` | Claude Code, OpenCode, Zed, VSCode, JetBrains |
| `openhands` | OpenHands |
| `manual` | Uso manual via API e notebooks |

### 17.2 Allowlist

Cada team deve enxergar apenas aliases aprovados.

Allowlist inicial sugerida:

| Team | Aliases |
|---|---|
| `rag` | `lab-chat-default`, `lab-chat-fallback`, `lab-embedding-default`, `lab-embedding-fallback` |
| `devtools` | `lab-chat-default`, `lab-chat-fast`, `lab-chat-reasoning`, `lab-chat-fallback` |
| `openhands` | `lab-chat-default`, `lab-chat-reasoning`, `lab-chat-fallback` |
| `manual` | Todos os aliases, exceto os que forem marcados como experimentais |

### 17.3 Denylist

Denylist nao e obrigatoria no MVP.

### 17.4 Budgets

Budgets devem existir por virtual key e team, mas valores iniciais devem ser definidos no bootstrap operacional.

### 17.5 Rate limits

Rate limits iniciais devem ser conservadores e ajustados apos observacao real.

## 18. Criterios de aceite

### 18.1 GitOps

- `clusters/platform/wave-6-ai/litellm/` existe com `app.yaml`, `Chart.yaml`, `values.yaml` e templates necessarios.
- Chart oficial do LiteLLM esta configurado como dependencia com versao fixada.
- Imagem LiteLLM esta configurada com tag fixada.
- `make template` renderiza sem erro.
- `make validate` passa com kubeconform ou registra excecoes justificadas para CRDs.
- `make yamllint` passa.

### 18.2 Runtime

- ArgoCD sincroniza a app na wave 6.
- Namespace `litellm` e criado ou usado corretamente.
- 2 replicas ficam ready.
- Readiness e liveness probes funcionam.
- LiteLLM conecta ao Postgres externo.
- LiteLLM conecta ao Valkey.
- LiteLLM carrega config de modelos e aliases.
- `https://litellm.platform.the-lab.zone` responde via Traefik.

### 18.3 API

- Chamada OpenAI-compatible com virtual key funciona.
- Chamada sem virtual key falha.
- Chamada com modelo real nao aprovado falha ou nao aparece ao consumidor.
- Chamada com `lab-chat-default` funciona.
- Chamada com `lab-chat-fallback` tenta local primeiro e usa fallback cloud quando local falha.
- Chamada com `lab-embedding-default` funciona.
- LightRAG consegue usar LiteLLM para chat e embeddings.

### 18.4 Admin e policies

- Admin UI esta acessivel.
- Master Key autentica administracao.
- Virtual key de cada consumidor MVP e criada.
- Budgets por team/key podem ser configurados.
- Rate limits podem ser configurados.
- Spend tracking registra tokens, custos e metadados operacionais.
- Prompts/completions nao sao armazenados.

### 18.5 Observabilidade

- ServiceMonitor existe.
- VictoriaMetrics coleta metricas.
- Dashboard Grafana basico existe ou e documentado como entrega imediata do MVP.
- Alertas minimos existem ou sao definidos como manifests versionados.

## 19. Plano de implementacao

1. Validar versao atual do chart oficial e imagem LiteLLM.
2. Fixar chart e imagem no `Chart.yaml` e `values.yaml`.
3. Criar app GitOps em `clusters/platform/wave-6-ai/litellm/`.
4. Criar `ExternalSecret` para `litellm-env`.
5. Criar config LiteLLM com aliases, providers, retries, timeouts e fallback simples.
6. Configurar Postgres externo e Valkey.
7. Configurar IngressRoute Traefik sem Authelia.
8. Configurar ServiceMonitor.
9. Renderizar e validar manifests.
10. Sincronizar via ArgoCD.
11. Criar virtual keys e teams iniciais.
12. Testar chat, embeddings, fallback, rate limit e spend tracking.
13. Atualizar LightRAG para usar LiteLLM.
14. Criar dashboard Grafana e alertas minimos.

## 20. Riscos e mitigacoes

| Risco | Impacto | Mitigacao |
|---|---|---|
| Admin UI exposta sem Authelia | Acesso administrativo depende apenas da Master Key | Master Key forte, segredo em Infisical, rotacao planejada |
| Chart oficial beta | Drift ou campos instaveis | Fixar versao, validar render, manter templates complementares |
| Ollama local indisponivel | Falha em consumidores | Fallback para OpenRouter |
| OpenRouter indisponivel | Perda de fallback cloud | Alertas, possibilidade futura de segundo provider |
| Banco indisponivel | Perda de admin, virtual keys e tracking | Alertas, estrategia existente de backup/restore |
| Valkey indisponivel | Rate limit/cache operacional degradado | Alertas e comportamento de fallback validado |
| Cardinalidade alta de metricas | Custo de observabilidade | Limitar labels por key/team se necessario |
| Armazenamento acidental de prompts | Risco de privacidade e segredos | Desabilitar callbacks de logging de conteudo, validar config |
| Tags flutuantes | Drift e risco de supply chain | Pin de tag/digest e verificacao de assinatura |

## 21. Referencias

- LiteLLM Docker, Kubernetes e Helm: `https://docs.litellm.ai/docs/proxy/deploy`
- LiteLLM Virtual Keys: `https://docs.litellm.ai/docs/proxy/virtual_keys`
- LiteLLM Fallbacks: `https://docs.litellm.ai/docs/proxy/reliability`
- LiteLLM Caching: `https://docs.litellm.ai/docs/proxy/caching`
- LiteLLM Prometheus metrics: `https://docs.litellm.ai/docs/proxy/prometheus`
- LiteLLM GitHub releases e assinatura de imagem: `https://github.com/BerriAI/litellm/releases`
