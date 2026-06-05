# PRD Tecnico: LightRAG com Qdrant e Neo4j

## 1. Resumo

Este PRD define a implementacao do LightRAG como plataforma de Knowledge RAG no cluster Kubernetes GitOps do The Lab Zone, consumindo Qdrant como vector database e Neo4j como knowledge graph database.

O objetivo e entregar uma aplicacao LightRAG operacional, acessivel por API e UI, capaz de indexar documentos tecnicos, persistir embeddings no Qdrant, persistir o grafo no Neo4j e servir consultas RAG para usuarios e agentes internos.

A arquitetura alvo usa storages especializados:

| Responsabilidade | Sistema |
|---|---|
| API, UI, ingestao, extracao, retrieval e orquestracao GraphRAG | LightRAG |
| Embeddings, vetores de chunks, entidades e relacoes | Qdrant |
| Knowledge graph, entidades e relacionamentos | Neo4j |
| KV, cache, chunks, metadados de documentos e status de processamento | Valkey/Redis |
| LLM e embeddings | Ollama, OpenAI-compatible APIs ou vLLM futuro |

LightRAG nao substitui Qdrant nem Neo4j. Ele passa a ser o servico consumidor e orquestrador que conecta as capacidades de vector search e graph retrieval.

Decisoes principais:

- LightRAG deve ser implantado em `clusters/platform/wave-6-ai/lightrag/`.
- Qdrant permanece como vector database autoritativo.
- Neo4j permanece como graph database autoritativo.
- Valkey existente deve ser usado como backend Redis-compatible para KV e doc status no MVP.
- A API/UI do LightRAG deve ser exposta por Traefik em `lightrag.platform.the-lab.zone`.
- O acesso externo deve ser protegido por Authelia, e chamadas programaticas devem usar `LIGHTRAG_API_KEY`.
- Login nativo do LightRAG via `AUTH_ACCOUNTS` fica desabilitado no MVP.
- Conexoes com Qdrant, Neo4j e Valkey devem ser internas ao cluster.
- Credenciais devem vir de Infisical via External Secrets Operator.
- A implantacao deve seguir o padrao GitOps do repositorio.

## 2. Objetivos

### 2.1 Objetivos de produto

- Disponibilizar uma plataforma Knowledge RAG operacional para o The Lab Zone.
- Permitir indexacao de documentacao tecnica, runbooks, ADRs, repositorios Git e Obsidian Vault.
- Permitir consultas em linguagem natural sobre infraestrutura, GitOps, Kubernetes, Talos, Cilium, Forgejo, Actions, Qdrant, Neo4j e demais componentes do lab.
- Fornecer uma camada consumivel por Fernando, Claude Code, OpenHands, agentes SRE autonomos, clientes MCP e APIs internas.
- Melhorar respostas RAG usando combinacao de busca vetorial, grafo de conhecimento, entidades, relacoes e chunks fontes.

### 2.2 Objetivos tecnicos

- Implantar LightRAG como workload Kubernetes gerenciado por ArgoCD.
- Usar Qdrant com `QdrantVectorDBStorage`.
- Usar Neo4j com `Neo4JStorage`.
- Usar Valkey com `RedisKVStorage` e `RedisDocStatusStorage`.
- Configurar workspace unico inicial para isolamento logico dos dados.
- Expor UI/API HTTPS via Traefik.
- Proteger a borda com Authelia.
- Habilitar autenticacao de API do LightRAG.
- Persistir dados operacionais necessarios do LightRAG em PVC apenas quando o backend exigir filesystem local.
- Configurar requests/limits, probes e observabilidade basica.
- Documentar endpoints, secrets e operacao inicial.

## 3. Fora de escopo

- Treinamento ou fine-tuning de modelos.
- Deploy inicial de vLLM, reranker dedicado, MinerU ou Docling.
- UI customizada alem da UI nativa do LightRAG.
- Multi-tenancy real por usuario, equipe ou dominio.
- Integracao MCP final.
- Automacao completa de ingestao Git/Forgejo/Obsidian via pipelines externos.
- RBAC granular dentro do LightRAG.
- Alta disponibilidade do LightRAG no MVP.
- Alta disponibilidade adicional para Neo4j ou Qdrant.
- Reindexacao automatica por mudanca de modelo de embedding.
- Avaliacao RAGAS/Langfuse no MVP.

## 4. Consumidores previstos

| Consumidor | Uso esperado |
|---|---|
| Fernando | Uso da UI e API para ingestao manual, consultas e administracao inicial |
| Claude Code | Consumo futuro via API ou MCP |
| OpenHands | Consumo futuro via API ou MCP |
| Agentes SRE autonomos | Consulta de contexto operacional, dependencias e runbooks |
| Clientes MCP | Interface futura para ferramentas de AI |
| APIs internas | Consultas programaticas e integracoes |

## 5. Requisitos funcionais

### 5.1 API e UI

- O LightRAG deve expor UI/API em `https://lightrag.platform.the-lab.zone`.
- A UI deve permitir upload manual ou ingestao inicial de documentos suportados.
- A API deve permitir consultas RAG autenticadas.
- A API deve permitir ingestao programatica de textos/documentos no MVP, se suportado pela API nativa.
- A aplicacao deve responder a health checks internos.

### 5.2 Indexacao

- O LightRAG deve processar documentos textuais e Markdown no MVP.
- O LightRAG deve gerar chunks conforme configuracao versionada.
- O LightRAG deve chamar o provedor de embeddings configurado.
- O LightRAG deve gravar vetores no Qdrant.
- O LightRAG deve extrair entidades e relacoes via LLM.
- O LightRAG deve gravar grafo no Neo4j.
- O LightRAG deve registrar status de documentos no backend de doc status.

### 5.3 Consulta

- O LightRAG deve suportar consultas usando modos nativos como `naive`, `local`, `global`, `hybrid` e `mix`, conforme disponiveis na versao adotada.
- O modo padrao inicial deve ser `mix`, salvo se testes mostrarem latencia ou qualidade inadequadas.
- As respostas devem incluir contexto recuperado e referencias quando a API/versao suportar.
- A plataforma deve preservar proveniencia minima por documento/chunk.

## 6. Arquitetura de storage

LightRAG possui quatro categorias principais de storage. A implementacao do MVP deve usar:

| Storage LightRAG | Implementacao | Backend |
|---|---|---|
| `LIGHTRAG_KV_STORAGE` | `RedisKVStorage` | Valkey |
| `LIGHTRAG_DOC_STATUS_STORAGE` | `RedisDocStatusStorage` | Valkey |
| `LIGHTRAG_VECTOR_STORAGE` | `QdrantVectorDBStorage` | Qdrant |
| `LIGHTRAG_GRAPH_STORAGE` | `Neo4JStorage` | Neo4j |

Justificativa:

- Qdrant ja e o vector database da plataforma.
- Neo4j ja e o graph database da plataforma.
- Valkey ja existe no cluster, possui persistencia e evita depender de JSON local em PVC para KV/status.
- O filesystem do pod fica menos critico e pode ser usado apenas para diretorios auxiliares, cache local e staging.

### 6.1 Qdrant

Conexao interna esperada:

```text
http://qdrant.qdrant.svc.cluster.local:6333
```

Requisitos:

- LightRAG deve usar Qdrant apenas para vetores.
- Colecoes devem ser criadas e gerenciadas pelo LightRAG, salvo necessidade operacional contraria.
- O embedding model e a dimensao vetorial devem ser definidos antes da primeira indexacao.
- Mudanca de embedding model deve exigir reindexacao planejada.

### 6.2 Neo4j

Conexao interna esperada:

```text
neo4j://neo4j.neo4j.svc.cluster.local:7687
```

Requisitos:

- LightRAG deve usar o endpoint interno Bolt, nao o endpoint externo via Traefik.
- Credenciais devem vir do Secret `neo4j-credentials` ou de Secret proprio do LightRAG sincronizado do Infisical.
- Neo4j deve armazenar grafo, entidades, relacoes e metadados de grafo produzidos pelo LightRAG.
- Neo4j nao deve armazenar embeddings no MVP.

### 6.3 Valkey

Conexao interna esperada:

```text
redis://:<password>@valkey-primary.valkey.svc.cluster.local:6379/3
```

Requisitos:

- Usar database Redis separado para LightRAG, inicialmente DB `3`, para evitar colisao com Forgejo e outros consumidores.
- A senha deve vir de Infisical/ESO.
- Valkey deve manter persistencia habilitada.
- Chaves devem usar workspace/prefixo do LightRAG.

## 7. Modelos e providers

### 7.1 LLM

Providers suportados no MVP:

- Ollama.
- OpenAI-compatible API.
- vLLM futuro.

Configuracao inicial recomendada:

| Papel | Binding | Observacao |
|---|---|---|
| Query | OpenAI-compatible ou Ollama | Modelo com boa janela de contexto |
| Extract | OpenAI-compatible ou Ollama | Modelo com boa extracao de entidades/relacoes |
| Keyword | Mesmo provider da query ou modelo menor | Otimizacao futura |
| VLM | Desabilitado no MVP | Ativar em fase posterior para PDFs/imagens |

### 7.2 Embeddings

Modelos candidatos:

- BGE-M3.
- Nomic Embed.
- Jina Embeddings.

Decisao de MVP:

- A dimensao do embedding deve ser fixada antes da primeira ingestao.
- O nome do modelo, dimensao e provider devem ser documentados no `values.yaml`.
- Mudancas posteriores exigem reindexacao completa ou uma estrategia explicita de colecoes paralelas.

### 7.3 Reranking

Reranking fica opcional no MVP.

Recomendacao:

- Manter `RERANK_BINDING=null` inicialmente.
- Avaliar `BAAI/bge-reranker-v2-m3` via vLLM em fase posterior.

## 8. Kubernetes e GitOps

### 8.1 Localizacao

LightRAG deve ser adicionado em:

```text
clusters/platform/wave-6-ai/lightrag/
```

Estrutura esperada:

```text
lightrag/
  app.yaml
  Chart.yaml
  values.yaml
  templates/
    deployment.yaml
    service.yaml
    ingressroute.yaml
    external-secret.yaml
    servicemonitor.yaml
    pvc.yaml
```

### 8.2 ArgoCD

`app.yaml` proposto:

```yaml
app:
  name: lightrag
  namespace: lightrag
  syncWave: "6"
```

Justificativa:

- LightRAG pertence a wave de AI junto de Qdrant e Neo4j.
- Qdrant, Neo4j e Valkey ja devem existir quando LightRAG iniciar.
- Caso haja problema de ordem dentro da mesma wave, LightRAG deve usar probes/retries e ArgoCD health normal, ou receber sync wave posterior dentro da propria app se o padrao do repositorio suportar.

### 8.3 Chart

Decisao:

- Usar chart local derivado do chart de exemplo oficial em `k8s-deploy/lightrag`.
- Preservar a estrutura base do chart oficial: `Deployment`, `Service`, `PVC`, helpers e `.env` montado em `/app/.env`.
- Adaptar o chart ao padrao do repositorio com `app.yaml`, `ExternalSecret`, `IngressRoute`, `ServiceMonitor`, storageClass `proxmox-lvm` e secrets via Infisical/ESO.
- Fixar imagem em tag explicita, evitando `latest`.
- Referencia do chart base: https://github.com/HKUDS/LightRAG/tree/main/k8s-deploy/lightrag

### 8.4 Imagem

Requisitos:

- A imagem deve conter o servidor API do LightRAG.
- A imagem deve incluir dependencias para Qdrant, Neo4j e Redis/Valkey.
- A tag deve ser fixada.
- A origem da imagem deve ser documentada.

Imagem inicial:

```text
ghcr.io/hkuds/lightrag:v1.5.0rc3
```

### 8.5 Recursos

Sizing inicial:

| Recurso | Request | Limit |
|---|---:|---:|
| CPU | `500m` | `2000m` |
| Memoria | `1Gi` | `4Gi` |

Notas:

- Indexacao e extracao podem exigir mais memoria dependendo do tamanho dos documentos.
- Limites devem ser revistos apos ingestao real dos primeiros documentos.

### 8.6 Storage local

Mesmo usando backends externos, LightRAG pode precisar de diretorios locais para input, working dir, logs, cache ou staging.

PVC proposto:

| Campo | Valor |
|---|---|
| StorageClass | `proxmox-lvm` |
| Tamanho inicial | `20Gi` |
| Access mode | `ReadWriteOnce` |

Diretorios esperados:

```text
/app/data/inputs
/app/data/rag_storage
/app/data/tiktoken
/app/data/logs
```

### 8.7 Networking

- UI/API externa em `lightrag.platform.the-lab.zone`.
- Entrada via Traefik `websecure`.
- TLS via wildcard `platform-wildcard-tls`.
- Authelia na borda para acesso humano.
- `LIGHTRAG_API_KEY` para acesso programatico.
- Qdrant, Neo4j e Valkey acessados apenas por service interno.

### 8.8 Secrets

Secrets devem ser sincronizados por External Secrets Operator a partir do Infisical.

Secret Kubernetes esperado:

```text
lightrag-credentials
```

Chaves recomendadas:

| Chave | Uso |
|---|---|
| `LIGHTRAG_API_KEY` | Autenticacao da API |
| `LLM_BINDING_API_KEY` | Chave do provider LLM, quando necessario |
| `EMBEDDING_BINDING_API_KEY` | Chave do provider de embedding, quando necessario |
| `NEO4J_USERNAME` | Usuario Neo4j |
| `NEO4J_PASSWORD` | Senha Neo4j |
| `REDIS_PASSWORD` | Senha Valkey |
| `QDRANT_API_KEY` | Reservado caso Qdrant passe a exigir API key |

Nenhum segredo deve ser armazenado em texto puro no Git.

## 9. Configuracao inicial

Variaveis de ambiente propostas:

```text
HOST=0.0.0.0
PORT=9621
WORKING_DIR=/app/data/rag_storage
INPUT_DIR=/app/data/inputs
TIKTOKEN_CACHE_DIR=/app/data/tiktoken
LOG_DIR=/app/data/logs
LOG_LEVEL=INFO

WORKSPACE=the_lab_zone
SUMMARY_LANGUAGE=Portuguese

LIGHTRAG_KV_STORAGE=RedisKVStorage
LIGHTRAG_DOC_STATUS_STORAGE=RedisDocStatusStorage
LIGHTRAG_VECTOR_STORAGE=QdrantVectorDBStorage
LIGHTRAG_GRAPH_STORAGE=Neo4JStorage

REDIS_URI=redis://:${REDIS_PASSWORD}@valkey-primary.valkey.svc.cluster.local:6379/3
QDRANT_URL=http://qdrant.qdrant.svc.cluster.local:6333
NEO4J_URI=neo4j://neo4j.neo4j.svc.cluster.local:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=${NEO4J_PASSWORD}

RERANK_BINDING=null
ENTITY_EXTRACTION_USE_JSON=true
MAX_PARALLEL_INSERT=2
MAX_ASYNC_LLM=4
EMBEDDING_FUNC_MAX_ASYNC=8
EMBEDDING_BATCH_NUM=16
```

Nota: os nomes exatos das variaveis de conexao de Qdrant, Neo4j e Redis/Valkey devem ser validados contra o `env.example` da tag LightRAG fixada na implementacao. O PRD fixa a intencao arquitetural e os endpoints internos esperados.

Variaveis de modelo devem ser definidas na implementacao conforme provider escolhido:

```text
LLM_BINDING=<ollama|openai>
LLM_BINDING_HOST=<endpoint>
LLM_MODEL=<modelo>
LLM_BINDING_API_KEY=<secret>

EMBEDDING_BINDING=<ollama|openai|jina>
EMBEDDING_BINDING_HOST=<endpoint>
EMBEDDING_MODEL=<modelo>
EMBEDDING_DIM=<dimensao>
EMBEDDING_TOKEN_LIMIT=<limite>
EMBEDDING_BINDING_API_KEY=<secret>
```

## 10. Seguranca

### 10.1 Acesso externo

- UI/API externa protegida por Authelia.
- LightRAG deve manter autenticacao propria habilitada para API.
- API key deve ser obrigatoria para consumidores programaticos fora de sessoes humanas.

### 10.2 Acesso interno

- LightRAG deve acessar Qdrant, Neo4j e Valkey por DNS interno Kubernetes.
- Bolt externo do Neo4j nao deve ser usado pelo LightRAG.
- Futuras NetworkPolicies devem permitir apenas os fluxos necessarios.

Fluxos internos:

| Origem | Destino | Porta | Protocolo |
|---|---|---:|---|
| LightRAG | Qdrant | `6333` | HTTP |
| LightRAG | Neo4j | `7687` | Bolt |
| LightRAG | Valkey | `6379` | Redis |
| Traefik | LightRAG | `9621` | HTTP |

### 10.3 Dados sensiveis

Embora nao haja expectativa inicial de dados regulados, a base de conhecimento contem contexto interno do lab. Portanto:

- Logs nao devem expor prompts completos com segredos.
- Secrets nao devem aparecer em argumentos de comando.
- Uploads devem ser tratados como dados internos.
- Backups devem ser controlados.

## 11. Observabilidade

### 11.1 Metricas

Metricas obrigatorias:

- CPU.
- Memoria.
- Restart count.
- Latencia HTTP.
- Taxa de erros HTTP 4xx/5xx.
- Tempo de ingestao por documento, se exposto.
- Tamanho da fila ou status de processamento, se exposto.
- Latencia de chamadas para LLM/embedding, se exposto.

### 11.2 Logs

Logs devem permitir diagnosticar:

- Erros de conexao com Qdrant.
- Erros de conexao com Neo4j.
- Erros de conexao com Valkey.
- Falhas de autenticacao.
- Falhas de ingestao.
- Timeouts de LLM/embedding.

### 11.3 Dashboards

Dashboard Grafana basico:

- Saude do pod.
- Uso de CPU/memoria.
- Latencia e taxa de erro HTTP.
- Reinicios.
- Volume de ingestao.
- Capacidade do PVC.

### 11.4 Alertas

Alertas minimos:

- Pod indisponivel.
- Reinicios frequentes.
- PVC acima de 80%.
- PVC acima de 90%.
- HTTP 5xx sustentado.
- Falha persistente de conexao com Qdrant.
- Falha persistente de conexao com Neo4j.
- Falha persistente de conexao com Valkey.

## 12. Backup e restore

### 12.1 Escopo de backup

LightRAG depende de multiplos backends. O restore completo exige consistencia entre:

- Qdrant.
- Neo4j.
- Valkey.
- PVC local do LightRAG, se houver dados necessarios.

### 12.2 Politica MVP

| Componente | Backup |
|---|---|
| Neo4j | Ja definido no PRD de Neo4j via `neo4j-admin database dump` |
| Qdrant | Snapshot/export conforme mecanismo do Qdrant ou backup de PVC, a definir |
| Valkey | Persistencia propria + backup do PVC ou mecanismo existente |
| LightRAG PVC | Velero ou backup de volume, se dados locais forem necessarios |

RPO/RTO alvo inicial:

| Campo | Valor |
|---|---|
| RPO | 24 horas |
| RTO | 4 horas |

Pergunta aberta:

- Como garantir consistencia temporal entre backups de Qdrant, Neo4j e Valkey?

## 13. Ingestao MVP

### 13.1 Fontes iniciais

MVP:

- Markdown documentation.
- Runbooks.
- ADRs.
- Obsidian Vault exportado ou sincronizado.
- Repositorios Forgejo selecionados.

Futuro:

- PDFs.
- Tickets.
- Wikis.
- Logs operacionais curados.

### 13.2 Modelo operacional inicial

MVP deve suportar ingestao manual ou semi-manual:

- Upload pela UI, quando suficiente.
- Chamada de API para documentos Markdown.
- Job Kubernetes ou workflow futuro para sincronizar repositorios.

Automacao completa fica fora do MVP deste PRD, mas o design deve permitir evoluir para pipeline GitOps/batch.

### 13.3 Regras iniciais

- Comecar com corpus pequeno e conhecido.
- Validar qualidade antes de indexar grandes volumes.
- Registrar embedding model usado.
- Nao trocar embedding model sem plano de reindexacao.
- Usar workspace unico `the_lab_zone`.

## 14. Performance e escala

### 14.1 Escala inicial

| Item | Valor inicial |
|---|---:|
| Documentos | ate 10.000 |
| Usuarios/agentes concorrentes | menos de 20 |
| Tamanho inicial do PVC LightRAG | 20Gi |
| Latencia alvo de consulta simples | ate 5 segundos |
| Latencia alvo de consulta complexa | ate 15 segundos |

### 14.2 Concorrencia

Configuracao inicial conservadora:

```text
WORKERS=1
MAX_PARALLEL_INSERT=2
MAX_ASYNC_LLM=4
EMBEDDING_FUNC_MAX_ASYNC=8
EMBEDDING_BATCH_NUM=16
```

Revisar apos testes com corpus real.

## 15. Milestones

### M1 - Design e scaffold GitOps

- Criar PRD aprovado.
- Definir chart local ou upstream.
- Criar app `lightrag` em `wave-6-ai`.
- Definir `values.yaml`, `ExternalSecret`, `Deployment`, `Service`, `IngressRoute`, PVC e probes.
- Definir imagem e tag fixada.
- Definir variaveis de ambiente iniciais.

### M2 - Deploy base

- LightRAG sincronizado pelo ArgoCD.
- Namespace `lightrag` criado.
- Pod sobe com probes saudaveis.
- UI/API acessivel em `lightrag.platform.the-lab.zone`.
- Authelia protege acesso externo.
- `LIGHTRAG_API_KEY` configurada para chamadas programaticas.

### M3 - Conectividade com backends

- LightRAG conecta no Qdrant internamente.
- LightRAG conecta no Neo4j internamente.
- LightRAG conecta no Valkey internamente.
- Health check operacional confirma dependencias.
- Logs nao mostram falhas persistentes de storage.

### M4 - Primeira indexacao

- Indexar conjunto pequeno de documentos Markdown.
- Confirmar colecoes no Qdrant.
- Confirmar dados no Neo4j.
- Confirmar status/cache no Valkey.
- Executar consultas `naive`, `local`, `global`, `hybrid` e `mix`, conforme disponiveis.

### M5 - Operacao minima

- Dashboard Grafana inicial.
- Alertas basicos.
- Procedimento de backup/restore documentado.
- Procedimento de reindexacao documentado.
- Endpoints e secrets documentados.

## 16. Criterios de aceite

### 16.1 Plataforma

- LightRAG esta definido em Git no padrao do repositorio.
- LightRAG fica em `clusters/platform/wave-6-ai/lightrag/`.
- ArgoCD sincroniza a aplicacao sem drift.
- O workload sobe em namespace `lightrag`.
- Nenhum segredo sensivel esta em texto puro no Git.
- UI/API esta acessivel por `lightrag.platform.the-lab.zone`.
- Acesso externo passa por Traefik e Authelia.
- `LIGHTRAG_API_KEY` esta configurada para chamadas programaticas.

### 16.2 Storage

- `LIGHTRAG_VECTOR_STORAGE=QdrantVectorDBStorage`.
- `LIGHTRAG_GRAPH_STORAGE=Neo4JStorage`.
- `LIGHTRAG_KV_STORAGE=RedisKVStorage`.
- `LIGHTRAG_DOC_STATUS_STORAGE=RedisDocStatusStorage`.
- LightRAG usa Qdrant interno em `qdrant.qdrant.svc.cluster.local`.
- LightRAG usa Neo4j interno em `neo4j.neo4j.svc.cluster.local`.
- LightRAG usa Valkey interno em `valkey-primary.valkey.svc.cluster.local`.

### 16.3 Funcional

- Um documento Markdown pode ser ingerido com sucesso.
- Vetores sao criados no Qdrant.
- Entidades/relacoes sao criadas no Neo4j.
- Status do documento e gravado no backend configurado.
- Uma consulta RAG retorna resposta usando o documento ingerido.
- A resposta inclui contexto ou referencias quando suportado pela API.

### 16.4 Operacional

- Pod reinicia sem perder estado relevante.
- Logs nao contem segredos.
- Dashboard basico existe.
- Alertas basicos existem.
- Procedimento de restore esta documentado.
- Mudanca de embedding model esta documentada como operacao de reindexacao.

## 17. Dependencias

- Cluster Kubernetes Talos existente.
- ArgoCD ApplicationSet existente.
- Traefik operacional.
- Authelia operacional.
- cert-manager e wildcard TLS refletido.
- Infisical e External Secrets Operator.
- StorageClass `proxmox-lvm`.
- Qdrant operacional em `wave-6-ai`.
- Neo4j operacional em `wave-6-ai`.
- Valkey operacional em `wave-5-platform`.
- Provider LLM inicial definido.
- Provider de embedding inicial definido.

## 18. Riscos e mitigacoes

| Risco | Impacto | Mitigacao |
|---|---|---|
| Embedding model trocado apos indexacao | Vetores existentes ficam incompativeis | Fixar modelo/dimensao antes da ingestao; documentar reindexacao |
| KV/doc status em Valkey sem backup consistente | Perda de estado operacional | Garantir persistencia Valkey e incluir no plano de backup |
| Inconsistencia entre Qdrant, Neo4j e Valkey no restore | Consultas ou status quebrados | Definir janela de backup coordenada e teste de restore |
| LLM local insuficiente para extracao | Grafo de baixa qualidade | Permitir OpenAI-compatible API para extract ou modelo maior |
| Indexacao consumir muitos recursos | Degradacao do cluster | Limitar concorrencia inicial e aumentar gradualmente |
| Authelia interferir em API programatica | Agentes nao conseguem consumir API | Separar rotas ou usar API key com whitelisting controlado se necessario |
| Versao LightRAG mudar variaveis de ambiente | Deploy quebra ou ignora configuracao | Fixar imagem e validar `env.example` da versao escolhida |
| Qdrant sem API key interna | Acesso lateral no cluster | Avaliar auth interna/NetworkPolicy em fase posterior |

## 19. Decisoes registradas

- LightRAG sera o orquestrador de ingestao, extracao, retrieval e resposta.
- Qdrant sera o vector storage do LightRAG.
- Neo4j sera o graph storage do LightRAG.
- Valkey sera usado para KV e doc status no MVP.
- O endpoint externo do Neo4j Bolt nao sera usado pelo LightRAG.
- A exposicao externa do LightRAG sera HTTPS via Traefik.
- Authelia sera usada na borda.
- `LIGHTRAG_API_KEY` sera usada para chamadas programaticas.
- `AUTH_ACCOUNTS` e login nativo do LightRAG ficam desabilitados no MVP.
- A imagem inicial sera `ghcr.io/hkuds/lightrag:v1.5.0rc3`.
- O chart local sera derivado do exemplo oficial `k8s-deploy/lightrag`.
- Reranking fica fora do MVP obrigatorio.
- Multimodal/PDF avancado fica para fase posterior.

## 20. Perguntas em aberto

- Qual provider LLM sera usado no MVP: Ollama, OpenAI-compatible ou ambos?
- Qual embedding model e dimensao serao adotados antes da primeira indexacao?
- A API publica deve passar por Authelia ou tera rota interna separada para agentes?
- Como sera feito backup consistente entre Qdrant, Neo4j e Valkey?
- Qual corpus inicial sera usado para a primeira indexacao validada?
- Havera um job GitOps/batch para ingestao de Obsidian/Forgejo no MVP ou isso fica para fase posterior?

## 21. Referencias

- LightRAG API Server: https://github.com/HKUDS/LightRAG/blob/main/docs/LightRAG-API-Server.md
- LightRAG README: https://github.com/HKUDS/LightRAG
- LightRAG `env.example`: https://raw.githubusercontent.com/HKUDS/LightRAG/main/env.example
- Qdrant GraphRAG com Neo4j: https://qdrant.tech/documentation/examples/graphrag-qdrant-neo4j/
- PRD Neo4j local: `docs/neo4j-knowledge-rag-prd.md`
