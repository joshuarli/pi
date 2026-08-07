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
#   make deno-linux-arm64-musl       # build pi-deno with supplied static Deno/denort
#   make deno-test                   # smoke-test the staged pi-deno artifact
#   make clean                       # clean workspace dist trees and staged binaries
#   make bun SKIP_INSTALL=1          # reuse an existing node_modules
#   make bun OFFLINE_MODEL_DATA=1    # bundle checked-in model data instead of refreshing it

BUN ?= $(shell if command -v bun >/dev/null 2>&1; then command -v bun; elif test -x "$$HOME/.local/bin/bun"; then printf '%s' "$$HOME/.local/bin/bun"; fi)
NPM ?= $(shell command -v npm 2>/dev/null || true)
PACKAGE_MANAGER_GOALS := $(filter bun bun-test bun-real-test deno deno-linux-arm64-musl deno-test fake-provider-test deps build workspace-build workspace-clean clean,$(MAKECMDGOALS))
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

DENO ?= deno
DOCKER_BUILD ?= docker buildx build
DOCKER_BUILD_CACHE_ARGS ?=
ESBUILD := node_modules/.bin/esbuild
BUN_VERSION ?= 1.4.0
BUN_RUNTIME_SHA ?= unknown
PI_SHA ?= $(shell git rev-parse --short HEAD)
BUN_MUSL_ARTIFACT := pi-$(PI_SHA)-bun-$(BUN_VERSION)-linux-arm64-musl
DENO_VERSION ?= $(shell if test -n "$(DENO_BIN)" && test -x "$(DENO_BIN)"; then "$(DENO_BIN)" --version | awk 'NR == 1 { print $$2 }'; else echo unknown; fi)
DENO_RUNTIME_SHA ?= unknown
DENO_MUSL_ARTIFACT := pi-$(PI_SHA)-deno-$(DENO_VERSION)-linux-arm64-musl-static
BUN_LINUX_ARM64_MUSL_IMAGE := pi-bun-linux-arm64-musl
BUN_LINUX_ARM64_MUSL_VOLUME := pi-bun-linux-arm64-musl
BUN_MUSL_URL ?= https://github.com/joshuarli/bun-musl-static/releases/download/bun-5bf1172b-arm64-static-musl-llvm22/bun
BUN_MUSL_SHA256 ?= fe6051fae1ba872d042f84d958c3b8df48346361797b6c5fa1cf18013d1eaf7e
DENO_LINUX_ARM64_MUSL_IMAGE := pi-deno-linux-arm64-musl
DENO_LINUX_ARM64_MUSL_VOLUME := pi-deno-linux-arm64-musl

OS_NAME := $(shell uname -s | tr '[:upper:]' '[:lower:]')
OS_ARCH := $(shell uname -m)
PLATFORM := $(OS_NAME)-$(OS_ARCH)
BUN_TARGET := bun-$(PLATFORM)

OUT_DIR ?= packages/coding-agent/binaries
BIN_DIR := $(OUT_DIR)/$(PLATFORM)

.PHONY: bun bun-linux-arm64-musl bun-test bun-real-test deno deno-linux-arm64-musl deno-test fake-provider-test clean deps build workspace-build workspace-clean

bun: build
	@test -n "$(BUN)" || { echo "bun is required for bun build --compile; npm fallback only covers workspace install/build" >&2; exit 1; }
	cd packages/coding-agent && $(BUN) build --compile --bytecode --format=esm --minify --target=$(BUN_TARGET) \
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
	$(DOCKER_BUILD) $(DOCKER_BUILD_CACHE_ARGS) --load --platform linux/arm64 \
		-t $(BUN_LINUX_ARM64_MUSL_IMAGE) \
		--build-arg BUN_MUSL_URL=$(BUN_MUSL_URL) \
		--build-arg BUN_MUSL_SHA256=$(BUN_MUSL_SHA256) \
		--build-arg EXPECTED_LINKAGE=static \
		--build-arg PI_SOURCE_SHA=$(PI_SHA) \
		--build-arg PI_RUNTIME_SHA=$(BUN_RUNTIME_SHA) \
		-f Dockerfile.bun .
	@mkdir -p "$(OUT_DIR)"
	@cid=$$(docker create -v $(BUN_LINUX_ARM64_MUSL_VOLUME):/artifacts $(BUN_LINUX_ARM64_MUSL_IMAGE)); \
	docker start -a $$cid; \
	docker cp $$cid:/artifacts/pi-bun "$(OUT_DIR)/$(BUN_MUSL_ARTIFACT)"; \
	docker rm $$cid
	@chmod +x "$(OUT_DIR)/$(BUN_MUSL_ARTIFACT)"
	@echo "==> Built $(OUT_DIR)/$(BUN_MUSL_ARTIFACT)"
	# The ARM64 binary runs inside the built ARM64 image under QEMU. Keep build
	# validation local and deterministic; real-provider testing is opt-in via
	# bun-real-test.
	docker run --rm --platform linux/arm64 \
		$(BUN_LINUX_ARM64_MUSL_IMAGE) \
		sh -ec 'apk add --no-cache bash curl >/dev/null && \
			/app/scripts/smoke-test-binary.sh /app/pi-bun bun && \
			/app/scripts/smoke-test-fake-provider.sh /app/pi-bun'

# Run the full binary's local smoke tests.
bun-test: fake-provider-test
	@./scripts/smoke-test-binary.sh "$(abspath $(BIN_DIR)/pi-bun)" bun

# Run the fake-provider round-trip against the full `pi-bun` binary.
fake-provider-test:
	@./scripts/smoke-test-fake-provider.sh "$(abspath $(BIN_DIR)/pi-bun)"

# Real-provider smoke test for the full Bun binary. This intentionally requires
# an explicit API key because it contacts OpenRouter and may consume quota.
bun-real-test:
	@./scripts/smoke-test-real-provider.sh "$(abspath $(BIN_DIR)/pi-bun)"

# Build pi-deno using a supplied native static Deno compiler. The compiler is
# passed as a named BuildKit context so it never enters the source tree or the
# image as an unverified host bind mount.
deno: deno-linux-arm64-musl

deno-linux-arm64-musl:
	@test -x "$(DENO_BIN)" || { echo "DENO_BIN must point to the release deno executable" >&2; exit 1; }
	@test -x "$(DENO_RT_BIN)" || { echo "DENO_RT_BIN must point to the matching release denort executable" >&2; exit 1; }
	@tmp=$$(mktemp -d); \
	trap 'find "$$tmp" -type f -delete; find "$$tmp" -depth -type d -empty -delete' EXIT; \
	cp "$(DENO_BIN)" "$$tmp/deno"; \
	cp "$(DENO_RT_BIN)" "$$tmp/denort"; \
	$(DOCKER_BUILD) $(DOCKER_BUILD_CACHE_ARGS) --load --platform linux/arm64 \
		--build-context deno-bin="$$tmp" \
		--build-arg BUN_MUSL_URL=$(BUN_MUSL_URL) \
		--build-arg BUN_MUSL_SHA256=$(BUN_MUSL_SHA256) \
		--build-arg PI_RUNTIME_SHA=$(DENO_RUNTIME_SHA) \
		-t $(DENO_LINUX_ARM64_MUSL_IMAGE) \
		-f Dockerfile.deno .
	@mkdir -p "$(OUT_DIR)"
	@cid=$$(docker create -v $(DENO_LINUX_ARM64_MUSL_VOLUME):/artifacts $(DENO_LINUX_ARM64_MUSL_IMAGE)); \
	docker start -a $$cid; \
	docker cp $$cid:/artifacts/pi-deno "$(OUT_DIR)/$(DENO_MUSL_ARTIFACT)"; \
	docker rm $$cid
	@chmod +x "$(OUT_DIR)/$(DENO_MUSL_ARTIFACT)"
	@echo "==> Built $(OUT_DIR)/$(DENO_MUSL_ARTIFACT)"
	# The ARM64 binary runs inside the built ARM64 image under QEMU.
	docker run --rm --platform linux/arm64 \
		$(DENO_LINUX_ARM64_MUSL_IMAGE) \
		sh -ec 'apk add --no-cache bash curl >/dev/null && \
			/app/scripts/smoke-test-binary.sh /app/pi-deno deno && \
			/app/scripts/smoke-test-fake-provider.sh /app/pi-deno'

deno-test:
	@./scripts/smoke-test-binary.sh "$(abspath $(OUT_DIR)/$(DENO_MUSL_ARTIFACT))" deno

deps:
	@if [ "$(SKIP_INSTALL)" != "1" ]; then \
			echo "==> Installing dependencies..."; \
		"$(NPM)" install --ignore-scripts; \
	else \
		echo "==> Skipping dependency install (SKIP_INSTALL=1)"; \
	fi

workspace-build: deps
	@shim_dir="$$(mktemp -d)"; \
	trap 'if test -L "$$shim_dir/bun"; then unlink "$$shim_dir/bun"; fi; if test -L "$$shim_dir/npm"; then unlink "$$shim_dir/npm"; fi; rmdir "$$shim_dir"' EXIT; \
	if test -n "$(BUN)"; then ln -s "$(BUN)" "$$shim_dir/bun"; ln -s "$(BUN)" "$$shim_dir/npm"; fi; \
	PATH="$$shim_dir:$$PATH"; export PATH; \
	if [ "$(OFFLINE_MODEL_DATA)" = "1" ]; then \
		"$(PACKAGE_MANAGER)" run build:offline; \
	else \
		"$(PACKAGE_MANAGER)" run build; \
	fi

build: workspace-build

workspace-clean:
	@if test -n "$(NPM)"; then \
		"$(NPM)" run clean --workspaces --if-present; \
	else \
		echo "npm is required for workspace-clean" >&2; exit 1; \
	fi

clean: workspace-clean
	@rm -rf "$(OUT_DIR)"
