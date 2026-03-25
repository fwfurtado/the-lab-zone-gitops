# Bootstrap: repo secret + sealed-secrets key + Infisical secrets + root Application
# Requires: KUBECTL, OP, OPENSSL, SSH-KEYGEN, KUBESEAL

.PHONY: bootstrap-secrets bootstrap-sealed-secrets-key bootstrap-app
.PHONY: bootstrap-seal-infisical-secrets bootstrap-seal-infisical-credentials
.PHONY: bootstrap-seal-proxmox-csi-config
.PHONY: bootstrap-seal-db-credentials bootstrap-seal-cnpg-minio-backup
.PHONY: bootstrap-seal-coder-db-url

# Aplica apenas o Secret do repo via 1Password inject (op inject).
bootstrap-secrets:
	@op inject -i bootstrap/repo-secret.tpl.yaml | $(KUBECTL) apply -f -

# Cria o sealed-secrets-key usando RSA do 1Password.
# Item: op://homelab/K8s Platforms Sealed Secret Key/private key
bootstrap-sealed-secrets-key:
	@tmp_key=$$(mktemp); tmp_cert=$$(mktemp); \
	op read "op://homelab/K8s Platforms Sealed Secret Key/private key" > $$tmp_key; \
	if grep -q "BEGIN OPENSSH PRIVATE KEY" $$tmp_key; then \
		ssh-keygen -p -m PEM -f $$tmp_key -P "" -N "" >/dev/null; \
	fi; \
	openssl req -new -x509 -key $$tmp_key -out $$tmp_cert -subj "/CN=sealed-secrets"; \
	$(KUBECTL) create namespace sealed-secrets --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
	$(KUBECTL) -n sealed-secrets create secret tls sealed-secrets-key --cert=$$tmp_cert --key=$$tmp_key --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
	rm -f $$tmp_key $$tmp_cert

# Gera o SealedSecret com AUTH_SECRET, ROOT_ENCRYPTION_KEY, SITE_URL e DB_CONNECTION_URI para o Infisical.
# KMS migration requires 32-byte key; use ROOT_ENCRYPTION_KEY (not ENCRYPTION_KEY).
# Items: op://homelab/Infisical/auth-secret, op://homelab/Infisical/root-encryption-key
#        op://homelab/Infisical Database/password
# Generate root-encryption-key with: openssl rand -base64 32
bootstrap-seal-infisical-secrets:
	@tmp_key=$$(mktemp); tmp_cert=$$(mktemp); \
	op read "op://homelab/K8s Platforms Sealed Secret Key/private key" > $$tmp_key; \
	if grep -q "BEGIN OPENSSH PRIVATE KEY" $$tmp_key; then \
		ssh-keygen -p -m PEM -f $$tmp_key -P "" -N "" >/dev/null; \
	fi; \
	openssl req -new -x509 -key $$tmp_key -out $$tmp_cert -subj "/CN=sealed-secrets"; \
	AUTH_SECRET=$$(op read "op://homelab/Infisical/auth-secret"); \
	ROOT_ENCRYPTION_KEY=$$(op read "op://homelab/Infisical/root-encryption-key"); \
	INFISICAL_DB_PASSWORD=$$(op read "op://homelab/Infisical Database/password"); \
	$(KUBECTL) -n infisical create secret generic infisical-secrets \
		--from-literal=AUTH_SECRET="$$AUTH_SECRET" \
		--from-literal=ROOT_ENCRYPTION_KEY="$$ROOT_ENCRYPTION_KEY" \
		--from-literal=SITE_URL="https://infisical.infra.the-lab.zone" \
		--from-literal=DB_CONNECTION_URI="postgresql://infisical:$${INFISICAL_DB_PASSWORD}@platform-postgres-rw.cloudnativepg.svc.cluster.local:5432/infisicalDB" \
		--dry-run=client -o yaml \
	| kubeseal --format yaml --cert $$tmp_cert \
	> clusters/platform/wave-3-secrets/infisical/templates/infisical-secrets-sealedsecret.yaml; \
	rm -f $$tmp_key $$tmp_cert

# Gera o SealedSecret com clientId e clientSecret da Machine Identity do Infisical.
# Executar APÓS o Infisical estar rodando e a Machine Identity criada.
# Items: op://homelab/Infisical/eso-client-id, op://homelab/Infisical/eso-client-secret
bootstrap-seal-infisical-credentials:
	@tmp_key=$$(mktemp); tmp_cert=$$(mktemp); \
	op read "op://homelab/K8s Platforms Sealed Secret Key/private key" > $$tmp_key; \
	if grep -q "BEGIN OPENSSH PRIVATE KEY" $$tmp_key; then \
		ssh-keygen -p -m PEM -f $$tmp_key -P "" -N "" >/dev/null; \
	fi; \
	openssl req -new -x509 -key $$tmp_key -out $$tmp_cert -subj "/CN=sealed-secrets"; \
	CLIENT_ID=$$(op read "op://homelab/Infisical/eso-client-id"); \
	CLIENT_SECRET=$$(op read "op://homelab/Infisical/eso-client-secret"); \
	$(KUBECTL) -n external-secrets create secret generic infisical-credentials \
		--from-literal=clientId="$$CLIENT_ID" \
		--from-literal=clientSecret="$$CLIENT_SECRET" \
		--dry-run=client -o yaml \
	| kubeseal --format yaml --cert $$tmp_cert \
	> clusters/platform/wave-2-infra/external-secrets/templates/infisical-credentials-sealedsecret.yaml; \
	rm -f $$tmp_key $$tmp_cert

# Gera o SealedSecret com config.yaml do Proxmox CSI Plugin.
# Items: op://homelab/k8s proxmox csi/token-id, op://homelab/k8s proxmox csi/credential
bootstrap-seal-proxmox-csi-config:
	@tmp_key=$$(mktemp); tmp_cert=$$(mktemp); tmp_config=$$(mktemp); \
	op read "op://homelab/K8s Platforms Sealed Secret Key/private key" > $$tmp_key; \
	if grep -q "BEGIN OPENSSH PRIVATE KEY" $$tmp_key; then \
		ssh-keygen -p -m PEM -f $$tmp_key -P "" -N "" >/dev/null; \
	fi; \
	openssl req -new -x509 -key $$tmp_key -out $$tmp_cert -subj "/CN=sealed-secrets"; \
	TOKEN_ID=$$(op read "op://homelab/k8s proxmox csi/token-id"); \
	CREDENTIAL=$$(op read "op://homelab/k8s proxmox csi/credential"); \
	printf 'clusters:\n  - url: "https://10.40.0.200:8006/api2/json"\n    insecure: true\n    token_id: "%s"\n    token_secret: "%s"\n    region: "homelab"\n' "$$TOKEN_ID" "$$CREDENTIAL" > $$tmp_config; \
	$(KUBECTL) -n csi-proxmox create secret generic proxmox-csi-config \
		--from-file=config.yaml=$$tmp_config \
		--dry-run=client -o yaml \
	| kubeseal --format yaml --cert $$tmp_cert \
	> clusters/platform/wave-2-infra/proxmox-csi/templates/proxmox-csi-config-sealedsecret.yaml; \
	rm -f $$tmp_key $$tmp_cert $$tmp_config

# Gera SealedSecrets com senhas de DB para o init-databases-job (cloudnativepg) e PushSecrets (infisical).
# Items: op://homelab/Infisical Database/password
#        op://homelab/Authelia Database/password
#        op://homelab/Forgejo Database/password
#        op://homelab/Coder Database/password
bootstrap-seal-db-credentials:
	@tmp_key=$$(mktemp); tmp_cert=$$(mktemp); \
	op read "op://homelab/K8s Platforms Sealed Secret Key/private key" > $$tmp_key; \
	if grep -q "BEGIN OPENSSH PRIVATE KEY" $$tmp_key; then \
		ssh-keygen -p -m PEM -f $$tmp_key -P "" -N "" >/dev/null; \
	fi; \
	openssl req -new -x509 -key $$tmp_key -out $$tmp_cert -subj "/CN=sealed-secrets"; \
	AUTHELIA_PW=$$(op read "op://homelab/Authelia Database/password"); \
	FORGEJO_PW=$$(op read "op://homelab/Forgejo Database/password"); \
	INFISICAL_PW=$$(op read "op://homelab/Infisical Database/password"); \
	CODER_PW=$$(op read "op://homelab/Coder Database/password"); \
	$(KUBECTL) -n cloudnativepg create secret generic db-init-credentials \
		--from-literal=authelia-password="$$AUTHELIA_PW" \
		--from-literal=forgejo-password="$$FORGEJO_PW" \
		--from-literal=infisical-password="$$INFISICAL_PW" \
		--from-literal=coder-password="$$CODER_PW" \
		--dry-run=client -o yaml \
	| kubeseal --format yaml --cert $$tmp_cert \
	> clusters/platform/wave-2-infra/cloudnativepg/templates/db-credentials-sealedsecret.yaml; \
	$(KUBECTL) -n infisical create secret generic db-credentials \
		--from-literal=authelia-password="$$AUTHELIA_PW" \
		--from-literal=forgejo-password="$$FORGEJO_PW" \
		--from-literal=infisical-password="$$INFISICAL_PW" \
		--from-literal=coder-password="$$CODER_PW" \
		--dry-run=client -o yaml \
	| kubeseal --format yaml --cert $$tmp_cert \
	> clusters/platform/wave-3-secrets/infisical/templates/db-credentials-sealedsecret.yaml; \
	rm -f $$tmp_key $$tmp_cert

# Gera SealedSecret com a connection URL do PostgreSQL para o Coder.
# Items: op://homelab/Coder Database/password
bootstrap-seal-coder-db-url:
	@tmp_key=$$(mktemp); tmp_cert=$$(mktemp); \
	op read "op://homelab/K8s Platforms Sealed Secret Key/private key" > $$tmp_key; \
	if grep -q "BEGIN OPENSSH PRIVATE KEY" $$tmp_key; then \
		ssh-keygen -p -m PEM -f $$tmp_key -P "" -N "" >/dev/null; \
	fi; \
	openssl req -new -x509 -key $$tmp_key -out $$tmp_cert -subj "/CN=sealed-secrets"; \
	CODER_PW=$$(op read "op://homelab/Coder Database/password"); \
	$(KUBECTL) -n coder create secret generic coder-db-url \
		--from-literal=url="postgres://coder:$${CODER_PW}@platform-postgres-rw.cloudnativepg.svc.cluster.local:5432/coder?sslmode=disable" \
		--dry-run=client -o yaml \
	| kubeseal --format yaml --cert $$tmp_cert \
	> clusters/platform/wave-5-platform/coder/templates/coder-db-url-sealedsecret.yaml; \
	rm -f $$tmp_key $$tmp_cert

# Gera SealedSecret com credenciais MinIO para backup barman do CloudNativePG.
# Items: op://homelab/MinIO/username, op://homelab/MinIO/password
bootstrap-seal-cnpg-minio-backup:
	@tmp_key=$$(mktemp); tmp_cert=$$(mktemp); \
	op read "op://homelab/K8s Platforms Sealed Secret Key/private key" > $$tmp_key; \
	if grep -q "BEGIN OPENSSH PRIVATE KEY" $$tmp_key; then \
		ssh-keygen -p -m PEM -f $$tmp_key -P "" -N "" >/dev/null; \
	fi; \
	openssl req -new -x509 -key $$tmp_key -out $$tmp_cert -subj "/CN=sealed-secrets"; \
	ACCESS_KEY=$$(op read "op://homelab/MinIO/username"); \
	SECRET_KEY=$$(op read "op://homelab/MinIO/password"); \
	$(KUBECTL) -n cloudnativepg create secret generic minio-backup-credentials \
		--from-literal=ACCESS_KEY_ID="$$ACCESS_KEY" \
		--from-literal=ACCESS_SECRET_KEY="$$SECRET_KEY" \
		--dry-run=client -o yaml \
	| kubeseal --format yaml --cert $$tmp_cert \
	> clusters/platform/wave-2-infra/cloudnativepg/templates/minio-backup-credentials-sealedsecret.yaml; \
	rm -f $$tmp_key $$tmp_cert

# Aplica apenas a Application bootstrap (root.yaml).
bootstrap-app:
	$(KUBECTL) apply -f bootstrap/root.yaml
