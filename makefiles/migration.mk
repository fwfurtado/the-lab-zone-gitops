# Migration helper targets
# Run these before committing the repository restructuring.
# Requires: op (1Password CLI), openssl, kubectl, kubeseal

KUBECTL ?= kubectl

.PHONY: migration-1password-items migration-seal-cloudflare migration-prerequisites
.PHONY: migration-validate-wave0 migration-validate-wave1 migration-validate-wave2
.PHONY: migration-validate-wave3 migration-validate-wave4 migration-validate-wave5
.PHONY: migration-init-databases migration-validate-minio-buckets
.PHONY: migration-dns-cutover-node migration-validate-dns

# ============================================================================
# Phase 0 — Prerequisites
# ============================================================================

migration-1password-items:
	@set -euo pipefail; \
	echo "==> Creating 1Password items in vault 'homelab'"; \
	echo "--- Authelia Postgres"; \
	op item create --vault homelab --category login \
		--title "Authelia Postgres" \
		"password=$$(openssl rand -hex 32)"; \
	echo "--- Forgejo Postgres"; \
	op item create --vault homelab --category login \
		--title "Forgejo Postgres" \
		"password=$$(openssl rand -hex 32)"; \
	echo "--- Valkey"; \
	op item create --vault homelab --category login \
		--title "Valkey" \
		"password=$$(openssl rand -hex 32)"; \
	echo "--- Authelia OIDC secrets"; \
	op item create --vault homelab --category login \
		--title "Authelia OIDC" \
		"hmac-secret=$$(openssl rand -hex 32)" \
		"jwt-secret=$$(openssl rand -hex 32)"; \
	echo "--- Authelia OIDC JWK (RSA 4096)"; \
	tmp=$$(mktemp); openssl genrsa 4096 > $$tmp 2>/dev/null; \
	op item create --vault homelab --category "Secure Note" \
		--title "Authelia OIDC JWK" \
		"private key=$$(cat $$tmp)"; \
	rm -f $$tmp; \
	echo "--- ArgoCD Authelia OAuth"; \
	op item create --vault homelab --category login \
		--title "ArgoCD Authelia OAuth" \
		"client-secret=$$(openssl rand -hex 32)"; \
	echo "--- Grafana Authelia OAuth"; \
	op item create --vault homelab --category login \
		--title "Grafana Authelia OAuth" \
		"client-secret=$$(openssl rand -hex 32)"; \
	echo "--- Forgejo Authelia OAuth"; \
	op item create --vault homelab --category login \
		--title "Forgejo Authelia OAuth" \
		"client-secret=$$(openssl rand -hex 32)"; \
	echo "==> All 1Password items created"

migration-seal-cloudflare:
	@set -euo pipefail; \
	echo "==> Generating Cloudflare API token SealedSecret"; \
	tmp_key=$$(mktemp); tmp_cert=$$(mktemp); \
	op read "op://homelab/K8s Platforms Sealed Secret Key/private key" > $$tmp_key; \
	if grep -q "BEGIN OPENSSH PRIVATE KEY" $$tmp_key; then \
		ssh-keygen -p -m PEM -f $$tmp_key -P "" -N "" >/dev/null; \
	fi; \
	openssl req -new -x509 -key $$tmp_key -out $$tmp_cert -subj "/CN=sealed-secrets"; \
	CF_TOKEN=$$(op read "op://development/Cloudflare/the-lab.zone"); \
	$(KUBECTL) -n cert-manager create secret generic cloudflare-api-token \
		--from-literal=api-token="$$CF_TOKEN" \
		--dry-run=client -o yaml \
	| kubeseal --format yaml --cert $$tmp_cert \
	> clusters/platform/wave-1-tls/cert-manager/templates/cloudflare-sealedsecret.yaml; \
	rm -f $$tmp_key $$tmp_cert; \
	echo "==> SealedSecret written to clusters/platform/wave-1-tls/cert-manager/templates/cloudflare-sealedsecret.yaml"

migration-prerequisites: migration-1password-items migration-seal-cloudflare
	@echo "==> Migration prerequisites complete"
	@echo "    Next: review generated files, then commit and push"

# ============================================================================
# Phase 2 — Wave-by-wave validation
# ============================================================================

migration-validate-wave0:
	@set -euo pipefail; \
	echo "==> Validating Wave 0 — CNI and networking"; \
	echo "--- Cilium pods"; \
	$(KUBECTL) get pods -n kube-system -l app.kubernetes.io/name=cilium-agent --no-headers; \
	echo "--- MetalLB speaker pods"; \
	$(KUBECTL) get pods -n metallb-system --no-headers; \
	echo "--- IPAddressPools"; \
	$(KUBECTL) get ipaddresspools -n metallb-system; \
	echo "--- Prometheus Operator CRDs"; \
	$(KUBECTL) get crd servicemonitors.monitoring.coreos.com --no-headers; \
	echo "==> Wave 0 validation complete"

migration-validate-wave1:
	@set -euo pipefail; \
	echo "==> Validating Wave 1 — TLS"; \
	echo "--- cert-manager pods"; \
	$(KUBECTL) get pods -n cert-manager --no-headers; \
	echo "--- ClusterIssuer"; \
	$(KUBECTL) get clusterissuers letsencrypt-cloudflare; \
	echo "--- Certificates"; \
	$(KUBECTL) get certificates -A; \
	echo "--- Wildcard secrets replicated to traefik namespace"; \
	$(KUBECTL) get secret infra-wildcard-tls -n traefik --no-headers 2>/dev/null && echo "  infra-wildcard-tls OK" || echo "  MISSING: infra-wildcard-tls in traefik"; \
	$(KUBECTL) get secret platform-wildcard-tls -n traefik --no-headers 2>/dev/null && echo "  platform-wildcard-tls OK" || echo "  MISSING: platform-wildcard-tls in traefik"; \
	echo "--- Reflector pods"; \
	$(KUBECTL) get pods -n reflector --no-headers; \
	echo "--- Sealed Secrets pods"; \
	$(KUBECTL) get pods -n sealed-secrets --no-headers; \
	echo "==> Wave 1 validation complete"

migration-validate-wave2:
	@set -euo pipefail; \
	echo "==> Validating Wave 2 — Infra base"; \
	echo "--- CoreDNS pods"; \
	$(KUBECTL) get pods -n dns --no-headers; \
	echo "--- CoreDNS service IP"; \
	$(KUBECTL) get svc -n dns -o wide --no-headers; \
	echo "--- DNS resolution: nas.the-lab.zone"; \
	dig +short @10.40.2.2 nas.the-lab.zone || echo "  FAILED"; \
	echo "--- DNS resolution: argocd.platform.the-lab.zone"; \
	dig +short @10.40.2.2 argocd.platform.the-lab.zone || echo "  FAILED"; \
	echo "--- Infisical pods"; \
	$(KUBECTL) get pods -n infisical --no-headers; \
	echo "--- Infisical HTTPS"; \
	curl -sk https://infisical.infra.the-lab.zone -o /dev/null -w "  status: %{http_code}\n" 2>/dev/null || echo "  FAILED (may need DNS)"; \
	echo "--- External Secrets operator"; \
	$(KUBECTL) get pods -n external-secrets --no-headers; \
	echo "--- ClusterSecretStore"; \
	$(KUBECTL) get clustersecretstore infisical; \
	echo "--- Democratic CSI"; \
	$(KUBECTL) get pods -n democratic-csi --no-headers; \
	echo "--- StorageClass"; \
	$(KUBECTL) get storageclass truenas-nfs --no-headers; \
	echo "--- Monitoring: VM Operator"; \
	$(KUBECTL) get pods -n monitoring -l app.kubernetes.io/name=victoria-metrics-operator --no-headers; \
	echo "--- Monitoring: VMSingle"; \
	$(KUBECTL) get pods -n monitoring -l app.kubernetes.io/name=vmsingle --no-headers; \
	echo "--- Monitoring: VMAgent"; \
	$(KUBECTL) get pods -n monitoring -l app.kubernetes.io/name=vmagent --no-headers; \
	echo "--- Monitoring: VictoriaLogs"; \
	$(KUBECTL) get pods -n monitoring -l app.kubernetes.io/name=victoria-logs-single --no-headers; \
	echo "--- Monitoring: VictoriaTraces"; \
	$(KUBECTL) get pods -n monitoring -l app.kubernetes.io/name=victoria-traces --no-headers; \
	echo "--- Monitoring: kube-state-metrics"; \
	$(KUBECTL) get pods -n monitoring -l app.kubernetes.io/name=kube-state-metrics --no-headers; \
	echo "--- Monitoring: node-exporter"; \
	$(KUBECTL) get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter --no-headers; \
	echo "--- Monitoring: VLogs Collector DaemonSet"; \
	$(KUBECTL) get ds -n monitoring -l app.kubernetes.io/name=victoria-logs-collector --no-headers; \
	echo "==> Wave 2 validation complete"

migration-validate-wave3:
	@set -euo pipefail; \
	echo "==> Validating Wave 3 — Ingress and backup"; \
	echo "--- Traefik pods"; \
	$(KUBECTL) get pods -n traefik --no-headers; \
	echo "--- Traefik service IP"; \
	$(KUBECTL) get svc -n traefik -o wide --no-headers; \
	echo "--- HTTPS connectivity (Traefik)"; \
	curl -sk https://10.40.2.1 -o /dev/null -w "  HTTPS status: %{http_code}\n" || echo "  FAILED"; \
	echo "--- ExternalDNS pods"; \
	$(KUBECTL) get pods -n external-dns --no-headers; \
	echo "--- Velero pods"; \
	$(KUBECTL) get pods -n velero --no-headers; \
	echo "--- Velero backup location"; \
	$(KUBECTL) get backupstoragelocations -n velero; \
	echo "==> Wave 3 validation complete"

migration-validate-wave4:
	@set -euo pipefail; \
	echo "==> Validating Wave 4 — Platform services"; \
	echo "--- CloudNativePG operator"; \
	$(KUBECTL) get pods -n cloudnativepg -l app.kubernetes.io/name=cloudnativepg --no-headers; \
	echo "--- Postgres cluster"; \
	$(KUBECTL) get clusters -n cloudnativepg; \
	echo "--- Valkey"; \
	$(KUBECTL) get pods -n valkey --no-headers; \
	echo "--- MinIO"; \
	$(KUBECTL) get pods -n minio --no-headers; \
	echo "--- Authelia"; \
	$(KUBECTL) get pods -n authelia --no-headers; \
	echo "--- Authelia HTTPS"; \
	curl -sk https://auth.infra.the-lab.zone -o /dev/null -w "  status: %{http_code}\n" 2>/dev/null || echo "  FAILED (may need DNS)"; \
	echo "--- Forgejo"; \
	$(KUBECTL) get pods -n forgejo --no-headers; \
	echo "--- Forgejo HTTPS"; \
	curl -sk https://git.infra.the-lab.zone -o /dev/null -w "  status: %{http_code}\n" 2>/dev/null || echo "  FAILED (may need DNS)"; \
	echo "--- Zot"; \
	$(KUBECTL) get pods -n zot --no-headers; \
	echo "--- Grafana"; \
	$(KUBECTL) get pods -n grafana --no-headers; \
	echo "==> Wave 4 validation complete"

migration-validate-wave5:
	@set -euo pipefail; \
	echo "==> Validating Wave 5 — GitOps"; \
	echo "--- ArgoCD pods"; \
	$(KUBECTL) get pods -n argocd --no-headers; \
	echo "--- ArgoCD HTTPS"; \
	curl -sk https://argocd.platform.the-lab.zone -o /dev/null -w "  status: %{http_code}\n" 2>/dev/null || echo "  FAILED"; \
	echo "--- All ArgoCD applications"; \
	$(KUBECTL) get applications -n argocd; \
	echo "==> Wave 5 validation complete"

# ============================================================================
# Phase 2 — Wave 4 post-deploy initialization
# ============================================================================

migration-init-databases:
	@set -euo pipefail; \
	echo "==> Creating databases in CloudNativePG"; \
	PG_PRIMARY=$$($(KUBECTL) get pods -n cloudnativepg -l cnpg.io/cluster=platform-postgres,role=primary -o name | head -1); \
	AUTHELIA_PW=$$(op read "op://homelab/Authelia Postgres/password"); \
	FORGEJO_PW=$$(op read "op://homelab/Forgejo Postgres/password"); \
	echo "--- Creating authelia database and user"; \
	$(KUBECTL) exec -n cloudnativepg $$PG_PRIMARY -- psql -U postgres -c \
		"CREATE USER authelia WITH PASSWORD '$$AUTHELIA_PW'; CREATE DATABASE authelia OWNER authelia;" 2>&1 || true; \
	echo "--- Creating forgejo database and user"; \
	$(KUBECTL) exec -n cloudnativepg $$PG_PRIMARY -- psql -U postgres -c \
		"CREATE USER forgejo WITH PASSWORD '$$FORGEJO_PW'; CREATE DATABASE forgejo OWNER forgejo;" 2>&1 || true; \
	echo "==> Database initialization complete"

migration-validate-minio-buckets:
	@set -euo pipefail; \
	echo "==> Validating MinIO buckets"; \
	MINIO_POD=$$($(KUBECTL) get pods -n minio -l app=minio -o name | head -1); \
	$(KUBECTL) exec -n minio $$MINIO_POD -- mc alias set local http://localhost:9000 $$MINIO_ROOT_USER $$MINIO_ROOT_PASSWORD 2>/dev/null || true; \
	for bucket in forgejo velero postgres-backups; do \
		echo "--- Checking bucket: $$bucket"; \
		$(KUBECTL) exec -n minio $$MINIO_POD -- mc ls local/$$bucket 2>&1 && echo "  OK" || echo "  MISSING"; \
	done; \
	echo "==> MinIO bucket validation complete (buckets are auto-created by Helm values)"

# ============================================================================
# Phase 3 — DNS cutover
# ============================================================================

# Usage: make migration-dns-cutover-node NODE=10.40.0.201
migration-dns-cutover-node:
ifndef NODE
	$(error NODE is required. Usage: make migration-dns-cutover-node NODE=10.40.0.201)
endif
	@set -euo pipefail; \
	echo "==> Patching DNS on node $(NODE)"; \
	talosctl patch machineconfig --nodes $(NODE) --patch '[{"op": "replace", "path": "/machine/network/nameservers", "value": ["10.40.2.2", "1.1.1.1"]}]'; \
	echo "--- Waiting 10s for config to apply..."; \
	sleep 10; \
	echo "--- Validating DNS resolution from node $(NODE)"; \
	talosctl -n $(NODE) read /etc/resolv.conf; \
	echo "==> Node $(NODE) DNS cutover complete"

migration-validate-dns:
	@set -euo pipefail; \
	echo "==> Validating DNS across all nodes"; \
	for node in $$($(KUBECTL) get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do \
		echo "--- Node $$node"; \
		talosctl -n $$node read /etc/resolv.conf 2>&1 | grep nameserver || echo "  FAILED to read resolv.conf"; \
	done; \
	echo "==> DNS validation complete"

# ============================================================================
# Phase 4 — Decommissioning (run after all services validated)
# ============================================================================

# Update Velero S3 backend from external Garage LXC to in-cluster Garage.
# After running this, commit the change and let ArgoCD sync.
migration-velero-switch-minio:
	@echo "==> Velero S3 backend already points to in-cluster MinIO"
	@echo "    Verify: kubectl get backupstoragelocations -n velero -o yaml | grep s3Url"
	@echo "    Expected: http://minio.minio.svc.cluster.local:9000"
	@echo "    Validate: make migration-validate-wave3"

# Decommissioning order (safest first):
#   1. Caddy       — replaced by Traefik TLS termination
#   2. Step-CA     — replaced by cert-manager + Let's Encrypt
#   3. Grafana     — after in-cluster Grafana confirmed
#   4. Valkey      — after Authelia using in-cluster Valkey
#   5. PostgreSQL  — after Authelia + Forgejo on CloudNativePG
#   6. Authelia    — after in-cluster Authelia OIDC verified
#   7. Forgejo     — after in-cluster Forgejo confirmed
#   8. Zot         — after make zot-sync + Talos registry mirrors updated
#   9. CoreDNS     — after 48h with in-cluster CoreDNS stable
#  10. (Garage LXC no longer relevant — MinIO runs in-cluster)
#
# TrueNAS monitoring (not an LXC, runs directly on TrueNAS):
#  11. VMSingle + VLogsSingle on TrueNAS (10.40.1.60:8428 / 10.40.1.60:9428)
#      — replaced by in-cluster VMSingle + VLogs + VictoriaTraces
#      — decommission after wave 2 validation confirms in-cluster stack is healthy
#      — stop the services on TrueNAS, verify Grafana datasources work, wait 48h
#
# For each LXC:
#   1. Stop the LXC on Proxmox
#   2. Validate dependent services still work
#   3. Wait 24h
#   4. Remove the stack from fwfurtado/the-lab-zone-iac:
#        cd ../the-lab-zone-iac
#        atmos terraform destroy <stack-name> --auto-approve
#        git rm stacks/<stack>.yaml
#        git commit -m "remove <service> LXC stack (migrated to cluster)"
#
# NEVER decommission: Tailscale LXC (backdoor recovery)
