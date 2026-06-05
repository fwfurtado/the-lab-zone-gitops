# PRD Tecnico: Neo4j como Infraestrutura para Knowledge RAG

## 1. Resumo

Este PRD define a implementacao de Neo4j como componente de infraestrutura para uma futura plataforma de Knowledge RAG baseada em LightRAG, executada no cluster Kubernetes GitOps do The Lab Zone.

O escopo deste PRD e provisionar, expor, proteger, observar e operar Neo4j como banco de knowledge graph. A ingestao de documentos, extracao de entidades, extracao de relacionamentos, orquestracao GraphRAG e integracao especifica com LightRAG ficam fora deste PRD.

A arquitetura alvo continua dual-store:

| Responsabilidade | Sistema |
|---|---|
| Embeddings e busca semantica | Qdrant |
| Knowledge graph, entidades, relacoes, metadados e proveniencia | Neo4j |
| Ingestao, extracao e GraphRAG | LightRAG ou servico consumidor futuro |

Neo4j nao substitui o Qdrant e nao armazena embeddings no MVP. Ele deve ser implantado como infraestrutura pronta para ser consumida por LightRAG, agentes internos, APIs e clientes MCP.

Decisoes principais:

- Neo4j Community Edition em single instance.
- Helm chart oficial `neo4j/neo4j`.
- Versao fixada do chart/app: `2026.05.0`.
- Qdrant permanece como vector database autoritativo.
- Neo4j armazena apenas grafo, metadados e provenance.
- Backup logico via `neo4j-admin database dump`.
- Backup armazenado no AiStore/MinIO interno, seguindo o padrao do CronJob de backup do Forgejo.
- Bolt permanece interno ao cluster para LightRAG e consumidores Kubernetes, e tambem e exposto externamente via Traefik TCP para uso administrativo do Neo4j Browser.
- Neo4j Browser exposto via Traefik HTTPS sem Authelia; Browser e Bolt externo sao protegidos pela autenticacao nativa do Neo4j.
- Secrets via Infisical + External Secrets Operator.
- APOC entra no MVP.
- Graph Data Science fica para fase posterior.

## 2. Objetivos

### 2.1 Objetivos de produto

- Disponibilizar uma base de knowledge graph persistente para a futura plataforma LightRAG.
- Criar uma camada de grafo capaz de armazenar entidades, relacionamentos, metadados e proveniencia.
- Permitir exploracao manual inicial via Neo4j Browser.
- Fornecer uma dependencia padronizada para Claude Code, OpenHands, agentes SRE autonomos, clientes MCP e APIs internas.

### 2.2 Objetivos tecnicos

- Implantar Neo4j Community Edition como workload stateful no cluster Kubernetes Talos.
- Organizar Neo4j na wave de AI da plataforma, junto de Qdrant.
- Seguir o padrao existente do repositorio: `app.yaml`, `Chart.yaml`, `values.yaml`, `templates/` e ArgoCD sync wave.
- Usar o chart oficial `neo4j/neo4j` fixado em `2026.05.0`.
- Usar `proxmox-lvm` como StorageClass.
- Gerenciar credenciais por Infisical e External Secrets Operator.
- Expor Neo4j Browser em `neo4j.platform.the-lab.zone` via Traefik.
- Proteger o acesso externo ao Browser com autenticacao nativa do Neo4j.
- Manter Bolt interno ao cluster para LightRAG e consumidores Kubernetes.
- Expor Bolt externamente via Traefik TCP em `neo4j.platform.the-lab.zone:7687` para permitir uso administrativo do Neo4j Browser.
- Implementar observabilidade basica com VictoriaMetrics/Grafana.
- Definir backup diario via `neo4j-admin database dump`, com RPO de 24 horas e RTO de 4 horas.
- Suportar evolucao de schema via migracoes Cypher versionadas em Git.

## 3. Fora de escopo

- Deploy ou configuracao do LightRAG.
- Pipeline de ingestao.
- Extracao de entidades ou relacionamentos.
- Deduplicacao/entity resolution.
- Chunking de documentos.
- Criacao de embeddings.
- Recuperacao GraphRAG.
- API de consulta RAG.
- Contrato MCP final.
- Neo4j Enterprise Edition.
- Alta disponibilidade ou cluster Neo4j.
- Armazenamento de embeddings no Neo4j.
- UI rica de exploracao de conhecimento.
- Multi-tenancy.
- RBAC granular por equipe, dominio ou tenant.
- OIDC nativo no Neo4j.
- Graph Data Science como requisito mandatorio.

## 4. Consumidores previstos

| Consumidor | Uso esperado |
|---|---|
| LightRAG | Persistencia e consulta do knowledge graph |
| Claude Code | Consumo indireto via LightRAG, MCP ou API futura |
| OpenHands | Consumo indireto via LightRAG, MCP ou API futura |
| Agentes SRE autonomos | Consulta futura de contexto, dependencias e runbooks |
| Clientes MCP | Interface futura para leitura do knowledge graph |
| APIs internas | Integracao programatica futura |
| Fernando | Exploracao e administracao via Neo4j Browser |

## 5. Requisitos funcionais da infraestrutura

### 5.1 Neo4j

- O servico deve aceitar conexoes internas via Bolt.
- O Browser deve estar acessivel via HTTPS externo.
- A autenticacao nativa deve estar habilitada.
- APOC deve estar disponivel para consumidores que precisem de operacoes utilitarias.
- O banco deve persistir dados em PVC.
- O banco deve suportar criacao de constraints e indices via migracoes Cypher.

### 5.2 Contrato minimo para consumidores

Este PRD nao define a ingestao, mas Neo4j deve estar pronto para armazenar os tipos de dados que LightRAG ou outro consumidor venha a gravar.

Requisitos de prontidao:

- Credenciais disponiveis em Secret Kubernetes.
- Service interno estavel para Bolt.
- Endpoint HTTPS para Browser.
- PVC persistente.
- Backup e restore definidos.
- Observabilidade basica ativa.
- Mecanismo para aplicar migracoes Cypher.

## 6. Modelo de dados base

Nao existe ontologia inicial fechada. O PRD deve preparar Neo4j para receber uma ontologia evolutiva, mas sem implementar pipeline de populacao do grafo.

### 6.1 Labels iniciais recomendadas

| Label | Descricao |
|---|---|
| `Document` | Documento fonte referenciado por consumidores futuros |
| `Chunk` | Trecho de documento referenciado por consumidores futuros |
| `Repository` | Repositorio Git de origem |
| `Service` | Servico exposto ou interno |
| `Application` | Aplicacao implantada ou referenciada |
| `Cluster` | Cluster Kubernetes ou ambiente |
| `Technology` | Tecnologia, framework, produto ou protocolo |
| `Tool` | Ferramenta operacional ou de desenvolvimento |
| `Runbook` | Documento procedural de operacao |
| `Person` | Pessoa referenciada |
| `Component` | Parte tecnica de um sistema |

### 6.2 Relacoes iniciais recomendadas

| Relacao | Origem -> Destino | Uso |
|---|---|---|
| `CONTAINS` | `Document` -> `Chunk` | Vincular chunks ao documento |
| `FROM_REPOSITORY` | `Document` -> `Repository` | Rastrear origem Git |
| `MENTIONS` | `Document` ou `Chunk` -> qualquer entidade | Registrar mencoes |
| `DESCRIBES` | `Document` ou `Chunk` -> entidade | Indicar que a fonte descreve a entidade |
| `DEPENDS_ON` | entidade -> entidade | Dependencia tecnica ou operacional |
| `USES` | entidade -> `Technology` ou `Tool` | Uso de tecnologia/ferramenta |
| `RUNS_ON` | `Application` ou `Service` -> `Cluster` | Local de execucao |
| `RELATED_TO` | entidade -> entidade | Relacao generica quando nao houver tipo especifico |

### 6.3 Propriedades recomendadas

Entidades:

- `id`: identificador estavel.
- `name`: nome normalizado.
- `type`: tipo logico quando aplicavel.
- `createdAt`: timestamp de criacao.
- `updatedAt`: timestamp da ultima atualizacao.
- `sourceSystem`: origem do dado.
- `confidence`: confianca da extracao quando aplicavel.

Documentos:

- `uri`: caminho Git, URL ou identificador canonico.
- `title`: titulo detectado ou derivado.
- `repository`: repositorio de origem.
- `commitSha`: commit ingerido.
- `contentHash`: hash do conteudo.
- `lastIndexedAt`: timestamp da ultima indexacao.

Chunks:

- `chunkId`: identificador estavel do chunk.
- `documentId`: documento pai.
- `ordinal`: posicao do chunk no documento.
- `textHash`: hash do texto do chunk.
- `startLine` e `endLine`: quando disponiveis.

Relacionamentos:

- `createdAt`.
- `updatedAt`.
- `sourceDocumentId`.
- `sourceChunkId`.
- `extractionMethod`.
- `confidence`.

## 7. Requisitos de Neo4j

| Requisito | Valor |
|---|---|
| Edicao | Neo4j Community Edition |
| Topologia | Single instance |
| Chart Helm | `neo4j/neo4j` |
| Versao fixada | `2026.05.0` |
| Plugins obrigatorios | APOC |
| Plugins fase posterior | Graph Data Science |
| Papel de Qdrant | Vector database autoritativo |
| Papel de Neo4j | Grafo, metadados e provenance |
| Exposicao HTTP | Neo4j Browser via Traefik HTTPS sem Authelia |
| Exposicao Bolt | Interna em `neo4j.neo4j.svc.cluster.local:7687` e externa via Traefik TCP em `neo4j.platform.the-lab.zone:7687` |
| Documentos previstos | ate 10.000 |
| Nos previstos | ate 100.000 |
| Relacionamentos previstos | ate 1.000.000 |
| Concorrencia prevista | menos de 20 usuarios/agentes |
| Latencia alvo | consultas operacionais abaixo de 3 segundos |

## 8. Kubernetes e GitOps

### 8.1 Avaliacao de wave

Faz sentido criar uma wave especifica para a plataforma de AI.

Justificativa:

- Qdrant e Neo4j sao datastores especializados para workloads de AI/RAG.
- Eles nao pertencem ao mesmo grupo funcional de apps genericas de plataforma como Forgejo, Coder, Grafana, Valkey, Zot e Velero.
- Ambos dependem das waves anteriores: storage, secrets, monitoring, TLS e edge.
- Manter uma wave de AI deixa claro onde novas dependencias de RAG devem entrar.
- A ordem de sincronizacao deve ser `6`, depois dos servicos gerais de plataforma e antes de GitOps.

### 8.2 Localizacao proposta

Neo4j deve ser adicionado em:

```text
clusters/platform/wave-6-ai/neo4j/
```

Qdrant deve permanecer na mesma area de AI:

```text
clusters/platform/wave-6-ai/qdrant/
```

Estrutura esperada:

```text
neo4j/
  app.yaml
  Chart.yaml
  values.yaml
  templates/
    external-secret.yaml
    ingressroute.yaml
    servicemonitor.yaml
    backup-cronjob.yaml
```

### 8.3 ArgoCD

`app.yaml` proposto:

```yaml
app:
  name: neo4j
  namespace: neo4j
  syncWave: "6"
```

### 8.4 Helm

O chart deve usar o chart oficial `neo4j/neo4j`, com versao fixada em `2026.05.0`.

Requisitos de configuracao:

- Neo4j Community Edition.
- Single instance.
- Persistencia em PVC.
- APOC habilitado.
- Graph Data Science desabilitado no MVP.
- Recursos de CPU/memoria definidos explicitamente.
- Service HTTP para Browser.
- Service Bolt interno ao cluster e IngressRouteTCP para exposicao externa via Traefik.

### 8.5 Storage

| Campo | Valor |
|---|---|
| StorageClass | `proxmox-lvm` |
| Tamanho inicial | `50Gi` |
| Access mode | `ReadWriteOnce` |
| Binding | `WaitForFirstConsumer` |

### 8.6 Networking

- HTTP/Browser exposto externamente em `neo4j.platform.the-lab.zone`, se viavel com Neo4j Community Edition.
- Acesso externo via Traefik.
- Sem middleware de Authelia no Browser.
- Sem redirect automatico de `/` para `/browser/`, para preservar o discovery JSON usado pelo protocolo `https://` do Neo4j Browser.
- Neo4j deve aceitar headers `X-Forwarded-*` do Traefik para `neo4j.platform.the-lab.zone`.
- Bolt interno ao cluster para consumidores como LightRAG.
- Bolt externo via Traefik TCP em `neo4j.platform.the-lab.zone:7687` para permitir uso administrativo do Neo4j Browser.
- Bolt externo nao deve usar Authelia; o controle de acesso fica na autenticacao nativa do Neo4j.
- Bolt nao deve ter LoadBalancer ou NodePort dedicado fora do Traefik.
- TLS externo obrigatorio via cert-manager/Traefik e certificados refletidos conforme padrao da plataforma.

### 8.7 Secrets

Credenciais devem ser armazenadas no Infisical e sincronizadas por External Secrets Operator.

Secret Kubernetes esperado:

| Chave | Uso |
|---|---|
| `NEO4J_AUTH` | Credencial nativa do Neo4j no formato esperado pelo chart |
| `NEO4J_USERNAME` | Usuario administrativo quando necessario |
| `NEO4J_PASSWORD` | Senha administrativa quando necessario |

Nenhum segredo deve ser armazenado em texto puro no Git.

## 9. Seguranca

### 9.1 Acesso

Permitido:

- Fernando.
- LightRAG.
- Agentes internos.
- MCP services.
- APIs internas autorizadas.

### 9.2 Autenticacao

MVP:

- Autenticacao nativa do Neo4j.
- Sem Authelia no Neo4j Browser.
- Bolt interno ao cluster para consumidores Kubernetes.
- Bolt externo via Traefik TCP protegido pela autenticacao nativa do Neo4j.

Futuro:

- Avaliar OIDC via Authelia caso a edicao e o modo de licenciamento adotados suportem a necessidade.

### 9.3 TLS

- TLS externo obrigatorio.
- TLS interno opcional no MVP.

### 9.4 Dados sensiveis

Nao ha expectativa inicial de dados regulados ou sensiveis. Mesmo assim, Neo4j deve ser tratado como datastore persistente de conhecimento interno e protegido por autenticacao, rede interna e backup controlado.

## 10. Observabilidade

### 10.1 Metricas obrigatorias

- CPU.
- Memoria.
- Uso de disco/PVC.
- Latencia de queries quando exposta pelo chart/exporter.
- Throughput de queries quando exposto pelo chart/exporter.
- Contagem de nos.
- Contagem de relacionamentos.
- Estado do pod.
- Reinicios do pod.

### 10.2 Dashboards

O MVP deve entregar um dashboard Grafana basico com:

- Saude do pod.
- Uso de recursos.
- Crescimento do grafo.
- Indicadores de latencia/throughput quando expostos pelo exporter/chart.
- Capacidade do PVC.

### 10.3 Alertas

Alertas minimos:

- Pod indisponivel.
- Reinicios frequentes.
- PVC acima de 80%.
- PVC acima de 90%.
- Falha no job de backup.
- Latencia de query acima do alvo por janela sustentada, se a metrica estiver disponivel.

## 11. Backup e restore

### 11.1 Politica

- Backup diario.
- RPO: 24 horas.
- RTO: 4 horas.

### 11.2 Estrategia MVP

O backup deve ser implementado como CronJob Kubernetes, seguindo o padrao do backup do Forgejo.

Fluxo esperado:

```text
CronJob
  -> initContainer executa neo4j-admin database dump
  -> dump gravado em emptyDir temporario
  -> container minio/mc envia dump para AiStore/MinIO interno
  -> dumps antigos sao removidos por politica de retencao
```

Destino:

- AiStore/MinIO interno.
- Bucket/prefixo proposto: `neo4j-backups/`.

Ferramenta de dump:

- `neo4j-admin database dump`.

Padrao de implementacao:

- CronJob em `templates/backup-cronjob.yaml`.
- `concurrencyPolicy: Forbid`.
- `activeDeadlineSeconds` definido.
- `emptyDir` para staging do dump.
- Upload com `minio/mc`.
- Credenciais do AiStore/MinIO vindas de Secret sincronizado por Infisical/ESO.

Requisitos:

- Backup automatizado diario.
- Retencao configuravel, inicialmente 30 dias.
- Alerta em caso de falha.
- Procedimento documentado de restore.
- Teste manual inicial de restore antes de considerar o MVP aceito.

Backup criptografado e desejavel, mas nao obrigatorio no MVP.

## 12. Schema e migracoes

O schema do grafo deve evoluir por migracoes Cypher versionadas em Git. O mecanismo de migracao deve ser tratado como infraestrutura de banco, nao como pipeline de ingestao.

Requisitos:

- Diretorio versionado para migracoes, por exemplo `migrations/neo4j/`.
- Nomes ordenaveis, por exemplo `0001_constraints.cypher`.
- Migracoes idempotentes quando possivel.
- Constraints e indices definidos em Git.
- Job ou processo operacional capaz de aplicar migracoes de forma controlada.

Constraints iniciais recomendadas:

```cypher
CREATE CONSTRAINT document_id IF NOT EXISTS
FOR (d:Document) REQUIRE d.id IS UNIQUE;

CREATE CONSTRAINT chunk_id IF NOT EXISTS
FOR (c:Chunk) REQUIRE c.chunkId IS UNIQUE;

CREATE CONSTRAINT repository_id IF NOT EXISTS
FOR (r:Repository) REQUIRE r.id IS UNIQUE;
```

Indices iniciais recomendados:

```cypher
CREATE INDEX entity_name IF NOT EXISTS
FOR (n:Component) ON (n.name);

CREATE INDEX document_uri IF NOT EXISTS
FOR (d:Document) ON (d.uri);
```

## 13. Milestones

### M1 - Design e scaffold GitOps

- Criar app `neo4j` em `wave-6-ai`.
- Manter Qdrant em `wave-6-ai`.
- Definir chart oficial `neo4j/neo4j` fixado em `2026.05.0`.
- Definir values, PVC, secrets e ingress.
- Definir constraints/indices iniciais.

### M2 - Deploy operacional

- Neo4j sincronizado pelo ArgoCD.
- Browser acessivel em `neo4j.platform.the-lab.zone`, se viavel com Community Edition.
- Autenticacao nativa funcionando.
- PVC `proxmox-lvm` provisionado.
- APOC habilitado.
- Bolt acessivel internamente para consumidores no cluster.

### M3 - Observabilidade e backup

- Metricas basicas coletadas.
- Dashboard Grafana inicial.
- Alertas operacionais criados.
- Backup diario via `neo4j-admin database dump` configurado.
- Upload de backup para AiStore/MinIO interno configurado.
- Restore testado manualmente.

### M4 - Prontidao para LightRAG

- Secrets e endpoints internos documentados.
- Constraints e indices iniciais aplicados.
- Procedimento de migracao Cypher definido.
- Conectividade interna validada a partir de um pod temporario ou job de teste.

## 14. Criterios de aceite

### 14.1 Plataforma

- Neo4j esta definido em Git no padrao do repositorio.
- Neo4j fica em `clusters/platform/wave-6-ai/neo4j/`.
- Qdrant fica em `clusters/platform/wave-6-ai/qdrant/`.
- `Chart.yaml` usa o chart oficial `neo4j/neo4j` fixado em `2026.05.0`.
- ArgoCD cria e sincroniza a aplicacao sem drift.
- O workload sobe em namespace `neo4j`.
- O PVC usa `proxmox-lvm` com tamanho inicial de `50Gi`.
- As credenciais sao obtidas via Infisical/ESO.
- Nenhum segredo sensivel esta em texto puro no Git.
- Neo4j Browser esta acessivel por `neo4j.platform.the-lab.zone` via Traefik, se suportado pela Community Edition no modo adotado.
- Acesso externo ao Browser nao passa por Authelia.
- Bolt fica exposto via Traefik TCP em `neo4j.platform.the-lab.zone:7687`, sem Authelia e sem LoadBalancer/NodePort dedicado.

### 14.2 Funcional

- Login no Neo4j Browser funciona com credenciais nativas.
- Um cliente interno consegue conectar via Bolt em `neo4j.neo4j.svc.cluster.local:7687`.
- O Neo4j Browser consegue executar queries usando Bolt externo em `neo4j.platform.the-lab.zone:7687`.
- APOC esta disponivel.
- Graph Data Science nao esta habilitado no MVP.
- Constraints e indices iniciais podem ser aplicados por Cypher.
- Dados gravados sobrevivem ao restart do pod.

### 14.3 Operacional

- Dashboard Grafana mostra saude e capacidade do Neo4j.
- Alertas basicos existem para disponibilidade, PVC e backup.
- Backup diario via `neo4j-admin database dump` executa com sucesso.
- Dump e enviado para AiStore/MinIO interno.
- Retencao remove backups antigos conforme politica configurada.
- Restore foi validado pelo menos uma vez.
- Consultas operacionais representativas respondem em menos de 3 segundos no volume MVP.

## 15. Dependencias

- Cluster Kubernetes Talos existente.
- ArgoCD ApplicationSet existente.
- Traefik operacional.
- cert-manager e TLS wildcard/refletido funcionando.
- Infisical e External Secrets Operator operacionais.
- StorageClass `proxmox-lvm` funcional.
- Qdrant existente na wave de AI.
- Grafana/VictoriaMetrics para observabilidade.

## 16. Riscos e mitigacoes

| Risco | Impacto | Mitigacao |
|---|---|---|
| Neo4j Community single instance indisponivel durante manutencao | LightRAG e agentes perdem a camada de grafo | Backup diario, restore documentado e aceitacao explicita de sem HA no MVP |
| Browser exposto indevidamente | Acesso nao autorizado | Autenticacao nativa do Neo4j, senha forte via Infisical e monitoramento de acesso |
| Crescimento rapido do grafo apos LightRAG entrar | Queries lentas e disco cheio | Indices, alertas de PVC e revisao de capacidade |
| Backups nao restauraveis | Perda de dados | Teste de restore como criterio de aceite |
| Chart oficial nao suportar algum template auxiliar necessario | Retrabalho na implementacao | Usar templates locais no umbrella chart para ingress, secrets, backup e observabilidade |
| APOC impactar compatibilidade ou imagem | Falha de startup | Validar startup com APOC no MVP antes de habilitar consumidores |
| Exposicao do Browser nao funcionar bem na Community Edition | Browser externo indisponivel | Usar protocolo `https://` no Browser para administracao leve |

## 17. Decisoes registradas

- Chart Helm: oficial `neo4j/neo4j`.
- Versao fixada: `2026.05.0`.
- Edicao/topologia: Neo4j Community single instance.
- Qdrant permanece como vector database.
- Neo4j armazena apenas grafo, metadados e provenance.
- Backup: logico via `neo4j-admin database dump`.
- Destino de backup: AiStore/MinIO interno.
- Padrao de backup: CronJob similar ao `forgejo-backup`.
- Bolt: interno ao cluster para LightRAG e consumidores Kubernetes; externo via Traefik TCP para administracao pelo Neo4j Browser.
- Browser: Traefik sem Authelia, com autenticacao nativa do Neo4j.
- Secrets: Infisical + External Secrets Operator.
- APOC: MVP.
- Graph Data Science: fase posterior.

## 18. Perguntas em aberto

- Qual sera o nome final do Secret consumido por LightRAG?
- Quais permissoes de rede serao exigidas quando NetworkPolicy for adotada?
- Qual sera o bucket/prefixo definitivo no AiStore/MinIO para backups do Neo4j?
