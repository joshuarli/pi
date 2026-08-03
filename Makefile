# pi
#
# `make bun` compiles pi into a standalone executable (`pi-bun`) for the
# current platform. Themes, HTML export templates, docs,
# examples, README, CHANGELOG, and package.json are inlined
# into the executable by scripts/generate-embedded-assets.mjs and extracted to
# a cache directory at startup (see packages/coding-agent/src/standalone-assets.ts).
# The output is a single self-contained executable with no sidecar files.
#
# Usage:
#   make bun                         # compile pi-bun with Bun
#   make bun-test                    # smoke-test the pi-bun binary (run 'make bun' first)
#   make bun-real-test               # real OpenRouter test (requires OPENROUTER_API_KEY)
#   make bun-linux-arm64-musl        # build pi-bun (full) for linux-arm64 musl natively in a container
#   make bun SKIP_INSTALL=1          # reuse an existing node_modules
#   make bun OFFLINE_MODEL_DATA=1    # bundle checked-in model data instead of refreshing it

BUN ?= $(shell if command -v bun >/dev/null 2>&1; then command -v bun; elif test -x "$$HOME/.local/bin/bun"; then printf '%s' "$$HOME/.local/bin/bun"; fi)
NPM ?= $(shell command -v npm 2>/dev/null || true)
PACKAGE_MANAGER_GOALS := $(filter bun bun-test bun-real-test fake-provider-test deps build,$(MAKECMDGOALS))
ifeq ($(strip $(MAKECMDGOALS)),)
PACKAGE_MANAGER_GOALS := default
endif

ifeq ($(strip $(BUN)),)
ifeq ($(strip $(NPM)),)
ifneq ($(strip $(PACKAGE_MANAGER_GOALS)),)
$(error Neither bun nor npm is available; install one before running make)
endif
PACKAGE_MANAGER :=
else
PACKAGE_MANAGER := $(NPM)
endif
else
PACKAGE_MANAGER := $(BUN)
endif

# DENO is out of scope (see "deno" target below).
# DENO ?= deno
ESBUILD := node_modules/.bin/esbuild
BUN_VERSION ?= 1.4.0
PI_SHA ?= $(shell git rev-parse --short HEAD)
BUN_MUSL_ARTIFACT := pi-$(PI_SHA)-bun-$(BUN_VERSION)-linux-arm64-musl
BUN_LINUX_ARM64_MUSL_IMAGE := pi-bun-linux-arm64-musl
BUN_LINUX_ARM64_MUSL_VOLUME := pi-bun-linux-arm64-musl
BUN_MUSL_URL ?= https://github.com/joshuarli/bun-musl-static/releases/download/bun-5bf1172b-arm64-static-musl-llvm22/bun

OS_NAME := $(shell uname -s | tr '[:upper:]' '[:lower:]')
OS_ARCH := $(shell uname -m)
PLATFORM := $(OS_NAME)-$(OS_ARCH)
BUN_TARGET := bun-$(PLATFORM)

OUT_DIR ?= packages/coding-agent/binaries
BIN_DIR := $(OUT_DIR)/$(PLATFORM)

# Deno is out of scope for this fork; the target is disabled.
# DENO_BUNDLE := $(BIN_DIR)/.pi-deno-bundle.js
# DENO_BANNER := 'import { createRequire as __piDenoCreateRequire } from "node:module"; const require = __piDenoCreateRequire(import.meta.url);'

.PHONY: bun bun-linux-arm64-musl bun-test bun-real-test fake-provider-test clean deps build

bun: deps build
	@test -n "$(BUN)" || { echo "bun is required for bun build --compile; npm fallback only covers workspace install/build" >&2; exit 1; }
	cd packages/coding-agent && $(BUN) build --compile --target=$(BUN_TARGET) \
		./dist/bun/cli.js \
		--outfile "$(abspath $(BIN_DIR)/pi-bun)"
	@echo "==> Built $(BIN_DIR)/pi-bun"
	@$(MAKE) bun-test

# Build pi-bun (full) for linux-arm64 musl natively inside a linux/arm64
# container. Dockerfile.bun uses the static Bun at BUN_MUSL_URL as its
# compiler, installs dependencies, builds the workspace, compiles with the
# container's own platform (no --target), and verifies the output linkage with
# elfutils before staging. The binary is staged into a named volume (no bind
# mounts) and extracted to the host.
#
# This musl variant is for Alpine-based environments (e.g. the xsh gym): glibc
# binaries abort in Alpine containers, so the gym mounts this variant as
# /usr/local/bin/pi. EXPECTED_LINKAGE=static makes the elfutils check reject
# anything other than the fully static output.
#
bun-linux-arm64-musl:
	docker build --platform linux/arm64 \
		-t $(BUN_LINUX_ARM64_MUSL_IMAGE) \
		--build-arg BUN_MUSL_URL=$(BUN_MUSL_URL) \
		--build-arg EXPECTED_LINKAGE=static \
		--build-arg PI_SOURCE_SHA=$(PI_SHA) \
		-f Dockerfile.bun .
	@mkdir -p "$(OUT_DIR)"
	@cid=$$(docker create -v $(BUN_LINUX_ARM64_MUSL_VOLUME):/artifacts $(BUN_LINUX_ARM64_MUSL_IMAGE)); \
	docker start -a $$cid; \
	docker cp $$cid:/artifacts/pi-bun "$(OUT_DIR)/$(BUN_MUSL_ARTIFACT)"; \
	docker rm $$cid
	@chmod +x "$(OUT_DIR)/$(BUN_MUSL_ARTIFACT)"
	@echo "==> Built $(OUT_DIR)/$(BUN_MUSL_ARTIFACT)"
	# The ARM64 binary runs inside the built ARM64 image under QEMU.
	@test -n "$${OPENROUTER_API_KEY:-}" || { echo "OPENROUTER_API_KEY must be set" >&2; exit 1; }
	docker run --rm --platform linux/arm64 -e OPENROUTER_API_KEY \
		$(BUN_LINUX_ARM64_MUSL_IMAGE) \
		sh -ec 'apk add --no-cache bash >/dev/null && \
			/app/scripts/smoke-test-binary.sh /app/pi-bun bun && \
			/app/scripts/smoke-test-fake-provider.sh /app/pi-bun && \
			/app/scripts/smoke-test-real-provider.sh /app/pi-bun'

# Headless build targets are intentionally disabled while the full pi-bun
# artifact is being stabilized. Keep the old recipes here for reference.
#
# bun-headless-linux-arm64-musl:
# 	docker build --platform linux/arm64 \
# 		-t $(BUN_LINUX_ARM64_MUSL_IMAGE) \
# 		--build-arg BUN_FLAVOR=musl \
# 		--build-arg EXPECTED_LINKAGE=musl \
# 		--build-arg PI_SOURCE_SHA=$(PI_SHA) \
# 		-f Dockerfile.bun .
# 	@mkdir -p "$(OUT_DIR)"
# 	@cid=$$(docker create -v $(BUN_LINUX_ARM64_MUSL_VOLUME):/artifacts $(BUN_LINUX_ARM64_MUSL_IMAGE)); \
# 	docker start -a $$cid; \
# 	docker cp $$cid:/artifacts/pi-headless "$(OUT_DIR)/pi-$(PI_SHA)-bun-headless-$(BUN_VERSION)-linux-arm64-musl"; \
# 	docker rm $$cid
# 	@chmod +x "$(OUT_DIR)/pi-$(PI_SHA)-bun-headless-$(BUN_VERSION)-linux-arm64-musl"
# 	@echo "==> Built $(OUT_DIR)/pi-$(PI_SHA)-bun-headless-$(BUN_VERSION)-linux-arm64-musl"
#
# headless: deps build
# 	cd packages/coding-agent && bun scripts/build-headless.mts "$(abspath $(BIN_DIR)/pi-headless)"
# 	chmod +x "$(abspath $(BIN_DIR)/pi-headless)"
# 	@echo "==> Built $(BIN_DIR)/pi-headless"
#
# headless-test:
# 	@./scripts/smoke-test-binary.sh "$(abspath $(BIN_DIR)/pi-headless)" headless
# 	@./scripts/smoke-test-fake-provider.sh "$(abspath $(BIN_DIR)/pi-headless)"
#
# headless-real-test:
# 	@test -n "$${OPENROUTER_API_KEY:-}" || { echo "OPENROUTER_API_KEY must be set" >&2; exit 1; }
# 	@PI_CODING_AGENT_DIR="$$(mktemp -d)"; \
# 	trap 'rm -rf "$$PI_CODING_AGENT_DIR"' EXIT; \
# 	export PI_CODING_AGENT_DIR OPENROUTER_API_KEY; \
# 	"$(abspath $(BIN_DIR)/pi-headless)" \
# 		--offline --no-tools --no-extensions --no-skills --no-themes \
# 		--no-session --no-context-files --approve --thinking low \
# 		--provider openrouter --model 'poolside/laguna-xs-2.1:free' \
# 		-p "just say hi"

# Run the full binary's local and real-provider smoke tests.
bun-test: fake-provider-test
	@./scripts/smoke-test-binary.sh "$(abspath $(BIN_DIR)/pi-bun)" bun
	@$(MAKE) bun-real-test

# Run the fake-provider round-trip against the full `pi-bun` binary.
fake-provider-test:
	@./scripts/smoke-test-fake-provider.sh "$(abspath $(BIN_DIR)/pi-bun)"

# Real-provider smoke test for the full Bun binary. This intentionally requires
# an explicit API key because it contacts OpenRouter and may consume quota.
bun-real-test:
	@./scripts/smoke-test-real-provider.sh "$(abspath $(BIN_DIR)/pi-bun)"

# Deno is out of scope for this fork; the target is disabled.
# deno-test:
# 	@./scripts/smoke-test-binary.sh "$(abspath $(BIN_DIR)/pi-deno)" deno
#
# deno: deps build
# 	$(ESBUILD) packages/coding-agent/dist/deno/cli.js --bundle --platform=node \
# 		--format=esm --main-fields=module,main \
# 		--banner:js=$(DENO_BANNER) \
# 		--outfile="$(abspath $(DENO_BUNDLE))"
# 	@# Compile outside the repo: a package.json in the bundle's ancestry makes
# 	@# Deno embed the whole node_modules tree. Use a temp dir with no package.json.
# 	@tmp=$$(mktemp -d); \
# 	cp "$(abspath $(DENO_BUNDLE))" "$$tmp/pi-deno-bundle.js"; \
# 	cd "$$tmp" && $(DENO) compile --no-check --allow-all \
# 		--output "$(abspath $(BIN_DIR)/pi-deno)" "$$tmp/pi-deno-bundle.js"; \
# 	status=$$?; rm -rf "$$tmp"; exit $$status
# 	rm -f "$(DENO_BUNDLE)"
# 	@echo "==> Built $(BIN_DIR)/pi-deno"

deps:
	@if [ "$(SKIP_INSTALL)" != "1" ]; then \
		if [ ! -d node_modules ] || ! node_modules/.bin/tsgo --version >/dev/null 2>&1; then \
			echo "==> Installing dependencies..."; \
			if test -n "$(BUN)"; then \
				if ! "$(BUN)" install --no-save --ignore-scripts; then \
					if test -n "$(NPM)"; then \
						echo "==> Bun install failed; falling back to npm ci" >&2; \
						"$(NPM)" ci --ignore-scripts; \
					else \
						echo "Bun install failed and npm is unavailable" >&2; \
						exit 1; \
					fi; \
				fi; \
			else \
				"$(NPM)" ci --ignore-scripts; \
			fi; \
		fi; \
	else \
		echo "==> Skipping dependency install (SKIP_INSTALL=1)"; \
	fi

build:
	@shim_dir="$$(mktemp -d)"; \
	trap 'if test -L "$$shim_dir/bun"; then unlink "$$shim_dir/bun"; fi; if test -L "$$shim_dir/npm"; then unlink "$$shim_dir/npm"; fi; rmdir "$$shim_dir"' EXIT; \
	if test -n "$(BUN)"; then ln -s "$(BUN)" "$$shim_dir/bun"; ln -s "$(BUN)" "$$shim_dir/npm"; fi; \
	PATH="$$shim_dir:$$PATH"; export PATH; \
	if [ "$(OFFLINE_MODEL_DATA)" = "1" ]; then \
		"$(PACKAGE_MANAGER)" run build:offline; \
	else \
		"$(PACKAGE_MANAGER)" run build; \
	fi

clean:
	rm -rf $(OUT_DIR)
