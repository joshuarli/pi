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
#   make bun-linux-arm64-musl        # build pi-bun (full) for linux-arm64 musl natively in a container
#   make bun-headless-linux-arm64-musl  # build pi-headless for linux-arm64 musl natively in a container
#   make bun SKIP_INSTALL=1          # reuse an existing node_modules
#   make bun OFFLINE_MODEL_DATA=1    # bundle checked-in model data instead of refreshing it

BUN ?= bun
# DENO is out of scope (see "deno" target below).
# DENO ?= deno
ESBUILD := node_modules/.bin/esbuild
BUN_VERSION ?= 1.3.14
PI_SHA ?= $(shell git rev-parse --short HEAD)
BUN_MUSL_ARTIFACT := pi-$(PI_SHA)-bun-$(BUN_VERSION)-linux-arm64-musl
BUN_HEADLESS_MUSL_ARTIFACT := pi-$(PI_SHA)-bun-headless-$(BUN_VERSION)-linux-arm64-musl
BUN_LINUX_ARM64_MUSL_IMAGE := pi-bun-linux-arm64-musl
BUN_LINUX_ARM64_MUSL_VOLUME := pi-bun-linux-arm64-musl

OS_NAME := $(shell uname -s | tr '[:upper:]' '[:lower:]')
OS_ARCH := $(shell uname -m)
PLATFORM := $(OS_NAME)-$(OS_ARCH)
BUN_TARGET := bun-$(PLATFORM)

OUT_DIR ?= packages/coding-agent/binaries
BIN_DIR := $(OUT_DIR)/$(PLATFORM)

# Deno is out of scope for this fork; the target is disabled.
# DENO_BUNDLE := $(BIN_DIR)/.pi-deno-bundle.js
# DENO_BANNER := 'import { createRequire as __piDenoCreateRequire } from "node:module"; const require = __piDenoCreateRequire(import.meta.url);'

.PHONY: bun bun-linux-arm64-musl bun-headless-linux-arm64-musl bun-test headless-test fake-provider-test clean deps build headless

bun: deps build
	cd packages/coding-agent && $(BUN) build --compile --target=$(BUN_TARGET) \
		./dist/bun/cli.js \
		--outfile "$(abspath $(BIN_DIR)/pi-bun)"
	@echo "==> Built $(BIN_DIR)/pi-bun"

# Build pi-bun (full) for linux-arm64 musl natively inside a linux/arm64
# container. Dockerfile.bun installs dependencies, builds the workspace, compiles
# with the container's own platform (no --target), and verifies the output
# linkage with elfutils before staging. The source is copied into the image via
# the build context; the binary is staged into a named volume (no bind mounts)
# and extracted to the host.
#
# This musl variant is for Alpine-based environments (e.g. the xsh gym): glibc
# binaries abort in Alpine containers, so the gym mounts this variant as
# /usr/local/bin/pi. EXPECTED_LINKAGE=musl makes the elfutils check refuse to
# stage a glibc-linked output.
#
# TODO: produce a fully static binary. bun --compile emits musl-dynamic
# output (ld-musl plus libstdc++/libgcc_s) in every 1.3.x release we tried,
# so Alpine-based consumers still need libstdc++ and libgcc_s at runtime; a
# static build would remove those runtime deps.
bun-linux-arm64-musl:
	docker build --platform linux/arm64 \
		-t $(BUN_LINUX_ARM64_MUSL_IMAGE) \
		--build-arg BUN_FLAVOR=musl \
		--build-arg EXPECTED_LINKAGE=musl \
		--build-arg PI_SOURCE_SHA=$(PI_SHA) \
		-f Dockerfile.bun .
	@mkdir -p "$(OUT_DIR)"
	@cid=$$(docker create -v $(BUN_LINUX_ARM64_MUSL_VOLUME):/artifacts $(BUN_LINUX_ARM64_MUSL_IMAGE)); \
	docker start -a $$cid; \
	docker cp $$cid:/artifacts/pi-bun "$(OUT_DIR)/$(BUN_MUSL_ARTIFACT)"; \
	docker rm $$cid
	@chmod +x "$(OUT_DIR)/$(BUN_MUSL_ARTIFACT)"
	@echo "==> Built $(OUT_DIR)/$(BUN_MUSL_ARTIFACT)"

# Build pi-headless (TUI stubbed out) for linux-arm64 musl natively in the same
# container as `bun-linux-arm64-musl` (Dockerfile.bun stages both pi-bun and
# pi-headless into /artifacts); only the headless binary is extracted here.
bun-headless-linux-arm64-musl:
	docker build --platform linux/arm64 \
		-t $(BUN_LINUX_ARM64_MUSL_IMAGE) \
		--build-arg BUN_FLAVOR=musl \
		--build-arg EXPECTED_LINKAGE=musl \
		--build-arg PI_SOURCE_SHA=$(PI_SHA) \
		-f Dockerfile.bun .
	@mkdir -p "$(OUT_DIR)"
	@cid=$$(docker create -v $(BUN_LINUX_ARM64_MUSL_VOLUME):/artifacts $(BUN_LINUX_ARM64_MUSL_IMAGE)); \
	docker start -a $$cid; \
	docker cp $$cid:/artifacts/pi-headless "$(OUT_DIR)/$(BUN_HEADLESS_MUSL_ARTIFACT)"; \
	docker rm $$cid
	@chmod +x "$(OUT_DIR)/$(BUN_HEADLESS_MUSL_ARTIFACT)"
	@echo "==> Built $(OUT_DIR)/$(BUN_HEADLESS_MUSL_ARTIFACT)"

# Smoke tests verify a built binary (run the matching build target first so the
# binary under test is fresh). They do not rebuild: the full build is heavy and
# touches the network, while the test itself is fast and offline.

# Headless build: compiles pi without the TUI. `@earendil-works/pi-tui` is
# swapped for a no-op stub by `headless/stub-pi-tui.plugin.ts`, so the binary
# carries none of the interactive UI code (see scripts/build-headless.mts).
headless: deps build
	cd packages/coding-agent && bun scripts/build-headless.mts "$(abspath $(BIN_DIR)/pi-headless)"
	chmod +x "$(abspath $(BIN_DIR)/pi-headless)"
	@echo "==> Built $(BIN_DIR)/pi-headless"

headless-test:
	@./scripts/smoke-test-binary.sh "$(abspath $(BIN_DIR)/pi-headless)" headless
	@./scripts/smoke-test-fake-provider.sh "$(abspath $(BIN_DIR)/pi-headless)"

# Smoke the full binary against the fake provider too (generic test).
bun-test: fake-provider-test
	@./scripts/smoke-test-binary.sh "$(abspath $(BIN_DIR)/pi-bun)" bun

# Run the fake-provider round-trip against the full `pi-bun` binary.
fake-provider-test:
	@./scripts/smoke-test-fake-provider.sh "$(abspath $(BIN_DIR)/pi-bun)"

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
		if [ ! -d node_modules ]; then \
			echo "==> Installing dependencies..."; \
			npm ci --ignore-scripts; \
		fi; \
	else \
		echo "==> Skipping dependency install (SKIP_INSTALL=1)"; \
	fi

build:
	@if [ "$(OFFLINE_MODEL_DATA)" = "1" ]; then \
		npm run build:offline; \
	else \
		npm run build; \
	fi

clean:
	rm -rf $(OUT_DIR)
