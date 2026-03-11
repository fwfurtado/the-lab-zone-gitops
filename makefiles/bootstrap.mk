# Bootstrap: repo secret + sealed-secrets key + Infisical secrets + root Application
# Requires: KUBECTL, OP, OPENSSL, SSH-KEYGEN, KUBESEAL

.PHONY: bootstrap-secrets bootstrap-sealed-secrets-key bootstrap-app
.PHONY: bootstrap-seal-infisical-secrets bootstrap-seal-infisical-credentials

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

# Gera o SealedSecret com AUTH_SECRET, ROOT_ENCRYPTION_KEY e SITE_URL para o Infisical.
# KMS migration requires 32-byte key; use ROOT_ENCRYPTION_KEY (not ENCRYPTION_KEY).
# Items: op://homelab/Infisical/auth-secret, op://homelab/Infisical/root-encryption-key
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
	$(KUBECTL) -n infisical create secret generic infisical-secrets \
		--from-literal=AUTH_SECRET="$$AUTH_SECRET" \
		--from-literal=ROOT_ENCRYPTION_KEY="$$ROOT_ENCRYPTION_KEY" \
		--from-literal=SITE_URL="https://infisical.infra.the-lab.zone" \
		--dry-run=client -o yaml \
	| kubeseal --format yaml --cert $$tmp_cert \
	> clusters/platform/wave-2-infra/infisical/templates/infisical-secrets-sealedsecret.yaml; \
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

# Aplica apenas a Application bootstrap (root.yaml).
bootstrap-app:
	$(KUBECTL) apply -f bootstrap/root.yaml
