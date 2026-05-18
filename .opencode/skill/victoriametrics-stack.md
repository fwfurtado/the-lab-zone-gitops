---
name: victoriametrics-stack
description: VictoriaMetrics operator stack patterns for the-lab-zone — VMSingle, VMAgent, VLogs, VTraces, Grafana
---

## Stack no cluster

Namespace `monitoring`, release name `monitoring`, alias no Chart.yaml:
- `stack` → `victoria-metrics-k8s-stack` (operator + VMSingle + VMAgent + kube-state-metrics + node-exporter)
- `vlogs` → `victoria-logs-single`
- `log-collector` → `victoria-logs-collector`
- `vtraces` → `victoria-traces-single`

## Endpoints internos

| Serviço | Endpoint |
|---|---|
| VMSingle (métricas) | `http://vmsingle-vm-stack.monitoring.svc.cluster.local:8428` |
| VLogs | `http://vlogs.monitoring.svc.cluster.local:9428` |
| VTraces (OTLP) | `http://vtraces.monitoring.svc.cluster.local:10428/insert/opentelemetry/v1/traces` |
| VTraces (Jaeger) | `http://vtraces.monitoring.svc.cluster.local:10428` |

## ServiceMonitor → VMServiceScrape

O VictoriaMetrics Operator converte `ServiceMonitor` e `PodMonitor` automaticamente em `VMServiceScrape`/`VMPodScrape` quando `operator.disable_prometheus_converter: false` (default do repo).

**Não criar VMServiceScrape manualmente se já existe ServiceMonitor** — causará scrape duplicado.

Para apps com `serviceMonitor.enabled: true` no values.yaml da dependência upstream, o operator converte automaticamente.

## Adicionar nova app ao scraping

Opção 1 — via values do chart upstream (preferido):
```yaml
myapp:
  metrics:
    serviceMonitor:
      enabled: true
```

Opção 2 — VMServiceScrape manual (quando upstream não tem ServiceMonitor):
```yaml
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMServiceScrape
metadata:
  name: myapp
  namespace: myapp
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: myapp
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
```

## Dashboards Grafana

Grafana usa sidecar com label `grafana_dashboard: "1"`. Para adicionar dashboard:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-dashboard
  namespace: myapp          # qualquer namespace (sidecar busca em ALL)
  labels:
    grafana_dashboard: "1"
data:
  myapp.json: |
    { ... dashboard JSON ... }
```

Ou via `grafana.dashboards.community` no values do chart grafana (gnetId).

## Alertas (VMAlert — desabilitado no repo)

`vmalert.enabled: false` e `alertmanager.enabled: false` no `monitoring/values.yaml`.
Para habilitar alertas, setar `vmalert.enabled: true` e adicionar regras como `VMRule` CRDs.

## Tracing — instrumentação

Apps devem enviar traces OTLP HTTP para `http://vtraces.monitoring.svc.cluster.local:10428/insert/opentelemetry/v1/traces`.

Traefik já está configurado com:
```yaml
tracing:
  otlp:
    http:
      endpoint: http://vtraces.monitoring.svc.cluster.local:10428/insert/opentelemetry/v1/traces
```

## Retenção atual

| Dado | Retenção |
|---|---|
| Métricas (VMSingle) | 14d |
| Logs (VLogs) | 7d |
| Traces (VTraces) | 7d |
