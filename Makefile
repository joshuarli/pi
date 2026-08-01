# pi
#
# `make bun` and `make deno` compile pi into standalone executables (`pi-bun`,
# `pi-deno`) for the current platform. Themes, HTML export templates, docs,
# examples, README, CHANGELOG, package.json, and the photon WASM are inlined
# into the executable by scripts/generate-embedded-assets.mjs and extracted to
# a cache directory at startup (see packages/coding-agent/src/standalone-assets.ts).
# The output is a single self-contained executable with no sidecar files.
#
# Usage:
#   make bun                         # compile pi-bun with Bun
#   make deno                        # compile pi-deno with Deno
#   make bun-test                    # smoke-test the pi-bun binary (run 'make bun' first)
#   make deno-test                   # smoke-test the pi-deno binary (run 'make deno' first)
#   make bun SKIP_INSTALL=1          # reuse an existing node_modules
#   make bun OFFLINE_MODEL_DATA=1    # bundle checked-in model data instead of refreshing it

BUN ?= bun
DENO ?= deno
ESBUILD := node_modules/.bin/esbuild

OS_NAME := $(shell uname -s | tr '[:upper:]' '[:lower:]')
OS_ARCH := $(shell uname -m)
PLATFORM := $(OS_NAME)-$(OS_ARCH)
BUN_TARGET := bun-$(PLATFORM)

OUT_DIR ?= packages/coding-agent/binaries
BIN_DIR := $(OUT_DIR)/$(PLATFORM)

DENO_BUNDLE := $(BIN_DIR)/.pi-deno-bundle.js
DENO_BANNER := 'import { createRequire as __piDenoCreateRequire } from "node:module"; const require = __piDenoCreateRequire(import.meta.url);'

.PHONY: bun deno bun-test deno-test clean deps build

bun: deps build
	cd packages/coding-agent && $(BUN) build --compile --target=$(BUN_TARGET) \
		./dist/bun/cli.js ./src/utils/image-resize-worker.ts \
		--outfile "$(abspath $(BIN_DIR)/pi-bun)"
	@echo "==> Built $(BIN_DIR)/pi-bun"

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
