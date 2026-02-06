# Bootstrap: repo secret + sealed-secrets key + root Application
# Requires: KUBECTL, OP, OPENSSL, SSH-KEYGEN

.PHONY: bootstrap bootstrap-secrets bootstrap-sealed-secrets-key bootstrap-seal-onepassword-local bootstrap-app

# Aplica o Secret do repositório, a chave do Sealed Secrets e o bootstrap/root.yaml.
bootstrap: bootstrap-secrets bootstrap-sealed-secrets-key bootstrap-app

# Aplica apenas o Secret do repo via 1Password inject (op inject).
# Ajuste o path op:// no arquivo bootstrap/repo-secret.yaml.injectable para o seu item no 1Password.
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

# Gera o SealedSecret usando cert local (X.509).
bootstrap-seal-onepassword-local:
	@tmp_key=$$(mktemp); tmp_cert=$$(mktemp); \
	op read "op://homelab/K8s Platforms Sealed Secret Key/private key" > $$tmp_key; \
	if grep -q "BEGIN OPENSSH PRIVATE KEY" $$tmp_key; then \
		ssh-keygen -p -m PEM -f $$tmp_key -P "" -N "" >/dev/null; \
	fi; \
	openssl req -new -x509 -key $$tmp_key -out $$tmp_cert -subj "/CN=sealed-secrets"; \
	token=$$(op read "op://Private/op-service-account-homelab-sa/credential"); \
	$(KUBECTL) -n external-secrets create secret generic onepassword-credentials \
		--from-literal=token="$$token" \
		--dry-run=client -o yaml \
	| kubeseal --format yaml --cert $$tmp_cert \
	> clusters/platforms/external-secrets/templates/onepassword-credentials-sealedsecret.yaml; \
	rm -f $$tmp_key $$tmp_cert

# Aplica apenas a Application bootstrap (root.yaml).
bootstrap-app:
	$(KUBECTL) apply -f bootstrap/root.yaml
