# zot.mk: Extract images from Helm charts and pre-populate Zot registry via skopeo
# Requires: helm, skopeo, cosign, grep, sort, op (1Password CLI)
#
# 1Password items:
#   op://homelab/Zot Admin/username + password   - Zot registry admin credentials
#   op://homelab/Docker Hub/username + token      - Docker Hub credentials (avoids rate limits)
#
# Usage:
#   make zot-populate                     # extract + copy all images (skopeo)
#   make zot-cosign                       # copy cosign signatures for all images
#   make zot-sync                         # populate + cosign in one shot
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
	docker.gitea.com=gitea \
	ecr-public.aws.com=ecr

.PHONY: zot-list zot-populate zot-cosign zot-sync

# ---------------------------------------------------------------------------
# zot-sync: full pipeline — populate images + copy cosign signatures
# ---------------------------------------------------------------------------
zot-sync: zot-populate zot-cosign

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
	sed -i '/^$$/d' $(ZOT_IMAGES_FILE); \
	sed -i '/{{/d' $(ZOT_IMAGES_FILE); \
	sed -i 's/@sha256:[a-f0-9]*//' $(ZOT_IMAGES_FILE); \
	awk -F'/' '{ \
		first=$$1; rest=substr($$0,length(first)+2); \
		if (first ~ /[.:]/) { \
			if (first == "docker.io" && NF == 2) { print first "/library/" rest } \
			else { print } \
		} else { \
			if (NF == 1) { print "docker.io/library/" $$0 } \
			else { print "docker.io/" $$0 } \
		} \
	}' $(ZOT_IMAGES_FILE) > $(ZOT_IMAGES_FILE).tmp; \
	mv $(ZOT_IMAGES_FILE).tmp $(ZOT_IMAGES_FILE); \
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

# ---------------------------------------------------------------------------
# zot-cosign: copy cosign signatures & attestations from upstream to Zot
#
# cosign copy transfers:
#   - cosign signatures  (sha256-<digest>.sig tags)
#   - SBOM attestations  (sha256-<digest>.att tags)
#   - in-toto attestations
#
# Images without cosign signatures are silently skipped (exit 0).
# ---------------------------------------------------------------------------
zot-cosign: $(ZOT_IMAGES_FILE)
	@set -euo pipefail; \
	echo "==> Reading credentials from 1Password..."; \
	ZOT_USER="$$(op read '$(ZOT_OP_USER)')"; \
	ZOT_PASS="$$(op read '$(ZOT_OP_PASSWORD)')"; \
	DOCKER_USER="$$(op read '$(DOCKER_OP_USER)' 2>/dev/null || echo '')"; \
	DOCKER_TOKEN="$$(op read '$(DOCKER_OP_TOKEN)' 2>/dev/null || echo '')"; \
	echo "==> Logging into Zot ($(ZOT_DEST))..."; \
	COSIGN_YES=1 cosign login $(ZOT_DEST) -u "$$ZOT_USER" -p "$$ZOT_PASS"; \
	if [ -n "$$DOCKER_USER" ] && [ -n "$$DOCKER_TOKEN" ]; then \
		echo "==> Logging into Docker Hub..."; \
		cosign login docker.io -u "$$DOCKER_USER" -p "$$DOCKER_TOKEN" 2>/dev/null || true; \
	fi; \
	total=$$(wc -l < $(ZOT_IMAGES_FILE)); \
	echo "==> Copying cosign signatures for $$total images..."; echo ""; \
	export COSIGN_INSECURE_REGISTRY=true; \
	copied=0; skipped=0; failed=0; n=0; \
	while IFS= read -r raw_img; do \
		n=$$((n + 1)); \
		img="$$raw_img"; \
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
		dest="$(ZOT_DEST)/$$prefix/$$path"; \
		echo "[$$n/$$total] cosign: $$img"; \
		output=$$(cosign copy \
			--allow-insecure-registry \
			--force \
			"$$img" "$$dest" 2>&1) && { \
			copied=$$((copied + 1)); \
			echo "    OK: signatures copied"; \
		} || { \
			if echo "$$output" | grep -qiE "no signatures|no matching signatures|no referrers|MANIFEST_UNKNOWN|MANIFEST_INVALID|no attestations|could not find"; then \
				skipped=$$((skipped + 1)); \
				if echo "$$output" | grep -qi "MANIFEST_INVALID"; then \
					echo "    SKIP: multi-arch manifest mismatch (only amd64 mirrored)"; \
				else \
					echo "    SKIP: no cosign signatures found upstream"; \
				fi; \
			else \
				failed=$$((failed + 1)); \
				echo "    FAILED: $$output" >&2; \
			fi; \
		}; \
		echo ""; \
	done < $(ZOT_IMAGES_FILE); \
	echo "================================"; \
	echo "Cosign done! Copied: $$copied  Skipped (unsigned): $$skipped  Failed: $$failed"; \
	echo "================================"
