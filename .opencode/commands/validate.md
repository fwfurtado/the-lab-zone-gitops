---
description: Valida um chart — helm lint + template + kubeconform. Uso: /validate <app-name>
agent: build
---

Valida o chart do app: $ARGUMENTS

Passos:
1. Encontrar o diretório: !`find clusters/ -name "Chart.yaml" | xargs grep -l "" | xargs -I{} dirname {} | grep "$ARGUMENTS"`
2. Executar: !`helm lint $(find clusters/ -name "Chart.yaml" | xargs grep -l "" | xargs -I{} dirname {} | grep "$ARGUMENTS" | head -1) 2>&1`
3. Executar: !`make template 2>&1 | grep -A5 "$ARGUMENTS"`
4. Executar: !`make validate 2>&1 | grep -A5 "$ARGUMENTS"`

Reporte warnings e erros encontrados. Se não encontrar o chart, liste os disponíveis em clusters.
