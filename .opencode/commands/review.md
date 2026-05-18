---
description: Revisa o diff atual com o infra-reviewer
agent: infra-reviewer
---

Revisa o diff atual deste repositório GitOps.

Execute primeiro para obter o diff:
!`git diff HEAD`

Se o diff estiver vazio, use os últimos commits:
!`git diff HEAD~1 HEAD`

Foque nos arquivos YAML alterados. Use o checklist completo do agente infra-reviewer.
