# ArgoCD install and port-forward (requires HELM and KUBECTL)
KUBECTL ?= kubectl
ARGOCD_NAMESPACE ?= argocd
ARGOCD_RELEASE ?= argocd
ARGOCD_HELM_REPO ?= https://argoproj.github.io/argo-helm
ARGOCD_PORT ?= 8080

.PHONY: argocd argocd-install argocd-port-forward argocd-cluster-config

# Instala ArgoCD no cluster e inicia port-forward (Ctrl+C encerra o port-forward).
argocd: argocd-install

argocd-install:
	$(HELM) repo add argo $(ARGOCD_HELM_REPO) 2>/dev/null || true
	$(HELM) repo update
	$(HELM) upgrade --install $(ARGOCD_RELEASE) argo/argo-cd \
		--namespace $(ARGOCD_NAMESPACE) \
		--create-namespace
	$(KUBECTL) wait --for=condition=available deployment/argocd-server \
		-n $(ARGOCD_NAMESPACE) --timeout=300s

argocd-port-forward:
	@echo "ArgoCD UI: https://localhost:$(ARGOCD_PORT) (admin / senha: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={.data.password} | base64 -d)"
	$(KUBECTL) port-forward svc/argocd-server -n $(ARGOCD_NAMESPACE) $(ARGOCD_PORT):443

# Configura o cluster in-cluster do ArgoCD com o nome real e a label managed.
argocd-cluster-config:
	@set -euo pipefail; \
	CLUSTER_NAME=$$($(KUBECTL) config get-contexts --no-headers | awk '$$1 == "*" {print $$3}'); \
	echo "==> Configuring in-cluster as $$CLUSTER_NAME"; \
	$(KUBECTL) -n $(ARGOCD_NAMESPACE) create secret generic in-cluster \
		--from-literal=name="$$CLUSTER_NAME" \
		--from-literal=server=https://kubernetes.default.svc \
		--dry-run=client -o yaml \
	| $(KUBECTL) label --local -f - \
		argocd.argoproj.io/secret-type=cluster \
		lab.the-lab.zone/managed=true \
		--overwrite -o yaml \
	| $(KUBECTL) apply -f -
