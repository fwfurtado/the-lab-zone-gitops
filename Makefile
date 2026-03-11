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

.PHONY: template validate clean yamllint bootstrap

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
