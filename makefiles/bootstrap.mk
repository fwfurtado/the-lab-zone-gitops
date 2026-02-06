# Bootstrap: repo secret (op inject or env) + root Application
# Requires: KUBECTL

.PHONY: bootstrap bootstrap-secrets bootstrap-app

# Aplica o Secret do repositório (via op inject) e em seguida o bootstrap/root.yaml.
bootstrap: bootstrap-secrets bootstrap-app

# Aplica apenas o Secret do repo via 1Password inject (op inject).
# Ajuste o path op:// no arquivo bootstrap/repo-secret.yaml.injectable para o seu item no 1Password.
bootstrap-secrets:
	@op inject -i bootstrap/repo-secret.tpl.yaml | $(KUBECTL) apply -f -
#	@op inject -i bootstrap/onepassword-secret.tpl.yaml | $(KUBECTL) apply -f -

# Aplica apenas a Application bootstrap (root.yaml).
bootstrap-app:
	$(KUBECTL) apply -f bootstrap/root.yaml
