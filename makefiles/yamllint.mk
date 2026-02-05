# yamllint: run YAML linter locally
# Requires: pip install yamllint (or uv add --dev yamllint)

YAMLLINT ?= yamllint
YAMLLINT_FLAGS ?= --strict
YAMLLINT_TARGETS ?= applicationsets bootstrap clusters .github

.PHONY: yamllint

yamllint:
	$(YAMLLINT) $(YAMLLINT_FLAGS) $(YAMLLINT_TARGETS)
