---
description: Investiga um problema no cluster. Uso: /investigate <sintoma>
agent: k8s-investigator
---

Investiga o seguinte problema no cluster platform:

**Sintoma:** $ARGUMENTS

Siga a metodologia:
1. Colete o estado atual via MCP (não assuma nada)
2. Siga a cadeia de dependências do stack
3. Proponha fix com impacto mínimo
4. Documente root cause ao final
