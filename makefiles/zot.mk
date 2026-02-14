# zot.mk: Extract images from Helm charts and pre-populate Zot registry via skopeo
# Requires: helm, skopeo, grep, sort, op (1Password CLI)
#
# 1Password items:
#   op://homelab/Zot Admin/username + password   - Zot registry admin credentials
#   op://homelab/Docker Hub/username + token      - Docker Hub credentials (avoids rate limits)
#
# Usage:
#   make zot-populate                     # extract + copy all images
#   make zot-list                         # dry-run: just list discovered images
#   make zot-populate CHARTS_DIR=clusters/staging

HELM ?= helm
ZOT_DEST ?= 10.40.1.30:5000
CHARTS_DIR ?= clusters/platform
ZOT_IMAGES_FILE ?= $(BUILD_DIR)/zot-images.txt

# 1Password paths — adjust to match your vault/item names
ZOT_OP_USER     ?= op://homelab/Zot Admin/username
ZOT_OP_PASSWORD ?= op://homelab/Zot Admin/password
DOCKER_OP_USER  ?= op://development/Docker Hub/username
DOCKER_OP_TOKEN ?= op://development/Docker Hub/token

# Registry → Zot prefix mapping (must match Talos mirror config in locals.tf)
# Format used by the shell loop below: "source=dest"
REGISTRY_MAP := \
	docker.io=docker \
	registry-1.docker.io=docker \
	registry.k8s.io=k8s \
	k8s.gcr.io=k8s \
	ghcr.io=ghcr \
	quay.io=quay \
	docker.gitea.com=gitea

.PHONY: zot-list zot-populate

# ---------------------------------------------------------------------------
# zot-list: render charts, extract images, print the list
# ---------------------------------------------------------------------------
zot-list: $(ZOT_IMAGES_FILE)
	@echo ""; echo "==> Unique images found:"; cat $(ZOT_IMAGES_FILE); \
	echo ""; echo "Total: $$(wc -l < $(ZOT_IMAGES_FILE))"

$(ZOT_IMAGES_FILE):
	@set -euo pipefail; \
	mkdir -p "$(BUILD_DIR)"; \
	> $(ZOT_IMAGES_FILE); \
	for dir in $(CHARTS_DIR)/*/; do \
		[ -f "$$dir/Chart.yaml" ] || continue; \
		name=$$(basename "$$dir"); \
		echo "==> Extracting images from $$name"; \
		$(HELM) dependency build "$$dir" >/dev/null 2>&1 || true; \
		rendered=$$($(HELM) template "$$name" "$$dir" -f "$$dir/values.yaml" --include-crds 2>/dev/null \
			|| $(HELM) template "$$name" "$$dir" -f "$$dir/values.yaml" 2>/dev/null \
			|| echo ""); \
		if [ -z "$$rendered" ]; then \
			echo "    WARN: helm template failed for $$name, skipping"; \
			continue; \
		fi; \
		echo "$$rendered" \
			| grep -oP '\bimage:\s*["'"'"']?\K[a-zA-Z0-9_./:@-]+' \
			| sort -u \
			>> $(ZOT_IMAGES_FILE); \
	done; \
	sort -u -o $(ZOT_IMAGES_FILE) $(ZOT_IMAGES_FILE); \
	sed -i '/^$$/d; /{{/d' $(ZOT_IMAGES_FILE); \
	sed -i 's/@sha256:[a-f0-9]\{64\}$$//' $(ZOT_IMAGES_FILE); \
	sort -u -o $(ZOT_IMAGES_FILE) $(ZOT_IMAGES_FILE)

# ---------------------------------------------------------------------------
# zot-populate: extract images then copy each to Zot via skopeo
# ---------------------------------------------------------------------------
zot-populate: $(ZOT_IMAGES_FILE)
	@set -euo pipefail; \
	echo "==> Reading credentials from 1Password..."; \
	ZOT_CREDS="$$(op read '$(ZOT_OP_USER)'):$$(op read '$(ZOT_OP_PASSWORD)')"; \
	DOCKER_CREDS="$$(op read '$(DOCKER_OP_USER)'):$$(op read '$(DOCKER_OP_TOKEN)')" 2>/dev/null || DOCKER_CREDS=""; \
	total=$$(wc -l < $(ZOT_IMAGES_FILE)); \
	echo "==> Populating Zot with $$total images..."; echo ""; \
	success=0; failed=0; n=0; \
	while IFS= read -r raw_img; do \
		n=$$((n + 1)); \
		img="$$raw_img"; \
		segments=$$(echo "$$img" | tr '/' '\n' | wc -l); \
		first=$$(echo "$$img" | cut -d'/' -f1); \
		case "$$first" in \
			*.*|*:*) ;; \
			*) \
				if [ "$$segments" -le 1 ]; then \
					img="docker.io/library/$$img"; \
				else \
					img="docker.io/$$img"; \
				fi ;; \
		esac; \
		registry=$$(echo "$$img" | cut -d'/' -f1); \
		path=$$(echo "$$img" | cut -d'/' -f2-); \
		prefix=""; \
		for entry in $(REGISTRY_MAP); do \
			key=$${entry%%=*}; val=$${entry##*=}; \
			if [ "$$registry" = "$$key" ]; then prefix="$$val"; break; fi; \
		done; \
		if [ -z "$$prefix" ]; then \
			prefix=$$(echo "$$registry" | tr '.' '_'); \
		fi; \
		case "$$path" in \
			*:*@sha256:*) path=$${path%%@sha256:*} ;; \
		esac; \
		dest="docker://$(ZOT_DEST)/$$prefix/$$path"; \
		src="docker://$$img"; \
		case "$$img" in \
			*:*@sha256:*) src="docker://$${img%%@sha256:*}" ;; \
		esac; \
		echo "[$$n/$$total] $$img -> $$prefix/$$path"; \
		skopeo_args="copy $$src $$dest --dest-creds $$ZOT_CREDS --dest-tls-verify=false --multi-arch all"; \
		if [ -n "$$DOCKER_CREDS" ]; then \
			case "$$registry" in \
				docker.io|registry-1.docker.io) skopeo_args="$$skopeo_args --src-creds $$DOCKER_CREDS" ;; \
			esac; \
		fi; \
		if skopeo $$skopeo_args 2>&1; then \
			success=$$((success + 1)); \
		else \
			echo "    FAILED: $$img" >&2; \
			failed=$$((failed + 1)); \
		fi; \
		echo ""; \
	done < $(ZOT_IMAGES_FILE); \
	echo "================================"; \
	echo "Done! Total: $$total  Success: $$success  Failed: $$failed"; \
	echo "================================"; \
	if [ "$$failed" -gt 0 ]; then exit 1; fi
