# Cilium install via Helm (requires HELM and KUBECTL)
KUBECTL ?= kubectl
CILIUM_NAMESPACE ?= kube-system
CILIUM_RELEASE ?= cilium
CILIUM_CHART_DIR ?= clusters/platform/cilium

.PHONY: cilium cilium-install

cilium: prometheus-crds cilium-install

# Instala Cilium no cluster usando o chart local (wrapper com dependency).
cilium-install:
	$(HELM) repo add cilium https://helm.cilium.io 2>/dev/null || true
	$(HELM) repo update
	$(HELM) dependency build $(CILIUM_CHART_DIR)
	$(HELM) upgrade --install $(CILIUM_RELEASE) $(CILIUM_CHART_DIR) \
		--namespace $(CILIUM_NAMESPACE) \
		--create-namespace \
		-f $(CILIUM_CHART_DIR)/values.yaml
	$(KUBECTL) wait --for=condition=available deployment/cilium-operator \
		-n $(CILIUM_NAMESPACE) --timeout=300s

prometheus-crds:
	$(HELM) repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
	$(HELM) repo update
	$(HELM) upgrade --install prometheus-operator-crds prometheus-community/prometheus-operator-crds \
		--namespace prometheus-operator-crds \
		--create-namespace
