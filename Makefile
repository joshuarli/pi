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
#   make deno-linux-arm64-musl       # build pi-deno with static QuickJS Deno/denort
#   make deno-linux-x86_64-musl      # build pi-deno with static QuickJS Deno/denort
#   make deno-macos-aarch64          # build pi-deno with macOS QuickJS Deno/denort
#   make deno-test                   # smoke-test the staged pi-deno artifact
#   make clean                       # clean workspace dist trees and staged binaries
#   make bun SKIP_INSTALL=1          # reuse an existing node_modules
#   make bun OFFLINE_MODEL_DATA=1    # bundle checked-in model data instead of refreshing it

BUN ?= $(shell if command -v bun >/dev/null 2>&1; then command -v bun; elif test -x "$$HOME/.local/bin/bun"; then printf '%s' "$$HOME/.local/bin/bun"; fi)
NPM ?= $(shell command -v npm 2>/dev/null || true)
PACKAGE_MANAGER_GOALS := $(filter bun bun-test bun-real-test deno deno-linux-arm64-musl deno-linux-x86_64-musl deno-linux-amd64-musl deno-macos-aarch64 deno-macos-aarch64-test deno-test fake-provider-test deps build workspace-build workspace-clean clean,$(MAKECMDGOALS))
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

DOCKER_BUILD ?= docker buildx build
DOCKER_BUILD_CACHE_ARGS ?=
ESBUILD := node_modules/.bin/esbuild
BUN_VERSION ?= 1.4.0
BUN_RUNTIME_SHA ?= unknown
PI_SHA ?= $(shell git rev-parse --short HEAD)
BUN_MUSL_ARTIFACT := pi-$(PI_SHA)-bun-$(BUN_VERSION)-linux-arm64-musl
# All Deno targets use compiler/runtime pairs from one immutable release. The
# per-platform fetch targets are only used when the corresponding DENO_BIN and
# DENO_RT_BIN overrides do not already point at executables.
DENO_RELEASE_SHA ?= 671a92517269d0191d031c5476bdb03ae53d5c78
DENO_RELEASE_TAG ?= deno-$(DENO_RELEASE_SHA)-linux-musl-static
DENO_RELEASE_BASE_URL ?= https://github.com/joshuarli/deno-musl-static/releases/download/$(DENO_RELEASE_TAG)
DENO_CACHE_DIR ?= .artifacts/deno/$(DENO_RELEASE_SHA)
DENO_LINUX_ARM64_BIN ?= $(DENO_CACHE_DIR)/linux-arm64/deno
DENO_LINUX_ARM64_RT_BIN ?= $(DENO_CACHE_DIR)/linux-arm64/denort
DENO_LINUX_X86_64_BIN ?= $(DENO_CACHE_DIR)/linux-x86_64/deno
DENO_LINUX_X86_64_RT_BIN ?= $(DENO_CACHE_DIR)/linux-x86_64/denort
DENO_MACOS_BIN ?= $(DENO_CACHE_DIR)/macos-aarch64/deno
DENO_MACOS_RT_BIN ?= $(DENO_CACHE_DIR)/macos-aarch64/denort
DENO_BIN ?= $(DENO_LINUX_ARM64_BIN)
DENO_RT_BIN ?= $(DENO_LINUX_ARM64_RT_BIN)
DENO_VERSION ?= $(shell if test -x "$(DENO_BIN)"; then version=$$("$(DENO_BIN)" --version 2>/dev/null | awk 'NR == 1 { print ($$1 == "deno" ? $$2 : $$1); exit }'); test -n "$$version" && printf '%s\n' "$$version" || printf '%s\n' unknown; else printf '%s\n' unknown; fi)
DENO_RUNTIME_SHA ?= $(shell if test -x "$(DENO_BIN)"; then sha=$$("$(DENO_BIN)" --version 2>/dev/null | grep -Eo '\([0-9a-fA-F]{7,40}\)' | tr -d '()' | head -n 1); test -n "$$sha" && printf '%s\n' "$$sha" || printf '%s\n' unknown; else printf '%s\n' unknown; fi)
DENO_MUSL_ARTIFACT := pi-$(PI_SHA)-deno-$(DENO_VERSION)-linux-arm64-musl-static

DENO_MACOS_VERSION ?= $(shell if test -x "$(DENO_MACOS_BIN)"; then version=$$("$(DENO_MACOS_BIN)" --version 2>/dev/null | awk 'NR == 1 { print ($$1 == "deno" ? $$2 : $$1); exit }'); test -n "$$version" && printf '%s\n' "$$version" || printf '%s\n' unknown; else printf '%s\n' unknown; fi)
DENO_MACOS_RUNTIME_VERSION ?= $(shell if test -x "$(DENO_MACOS_BIN)"; then version=$$("$(DENO_MACOS_BIN)" --version 2>/dev/null | awk 'NR == 1 { print ($$1 == "deno" ? $$2 : $$1); exit }'); test -n "$$version" && printf '%s\n' "$$version" || printf '%s\n' unknown; else printf '%s\n' unknown; fi)
DENO_MACOS_RUNTIME_SHA ?= $(shell if test -x "$(DENO_MACOS_BIN)"; then sha=$$("$(DENO_MACOS_BIN)" --version 2>/dev/null | grep -Eo '\([0-9a-fA-F]{7,40}\)' | tr -d '()' | head -n 1); if test -n "$$sha"; then printf '%s\n' "$$sha"; else printf '%s\n' "$(DENO_RUNTIME_SHA)"; fi; else printf '%s\n' "$(DENO_RUNTIME_SHA)"; fi)
DENO_MACOS_ARTIFACT ?= pi-$(PI_SHA)-deno-$(DENO_MACOS_VERSION)-macos-arm64

BUN_LINUX_ARM64_MUSL_IMAGE := pi-bun-linux-arm64-musl
BUN_LINUX_ARM64_MUSL_VOLUME := pi-bun-linux-arm64-musl
BUN_MUSL_URL ?= https://github.com/joshuarli/bun-musl-static/releases/download/bun-5bf1172b-arm64-static-musl-llvm22/bun
BUN_MUSL_SHA256 ?= fe6051fae1ba872d042f84d958c3b8df48346361797b6c5fa1cf18013d1eaf7e
DENO_LINUX_IMAGE ?= pi-deno-linux-arm64-musl
DENO_LINUX_VOLUME ?= pi-deno-linux-arm64-musl
DENO_LINUX_PLATFORM ?= linux/arm64

DENO_LINUX_ARM64_COMPILER_SHA256 := 3c9a27c192dcf6a015a9ea68153583e13fd97db6c54df854641909444464298c
DENO_LINUX_ARM64_RUNTIME_SHA256 := a93e2e5c4af455db03c78513a5ec83b210d772398cb468f922b00382362a67ba
DENO_LINUX_X86_64_COMPILER_SHA256 := 9436c1d3f92ac97d600cb1c8eb1d20c2611a0896a75fdefc8f0f6e6a1556152d
DENO_LINUX_X86_64_RUNTIME_SHA256 := 80c20f06bdf4120ff2763d69f6e86a43a9424fec1d773a7800aea649e812d9ea
DENO_MACOS_COMPILER_SHA256 := 228cbbf86d7de0884660eada6b6e269db6656006d2c96e77ef6815b9e3cfc74c
DENO_MACOS_RUNTIME_SHA256 := 81134a1ef922719acf3908bef895202ccac5d39cd2e60a4ae8a427ca315abeb2

OS_NAME := $(shell uname -s | tr '[:upper:]' '[:lower:]')
OS_ARCH := $(shell uname -m)
PLATFORM := $(OS_NAME)-$(OS_ARCH)
BUN_TARGET := bun-$(PLATFORM)

OUT_DIR ?= packages/coding-agent/binaries
BIN_DIR := $(OUT_DIR)/$(PLATFORM)

.PHONY: bun bun-linux-arm64-musl bun-test bun-real-test deno deno-linux-arm64-musl deno-linux-musl deno-linux-x86_64-musl deno-linux-amd64-musl deno-macos-aarch64 deno-macos-aarch64-test deno-test deno-fetch-linux-arm64 deno-fetch-linux-x86_64 deno-fetch-macos-aarch64 fake-provider-test clean deps build workspace-build workspace-clean

pi-bun: build
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

pi-deno: deno-macos-aarch64

deno-linux-arm64-musl: DENO_BIN=$(DENO_LINUX_ARM64_BIN)
deno-linux-arm64-musl: DENO_RT_BIN=$(DENO_LINUX_ARM64_RT_BIN)
deno-linux-arm64-musl: DENO_LINUX_PLATFORM=linux/arm64
deno-linux-arm64-musl: DENO_LINUX_IMAGE=pi-deno-linux-arm64-musl
deno-linux-arm64-musl: DENO_LINUX_VOLUME=pi-deno-linux-arm64-musl
deno-linux-arm64-musl: deno-fetch-linux-arm64 deno-linux-musl

deno-linux-x86_64-musl: DENO_BIN=$(DENO_LINUX_X86_64_BIN)
deno-linux-x86_64-musl: DENO_RT_BIN=$(DENO_LINUX_X86_64_RT_BIN)
deno-linux-x86_64-musl: DENO_LINUX_PLATFORM=linux/amd64
deno-linux-x86_64-musl: DENO_LINUX_IMAGE=pi-deno-linux-x86_64-musl
deno-linux-x86_64-musl: DENO_LINUX_VOLUME=pi-deno-linux-x86_64-musl
deno-linux-x86_64-musl: DENO_MUSL_ARTIFACT=pi-$(PI_SHA)-deno-$(DENO_VERSION)-linux-x86_64-musl-static
deno-linux-x86_64-musl: deno-fetch-linux-x86_64 deno-linux-musl

deno-linux-amd64-musl: DENO_BIN=$(DENO_LINUX_X86_64_BIN)
deno-linux-amd64-musl: DENO_RT_BIN=$(DENO_LINUX_X86_64_RT_BIN)
deno-linux-amd64-musl: DENO_LINUX_PLATFORM=linux/amd64
deno-linux-amd64-musl: DENO_LINUX_IMAGE=pi-deno-linux-x86_64-musl
deno-linux-amd64-musl: DENO_LINUX_VOLUME=pi-deno-linux-x86_64-musl
deno-linux-amd64-musl: DENO_MUSL_ARTIFACT=pi-$(PI_SHA)-deno-$(DENO_VERSION)-linux-x86_64-musl-static
deno-linux-amd64-musl: deno-fetch-linux-x86_64 deno-linux-musl

deno-linux-musl:
	@test -x "$(DENO_BIN)" || { echo "DENO_BIN must point to the release deno executable" >&2; exit 1; }
	@test -x "$(DENO_RT_BIN)" || { echo "DENO_RT_BIN must point to the matching release denort executable" >&2; exit 1; }
	@tmp=$$(mktemp -d); \
	trap 'find "$$tmp" -type f -delete; find "$$tmp" -depth -type d -empty -delete' EXIT; \
	cp "$(DENO_BIN)" "$$tmp/deno"; \
	cp "$(DENO_RT_BIN)" "$$tmp/denort"; \
	$(DOCKER_BUILD) $(DOCKER_BUILD_CACHE_ARGS) --load --platform $(DENO_LINUX_PLATFORM) \
		--build-context deno-bin="$$tmp" \
		--build-arg PI_SOURCE_SHA=$(PI_SHA) \
		--build-arg PI_RUNTIME_SHA=$(DENO_RUNTIME_SHA) \
		-t $(DENO_LINUX_IMAGE) \
		-f Dockerfile.deno .
	@mkdir -p "$(OUT_DIR)"
	@cid=$$(docker create -v $(DENO_LINUX_VOLUME):/artifacts $(DENO_LINUX_IMAGE)); \
	docker start -a $$cid; \
	docker cp $$cid:/artifacts/pi-deno "$(OUT_DIR)/$(DENO_MUSL_ARTIFACT)"; \
	docker rm $$cid
	@chmod +x "$(OUT_DIR)/$(DENO_MUSL_ARTIFACT)"
	@echo "==> Built $(OUT_DIR)/$(DENO_MUSL_ARTIFACT)"
	# The target binary runs inside its built image under QEMU when emulation is needed.
	docker run --rm --platform $(DENO_LINUX_PLATFORM) \
		$(DENO_LINUX_IMAGE) \
		sh -ec 'apk add --no-cache bash curl nodejs >/dev/null && \
			/app/scripts/smoke-test-binary.sh /app/pi-deno deno && \
			/app/scripts/smoke-test-fake-provider.sh /app/pi-deno'

deno-test:
	@./scripts/smoke-test-binary.sh "$(abspath $(OUT_DIR)/$(DENO_MUSL_ARTIFACT))" deno

deno-fetch-linux-arm64:
	@if ! test -x "$(DENO_BIN)" || ! test -x "$(DENO_RT_BIN)"; then \
		mkdir -p "$(dir $(DENO_BIN))" "$(dir $(DENO_RT_BIN))"; \
		curl --fail --location --retry 3 -o "$(DENO_BIN).zip" "$(DENO_RELEASE_BASE_URL)/deno-quickjs-aarch64-unknown-linux-musl.zip"; \
		echo "$(DENO_LINUX_ARM64_COMPILER_SHA256)  $(DENO_BIN).zip" | sha256sum -c -; \
		unzip -p "$(DENO_BIN).zip" deno-quickjs-aarch64-unknown-linux-musl > "$(DENO_BIN)"; \
		curl --fail --location --retry 3 -o "$(DENO_RT_BIN).zip" "$(DENO_RELEASE_BASE_URL)/denort-quickjs-aarch64-unknown-linux-musl.zip"; \
		echo "$(DENO_LINUX_ARM64_RUNTIME_SHA256)  $(DENO_RT_BIN).zip" | sha256sum -c -; \
		unzip -p "$(DENO_RT_BIN).zip" denort-quickjs-aarch64-unknown-linux-musl > "$(DENO_RT_BIN)"; \
		chmod 0755 "$(DENO_BIN)" "$(DENO_RT_BIN)"; \
	fi

deno-fetch-linux-x86_64:
	@if ! test -x "$(DENO_BIN)" || ! test -x "$(DENO_RT_BIN)"; then \
		mkdir -p "$(dir $(DENO_BIN))" "$(dir $(DENO_RT_BIN))"; \
		curl --fail --location --retry 3 -o "$(DENO_BIN).zip" "$(DENO_RELEASE_BASE_URL)/deno-quickjs-x86_64-unknown-linux-musl.zip"; \
		echo "$(DENO_LINUX_X86_64_COMPILER_SHA256)  $(DENO_BIN).zip" | sha256sum -c -; \
		unzip -p "$(DENO_BIN).zip" deno-quickjs-x86_64-unknown-linux-musl > "$(DENO_BIN)"; \
		curl --fail --location --retry 3 -o "$(DENO_RT_BIN).zip" "$(DENO_RELEASE_BASE_URL)/denort-quickjs-x86_64-unknown-linux-musl.zip"; \
		echo "$(DENO_LINUX_X86_64_RUNTIME_SHA256)  $(DENO_RT_BIN).zip" | sha256sum -c -; \
		unzip -p "$(DENO_RT_BIN).zip" denort-quickjs-x86_64-unknown-linux-musl > "$(DENO_RT_BIN)"; \
		chmod 0755 "$(DENO_BIN)" "$(DENO_RT_BIN)"; \
	fi

# Build pi-deno natively on macOS 26+ arm64. Unlike the Linux target, this
# intentionally uses the normal macOS dynamic system libraries and does not
# use musl, static-linking checks, or the musl allocator.
deno-macos-aarch64: export PI_RUNTIME_SHA=$(DENO_MACOS_RUNTIME_SHA)
deno-macos-aarch64: export PI_RUNTIME_VERSION=$(DENO_MACOS_RUNTIME_VERSION)
deno-macos-aarch64: deno-fetch-macos-aarch64 build
	@test "$(OS_NAME)" = darwin || { echo "macOS targets require macOS 26 or newer" >&2; exit 1; }
	@test "$(OS_ARCH)" = arm64 || { echo "macOS targets require an arm64 host" >&2; exit 1; }
	@macos_major=$$(sw_vers -productVersion | cut -d. -f1); \
	test "$$macos_major" -ge 26 || { echo "macOS targets require macOS 26 or newer" >&2; exit 1; }
	@if ! test -x "$(DENO_MACOS_BIN)" || ! test -x "$(DENO_MACOS_RT_BIN)"; then \
		$(MAKE) --no-print-directory deno-fetch-macos-aarch64 DENO_MACOS_BIN="$(DENO_MACOS_BIN)" DENO_MACOS_RT_BIN="$(DENO_MACOS_RT_BIN)"; \
	fi
	@test -x "$(DENO_MACOS_BIN)" || { echo "DENO_MACOS_BIN must point to the QuickJS macOS deno executable" >&2; exit 1; }
	@test -x "$(DENO_MACOS_RT_BIN)" || { echo "DENO_MACOS_RT_BIN must point to the matching QuickJS macOS denort executable" >&2; exit 1; }
	@tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT; \
	$(ESBUILD) packages/coding-agent/dist/deno/cli.js \
		--bundle \
		--platform=node \
		--format=esm \
		--main-fields=module,main \
		--banner:js='import { createRequire as __piDenoCreateRequire } from "node:module"; const require = __piDenoCreateRequire(import.meta.url);' \
		--outfile="$$tmp/pi-deno-bundle.js"; \
	node scripts/prepare-deno-bundle.mjs \
		"$$tmp/pi-deno-bundle.js" "$$tmp/pi-deno-bundle.cjs"; \
	DENORT_BIN="$(DENO_MACOS_RT_BIN)" "$(DENO_MACOS_BIN)" compile --no-check --allow-all \
		--engine quickjs --output "$$tmp/pi-deno" "$$tmp/pi-deno-bundle.cjs"; \
	mkdir -p "$(OUT_DIR)"; \
	cp "$$tmp/pi-deno" "$(OUT_DIR)/$(DENO_MACOS_ARTIFACT)"; \
	chmod +x "$(OUT_DIR)/$(DENO_MACOS_ARTIFACT)"; \
	file "$(OUT_DIR)/$(DENO_MACOS_ARTIFACT)"; \
	"$(OUT_DIR)/$(DENO_MACOS_ARTIFACT)" --version
	@$(MAKE) --no-print-directory deno-macos-aarch64-test \
		DENO_MACOS_ARTIFACT="$(DENO_MACOS_ARTIFACT)" OUT_DIR="$(OUT_DIR)"

deno-fetch-macos-aarch64:
	@if ! test -x "$(DENO_MACOS_BIN)" || ! test -x "$(DENO_MACOS_RT_BIN)"; then \
		mkdir -p "$(dir $(DENO_MACOS_BIN))" "$(dir $(DENO_MACOS_RT_BIN))"; \
		curl --fail --location --retry 3 -o "$(DENO_MACOS_BIN).zip" "$(DENO_RELEASE_BASE_URL)/deno-quickjs-aarch64-apple-darwin.zip"; \
		echo "$(DENO_MACOS_COMPILER_SHA256)  $(DENO_MACOS_BIN).zip" | shasum -a 256 -c -; \
		unzip -p "$(DENO_MACOS_BIN).zip" deno-quickjs-aarch64-apple-darwin > "$(DENO_MACOS_BIN)"; \
		curl --fail --location --retry 3 -o "$(DENO_MACOS_RT_BIN).zip" "$(DENO_RELEASE_BASE_URL)/denort-quickjs-aarch64-apple-darwin.zip"; \
		echo "$(DENO_MACOS_RUNTIME_SHA256)  $(DENO_MACOS_RT_BIN).zip" | shasum -a 256 -c -; \
		unzip -p "$(DENO_MACOS_RT_BIN).zip" denort-quickjs-aarch64-apple-darwin > "$(DENO_MACOS_RT_BIN)"; \
		chmod 0755 "$(DENO_MACOS_BIN)" "$(DENO_MACOS_RT_BIN)"; \
	fi

deno-macos-aarch64-test:
	@./scripts/smoke-test-binary.sh "$(abspath $(OUT_DIR)/$(DENO_MACOS_ARTIFACT))" deno-macos-aarch64
	@./scripts/smoke-test-fake-provider.sh "$(abspath $(OUT_DIR)/$(DENO_MACOS_ARTIFACT))"

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
