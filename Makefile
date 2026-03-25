SHELL := /bin/bash

HELM ?= helm
KUBECONFORM ?= kubeconform
BUILD_DIR ?= build
KUBECONFORM_FLAGS ?= -summary -strict -ignore-missing-schemas
KUBECONFORM_SCHEMA_LOCATIONS ?= -schema-location default \
	-schema-location https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/crd/bases/metallb.io_ipaddresspools.yaml \
	-schema-location https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/crd/bases/metallb.io_l2advertisements.yaml \
	-schema-location https://raw.githubusercontent.com/external-secrets/external-secrets/v0.15.1/deploy/crds/bundle.yaml

CHART_DIRS := $(sort $(dir $(wildcard clusters/*/*/*/Chart.yaml)))

include makefiles/bootstrap.mk
include makefiles/migration.mk
include makefiles/yamllint.mk
include makefiles/zot.mk

.PHONY: template validate clean yamllint bootstrap oidc-hash infisical-init-folders infisical-push-secrets

# Aplica o Secret do repositório, a chave do Sealed Secrets e aplica o bootstrap/root.yaml.
# Após o bootstrap, execute `make bootstrap-seal-infisical-secrets` e depois
# `make bootstrap-seal-infisical-credentials` (após configurar o Infisical).
bootstrap: bootstrap-secrets bootstrap-sealed-secrets-key bootstrap-app

template:
	@set -euo pipefail; \
	mkdir -p "$(BUILD_DIR)"; \
	for dir in $(CHART_DIRS); do \
		name=$$(basename "$$dir"); \
		echo "==> helm template $$dir"; \
		"$(HELM)" dependency build "$$dir" >/dev/null; \
		"$(HELM)" template "$$name" "$$dir" -f "$$dir/values.yaml" --include-crds > "$(BUILD_DIR)/$$name.yaml"; \
	done

validate:
	@set -euo pipefail; \
	for dir in $(CHART_DIRS); do \
		name=$$(basename "$$dir"); \
		echo "==> validate $$dir"; \
		"$(HELM)" dependency build "$$dir" >/dev/null; \
		"$(HELM)" template "$$name" "$$dir" -f "$$dir/values.yaml" --include-crds | "$(KUBECONFORM)" $(KUBECONFORM_FLAGS) $(KUBECONFORM_SCHEMA_LOCATIONS); \
	done

clean:
	@rm -rf "$(BUILD_DIR)"

# Gera um client secret OIDC e seu hash PBKDF2 para uso no Authelia.
# Uso: make oidc-hash
#   ou: make oidc-hash PASSWORD=my-secret
oidc-hash:
	@if [ -z "$(PASSWORD)" ]; then \
		PASSWORD=$$(openssl rand -base64 32); \
		echo "Generated secret: $$PASSWORD"; \
	else \
		PASSWORD="$(PASSWORD)"; \
		echo "Using provided secret"; \
	fi; \
	echo ""; \
	echo "Hash:"; \
	docker run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --password "$$PASSWORD"

# Cria todos os folders necessários no Infisical (projeto homelab, environment prod).
# Executar após o Infisical estar rodando e a Machine Identity configurada.
# Uso: make infisical-init-folders
INFISICAL_API ?= http://localhost:8080
INFISICAL_FOLDERS := \
	/ \
	/argocd \
	/argo-workflows \
	/authelia \
	/cloudflare \
	/coder \
	/coder/personal \
	/coder/work \
	/database \
	/database/authelia \
	/database/coder \
	/database/forgejo \
	/database/infisical \
	/forgejo \
	/grafana \
	/minio \
	/minio-truenas \
	/rustdesk \
	/valkey

infisical-init-folders:
	@CLIENT_ID=$$(kubectl -n external-secrets get secret infisical-credentials -o jsonpath='{.data.clientId}' | base64 -d); \
	CLIENT_SECRET=$$(kubectl -n external-secrets get secret infisical-credentials -o jsonpath='{.data.clientSecret}' | base64 -d); \
	echo "Autenticando no Infisical..."; \
	TOKEN=$$(curl -sf -X POST "$(INFISICAL_API)/api/v1/auth/universal-auth/login" \
		-H "Content-Type: application/json" \
		-d "{\"clientId\":\"$$CLIENT_ID\",\"clientSecret\":\"$$CLIENT_SECRET\"}" \
		| jq -r '.accessToken'); \
	if [ -z "$$TOKEN" ] || [ "$$TOKEN" = "null" ]; then \
		echo "Erro: falha na autenticação"; exit 1; \
	fi; \
	echo "Buscando workspace ID..."; \
	WORKSPACE_ID=$$(curl -sf "$(INFISICAL_API)/api/v1/workspace" \
		-H "Authorization: Bearer $$TOKEN" \
		| jq -r '.workspaces[] | select(.slug == "homelab") | .id'); \
	if [ -z "$$WORKSPACE_ID" ] || [ "$$WORKSPACE_ID" = "null" ]; then \
		echo "Erro: workspace 'homelab' não encontrado"; exit 1; \
	fi; \
	echo "Workspace ID: $$WORKSPACE_ID"; \
	echo "Criando folders..."; \
	for env in prod dev staging; do \
		echo "  Environment: $$env"; \
		for folder in $(INFISICAL_FOLDERS); do \
			PARENT=$$(dirname "$$folder"); \
			NAME=$$(basename "$$folder"); \
			if [ "$$folder" = "/" ]; then continue; fi; \
			if [ "$$PARENT" = "/" ]; then PARENT="/"; fi; \
			echo "    $$folder"; \
			curl -sf -X POST "$(INFISICAL_API)/api/v1/folders" \
				-H "Content-Type: application/json" \
				-H "Authorization: Bearer $$TOKEN" \
				-d "{\"workspaceId\":\"$$WORKSPACE_ID\",\"environment\":\"$$env\",\"name\":\"$$NAME\",\"path\":\"$$PARENT\"}" \
				>/dev/null 2>&1 || true; \
		done; \
	done; \
	echo "Folders criados!"

# Popula todos os secrets no Infisical a partir do 1Password.
# Requer: op (1Password CLI autenticado), kubectl, curl, jq
# Requer: port-forward para o Infisical (kubectl -n infisical port-forward svc/infisical-... 8080:8080)
# Uso: make infisical-push-secrets
infisical-push-secrets:
	@CLIENT_ID=$$(kubectl -n external-secrets get secret infisical-credentials -o jsonpath='{.data.clientId}' | base64 -d); \
	CLIENT_SECRET=$$(kubectl -n external-secrets get secret infisical-credentials -o jsonpath='{.data.clientSecret}' | base64 -d); \
	echo "Autenticando no Infisical..."; \
	TOKEN=$$(curl -sf -X POST "$(INFISICAL_API)/api/v1/auth/universal-auth/login" \
		-H "Content-Type: application/json" \
		-d "{\"clientId\":\"$$CLIENT_ID\",\"clientSecret\":\"$$CLIENT_SECRET\"}" \
		| jq -r '.accessToken'); \
	if [ -z "$$TOKEN" ] || [ "$$TOKEN" = "null" ]; then \
		echo "Erro: falha na autenticação"; exit 1; \
	fi; \
	echo "Buscando workspace ID..."; \
	WORKSPACE_ID=$$(curl -sf "$(INFISICAL_API)/api/v1/workspace" \
		-H "Authorization: Bearer $$TOKEN" \
		| jq -r '.workspaces[] | select(.slug == "homelab") | .id'); \
	if [ -z "$$WORKSPACE_ID" ] || [ "$$WORKSPACE_ID" = "null" ]; then \
		echo "Erro: workspace 'homelab' não encontrado"; exit 1; \
	fi; \
	TOTAL=$$(jq length bootstrap/infisical-secrets.tpl.json); \
	echo "Criando $$TOTAL secrets no Infisical..."; \
	CREATED=0; SKIPPED=0; FAILED=0; \
	for i in $$(seq 0 $$((TOTAL - 1))); do \
		PATH_=$$(jq -r ".[$${i}].path" bootstrap/infisical-secrets.tpl.json); \
		KEY=$$(jq -r ".[$${i}].key" bootstrap/infisical-secrets.tpl.json); \
		OP_REF=$$(jq -r ".[$${i}].value" bootstrap/infisical-secrets.tpl.json); \
		if echo "$$OP_REF" | grep -q '^op://'; then \
			VALUE=$$(op read "$$OP_REF" 2>/dev/null); \
			if [ $$? -ne 0 ]; then \
				echo "  FAIL: $$PATH_/$$KEY (op read failed for $$OP_REF)"; \
				FAILED=$$((FAILED + 1)); \
				continue; \
			fi; \
		else \
			VALUE="$$OP_REF"; \
		fi; \
		TMP_BODY=$$(mktemp); \
		jq -n \
			--arg wid "$$WORKSPACE_ID" \
			--arg env "prod" \
			--arg path "$$PATH_" \
			--arg val "$$VALUE" \
			'{workspaceId: $$wid, environment: $$env, secretPath: $$path, secretValue: $$val, type: "shared"}' \
			> "$$TMP_BODY"; \
		RESULT=$$(curl -s -o /dev/null -w "%{http_code}" -X POST "$(INFISICAL_API)/api/v3/secrets/raw/$${KEY}" \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer $$TOKEN" \
			-d @"$$TMP_BODY"); \
		rm -f "$$TMP_BODY"; \
		if [ "$$RESULT" = "200" ]; then \
			echo "  OK: $$PATH_/$$KEY"; \
			CREATED=$$((CREATED + 1)); \
		elif [ "$$RESULT" = "400" ]; then \
			echo "  SKIP: $$PATH_/$$KEY (already exists)"; \
			SKIPPED=$$((SKIPPED + 1)); \
		else \
			echo "  FAIL: $$PATH_/$$KEY (HTTP $$RESULT)"; \
			FAILED=$$((FAILED + 1)); \
		fi; \
	done; \
	echo ""; \
	echo "Resultado: $$CREATED criados, $$SKIPPED existentes, $$FAILED falhas"
