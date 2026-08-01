# pi
#
# `make bun` and `make deno` compile pi into standalone executables (`pi-bun`,
# `pi-deno`) for the current platform. Themes, HTML export templates, docs,
# examples, README, CHANGELOG, and package.json are inlined
# into the executable by scripts/generate-embedded-assets.mjs and extracted to
# a cache directory at startup (see packages/coding-agent/src/standalone-assets.ts).
# The output is a single self-contained executable with no sidecar files.
#
# Usage:
#   make bun                         # compile pi-bun with Bun
#   make deno                        # compile pi-deno with Deno
#   make bun-test                    # smoke-test the pi-bun binary (run 'make bun' first)
#   make bun-linux-arm64             # cross-compile pi-bun for linux-arm64 in a container
#   make deno-test                   # smoke-test the pi-deno binary (run 'make deno' first)
#   make bun SKIP_INSTALL=1          # reuse an existing node_modules
#   make bun OFFLINE_MODEL_DATA=1    # bundle checked-in model data instead of refreshing it

BUN ?= bun
DENO ?= deno
ESBUILD := node_modules/.bin/esbuild
BUN_VERSION ?= 1.3.14
BUN_LINUX_ARM64_IMAGE := pi-bun-linux-arm64
BUN_LINUX_ARM64_VOLUME := pi-bun-linux-arm64
BUN_LINUX_ARM64_MUSL_IMAGE := pi-bun-linux-arm64-musl
BUN_LINUX_ARM64_MUSL_VOLUME := pi-bun-linux-arm64-musl

OS_NAME := $(shell uname -s | tr '[:upper:]' '[:lower:]')
OS_ARCH := $(shell uname -m)
PLATFORM := $(OS_NAME)-$(OS_ARCH)
BUN_TARGET := bun-$(PLATFORM)

OUT_DIR ?= packages/coding-agent/binaries
BIN_DIR := $(OUT_DIR)/$(PLATFORM)

DENO_BUNDLE := $(BIN_DIR)/.pi-deno-bundle.js
DENO_BANNER := 'import { createRequire as __piDenoCreateRequire } from "node:module"; const require = __piDenoCreateRequire(import.meta.url);'

.PHONY: bun bun-linux-arm64 bun-linux-arm64-musl deno bun-test deno-test clean deps build

bun: deps build
	cd packages/coding-agent && $(BUN) build --compile --target=$(BUN_TARGET) \
		./dist/bun/cli.js \
		--outfile "$(abspath $(BIN_DIR)/pi-bun)"
	@echo "==> Built $(BIN_DIR)/pi-bun"

# Cross-compile pi-bun for linux-arm64 in a container. Dockerfile.bun installs
# dependencies, builds the workspace, and compiles with --target=bun-linux-arm64;
# the source is copied into the image via the build context. The binary is
# staged into a named volume (no bind mounts) and extracted to the host.
bun-linux-arm64:
	docker build -t $(BUN_LINUX_ARM64_IMAGE) -f Dockerfile.bun .
	@mkdir -p "$(OUT_DIR)/linux-arm64"
	@cid=$$(docker create -v $(BUN_LINUX_ARM64_VOLUME):/artifacts $(BUN_LINUX_ARM64_IMAGE)); \
	docker start -a $$cid; \
	docker cp $$cid:/artifacts/pi-bun "$(OUT_DIR)/linux-arm64/pi-bun"; \
	docker rm $$cid
	@chmod +x "$(OUT_DIR)/linux-arm64/pi-bun"
	@echo "==> Built $(OUT_DIR)/linux-arm64/pi-bun"

# Cross-compile the musl-linked variant for Alpine-based environments (e.g.
# the xsh gym): glibc binaries abort in Alpine containers, so the gym mounts
# this variant as /usr/local/bin/pi.
bun-linux-arm64-musl:
	docker build -t $(BUN_LINUX_ARM64_MUSL_IMAGE) \
		--build-arg BUN_FLAVOR=musl \
		--build-arg OUTPUT_DIR=packages/coding-agent/binaries/linux-arm64-musl \
		-f Dockerfile.bun .
	@mkdir -p "$(OUT_DIR)/linux-arm64-musl"
	@cid=$$(docker create -v $(BUN_LINUX_ARM64_MUSL_VOLUME):/artifacts $(BUN_LINUX_ARM64_MUSL_IMAGE)); \
	docker start -a $$cid; \
	docker cp $$cid:/artifacts/pi-bun "$(OUT_DIR)/linux-arm64-musl/pi-bun"; \
	docker rm $$cid
	@chmod +x "$(OUT_DIR)/linux-arm64-musl/pi-bun"
	@echo "==> Built $(OUT_DIR)/linux-arm64-musl/pi-bun"

# Smoke tests verify a built binary (run the matching build target first so the
# binary under test is fresh). They do not rebuild: the full build is heavy and
# touches the network, while the test itself is fast and offline.
bun-test:
	@./scripts/smoke-test-binary.sh "$(abspath $(BIN_DIR)/pi-bun)" bun

deno-test:
	@./scripts/smoke-test-binary.sh "$(abspath $(BIN_DIR)/pi-deno)" deno

deno: deps build
	$(ESBUILD) packages/coding-agent/dist/deno/cli.js --bundle --platform=node \
		--format=esm --main-fields=module,main \
		--banner:js=$(DENO_BANNER) \
		--outfile="$(abspath $(DENO_BUNDLE))"
	@# Compile outside the repo: a package.json in the bundle's ancestry makes
	@# Deno embed the whole node_modules tree. Use a temp dir with no package.json.
	@tmp=$$(mktemp -d); \
	cp "$(abspath $(DENO_BUNDLE))" "$$tmp/pi-deno-bundle.js"; \
	cd "$$tmp" && $(DENO) compile --no-check --allow-all \
		--output "$(abspath $(BIN_DIR)/pi-deno)" "$$tmp/pi-deno-bundle.js"; \
	status=$$?; rm -rf "$$tmp"; exit $$status
	rm -f "$(DENO_BUNDLE)"
	@echo "==> Built $(BIN_DIR)/pi-deno"

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
