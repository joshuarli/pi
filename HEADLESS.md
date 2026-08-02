# Headless, non-interactive pi build

Goal: produce a lean `pi` binary that never ships the terminal UI. A headless
build is used where the TUI is dead weight: servers, pipelines, RPC, JSON
output, single-shot `-p` runs. This is a fork-specific concern; the document
describes how to strip the TUI out at bundle time while keeping rebase onto
upstream painless.

`pi` is one monorepo (`packages/`). The runtime binary (`pi-bun`) is compiled by
`bun build --compile` in `Makefile`. Today the CLI, tools, and interactive TUI
are bundled together in every binary, and the TUI (`@earendil-works/pi-tui`) is
imported by modules far outside interactive mode — so a plain "skip the TUI
flag" is not enough: excluding it must be done in the **dependency graph**, not
at runtime.

## Constraints discovered

- `bun build` has **no `--define`**, so build-time constant gates (the esbuild
  `--define` trick) are not directly available for the bun binary.
- `@earendil-works/pi-tui` is statically imported across the whole CLI
  (`core/tools/*`, `cli/*`, `core/extensions/*`, `mode-agnostic` modules), not
  just `modes/interactive`. Any entrypoint that imports the tools pulls the TUI
  in transitively.
- **Tried, unreliable: `tsconfig` `paths` for package-name specifiers.** A
  `paths` remap of `@earendil-works/pi-tui` to a local stub worked in isolated
  reproductions, but not inside this repo layout: the entrypoint's nearest
  tsconfig (`dist/bun/cli.js` walk-up) and the root `tsconfig.json` `paths`
  (which map `pi-tui` → `packages/tui/src`) plus a `node_modules` symlink all
  win over a per-package `--tsconfig` `paths` entry. **Do not** rely on
  `tsconfig` `paths` for this.
- **Use a `bun` build plugin instead.** `onResolve` runs for every encountered
  import and returns a fully-absolute file path, which cannot be shadowed by
  package / tsconfig resolution. Verified: a `--tsconfig`+root-tsconfig
  reproduction resolves the stub via plugin even when the real TUI package is
  symlinked and mapped by the root tsconfig.

## Size reality (why we stub, and what we actually gain)

Measured (this fork's headless stub applied):

- Empty `bun build --compile` hello world: **~61.5MB** — the bun runtime floor.
- Full `pi-bun` (`7805b9409`, bun 1.3.14): **80,452,066 bytes**.
- Headless (TUI stubbed out): **80,039,266 bytes** — **~413KB smaller**. The
  real `pi-tui` library plus its dependencies are dropped, but the TUI is only a
  small slice of the ~19MB non-runtime payload, so the win is modest (the bun
  runtime dominates).

Consequence: excluding the TUI is *not* the size lever it first appeared to be.
It buys ~0.4MB against a 61.6MB floor. The same "dependency-graph stub" trick is
potentially far more profitable when applied to the **provider SDKs** (`openai`,
anthropic, google, mistral, ...) that account for much of the remaining
application payload. We only need the providers we actually use (e.g.
**openrouter**). The fork ships only the TUI trim; the provider trim is
**scoped out** because it cannot be done at bundle time (see "Provider SDK trim:
why it does not work" below).

## Provider SDK trim: why it does not work (scoped out)

A plugin remap of the bare specifier `@earendil-works/pi-ai/providers/all` does
**not** cut the provider SDKs. `compat.ts` inside `@earendil-works/pi-ai`
imports `./providers/all.js` **relatively** and executes `registerBuiltInApiProviders()`
+ `builtinModels()` at module load, so the entire catalog (~37 provider
implementations + their bundled SDKs and model data) still bundles regardless of
a bare-specifier stub. Measured: pointing the plugin at an openrouter-only
`providers/all` stub shrank the binary by only **~16KB** — the relative import
inside the package bypasses the remap entirely, and `anthropicProvider` /
`openaiProvider` markers remain in the binary.

The only effective route would be to edit upstream `packages/ai/src/providers/all.ts`
(keep openrouter + radius, drop the rest) and regenerate `models.generated.ts` —
a genuine fork divergence, poison for the rebase-friendly goal. **Decision:
stop at the TUI trim (claimed ~413KB) and do not touch the provider catalog.**

## Approach

Trade-off: a *fully* non-interactive headless `main.ts` forces edits to upstream
files (`resolveAppMode`, the mode dispatch) which is poison for rebasing. The
cheap, rebase-friendly version is a **build-graph stub**: keep all source
untouched, swap heavy modules for skeletons only at bundle time.

1. Keep all source untouched.
2. Add a local **stub** module (`headless/pi-tui-stub.ts`) providing no-op
   runtime exports for every value the bundled `dist` imports from `pi-tui`.
3. Add a **`bun` build plugin** (`headless/stub-pi-tui.plugin.ts`) whose
   `onResolve` maps `@earendil-works/pi-tui` and `@earendil-works/pi-tui/*` to
   the stub. Plugin resolution is absolute and deterministic.
4. Add a build script `scripts/build-headless.mts` that drives `Bun.build`
   programmatically with the plugin (`compile: true`), and a `Makefile headless`
   target that invokes it.

The upstream tool modules still `import { Box, Text, ... } from
"@earendil-works/pi-tui"` — the plugin lets them `resolve` against the stub, so
upstream files are never edited and rebase stays a fast-forward. `Bun.build`
bundles the **compiled** `dist/bun/cli.js` (tsgo already stripped type-only
imports), so the stub only needs runtime value exports — see below.

This deliberately does **not** exclude `modes/interactive/*` code (that would
require editing `main.ts`); it removes the `pi-tui` library. If interactive-mode
code itself must go, that is a later, larger divergence and is out of scope for
the rebase-priority version.

## What the stub must provide

The stub must provide every **runtime value** import used by the bundled graph.
`bun build --compile` bundles the compiled `dist/bun/cli.js`, where `tsgo` has
already erased `import type {...}` references, so type-only names (`KeyId`,
`Component`, `TUI`, `MarkdownTheme`, `ScrollViewScrollbar`, ...) need no stub
member — only values actually referenced at runtime. They can still be re-exported
from the stub as `type` to keep the headless tsconfig type-check happy, but the
bundle never sees them.

Runtime value imports collected across the whole compiled `dist/` (what the
bundle actually links):

- `Text`, `Container`, `Box`, `Spacer`, `TruncatedText`, `Image`, `Key`,
  `Input`, `Editor`, `Loader`, `CancellableLoader`, `SelectList`, `SettingsList`,
  `CombinedAutocompleteProvider`
- `ProcessTerminal`, `TuiAltScreen`, `TuiMainScreen`, `KeybindingsManager`
- `TUI_KEYBINDINGS`
- `getCapabilities`, `getCellDimensions`, `getImageDimensions`,
  `getKeybindings`, `setKeybindings`, `matchesKey`
- `truncateToWidth`, `visibleWidth`, `hyperlink`, `imageFallback`, `fuzzyMatch`,
  `fuzzyFilter`, `sliceByColumn`, `wrapTextWithAnsi`
- Extensions loader: a namespace import `import * as _bundledPiTui from
  "@earendil-works/pi-tui"` (used as the runtime provider registry key), so the
  stub must exist as a module with a stable identity.

Stub semantics: headless never runs the TUI, so the members can be minimal
no-ops — e.g. `getCapabilities () => ({ hyperlinks:false, images:false, ... })`,
`Text`/`Container`/`Box`/`Spacer` as class stubs, `hyperlink`/`imageFallback`
identity transforms, `getKeybindings` returning `[]`, etc. They only need to be
importable and structurally close to what callers reference.

Implementation detail: the stub and plugin live in their own `headless/`
directory (not `src/`) so the normal build and root `npm run check` (which map
`pi-tui` to the real `packages/tui` and type-check `src/**`) never see them.
Because the headless build compiles the already-`dist`-compiled `cli.js`, the
stub is only seen by the bundler resolver, not by `tsgo` — so it never needs to
satisfy the full `pi-tui` type surface. It must only be a valid TS module that
exports the names above.

## Headless entrypoint (stub-only version)

Because this fork values rebase simplicity, we do **not** add `cli-headless.ts`
or touch `main.ts`. The stub-only headless build reuses the existing
`dist/bun/cli.js` entrypoint unchanged. `pi` is already non-interactive by
default when `stdin`/`stdout` are not a TTY (`resolveAppMode` in `main.ts`), so
a headless binary is functionally just the full binary deployed to a server;
the divergence we ship is only in what the bundler resolves.

`resolveAppMode` already forces `print` when `!stdinIsTTY || !stdoutIsTTY`, so a
pipe/CI invocation naturally takes the print/json/rpc path without any code
change. Forcing `interactive` off explicitly would require an edit we are
deliberately avoiding for rebase-friendliness.

## Makefile changes

Keep the full TUI build as `make bun` (unchanged default). Add a headless
compile that re-bundles the already-built `dist/bun/cli.js` through the plugin
(via `scripts/build-headless.mts`) — no separate `tsgo` step:

```make
headless: deps build
	cd packages/coding-agent && bun scripts/build-headless.mts "$(abspath $(BIN_DIR)/pi-headless)"
	chmod +x "$(abspath $(BIN_DIR)/pi-headless)"
```

`dist/bun/cli.js` comes from the existing `build` step; the plugin only
redirects the bundler's `pi-tui` resolution, so no source or dist changes.
Provider trimming is a bundler/dependency-manifest concern, not a Makefile one
(see below).

Note: `Bun.build` with `compile: true` ignores `outfile` and writes a single
binary named after the entrypoint (`cli`) into `outdir`; the build script
captures the output path and renames it onto the requested name.

## Cross-platform / linux-arm64-musl

The headless stub works for **any** platform bun targets, including the
linux-arm64-musl variant used by Alpine-based consumers (e.g. the xsh gym).
`Dockerfile.bun` builds **both** the full (`pi-bun`) and headless (`pi-headless`)
binaries natively in a linux/arm64 container and stages both into `/artifacts`;
the two Makefile targets extract the one they need:

```make
bun-linux-arm64-musl        # -> pi-<sha>-bun-<version>-linux-arm64-musl
bun-headless-linux-arm64-musl  # -> pi-<sha>-bun-headless-<version>-linux-arm64-musl
```

Verified (linux/arm64, musl): the container compiles `pi-headless` through the
same `headless/stub-pi-tui.plugin.ts`, `verify-binary.sh` confirms musl linkage,
and the resulting headless binary runs `--version` and a full fake-provider
round-trip inside a plain `alpine:3.24` container (with `libstdc++`; the musl
output is musl-dynamic and still needs `libstdc++`/`libgcc_s` — see the Makefile
TODO on a fully static build). Sizes measured: headless linux musl
107,655,032 B vs full linux musl 108,048,248 B (~393KB smaller), consistent
with the darwin delta.

The glibc `bun-linux-arm64` target/image/volume was removed (the musl variant
is the one used). Deno is now out of scope: the `deno`/`deno-test` targets are
commented out in the Makefile.

## Verification

- Smoke-test the headless binary the same way `scripts/smoke-test-binary.sh`
  tests `pi-bun` and `pi-deno`.
- Size-compare `pi-bun` (full) vs `pi-headless`; the headless binary should be
  smaller, chiefly by the dropped `pi-tui` library: **80,039,266 B vs
  80,452,066 B (~413KB)**. Provider trimming was measured and scoped out (see
  above).
- Fake-provider run: run a headless `pi` against the **fake provider** in
  `packages/coding-agent/test/suite/harness.ts` so no network / real model is
  touched (no money spent).

## Open decisions

- Separate `make headless` (done here, keeps `make bun` unchanged) vs making
  headless the default. Currently planning **separate target**.
- The real size lever is **provider SDK trimming**, but it is **scoped out**: a
  bundle-time stub does not work because `@earendil-works/pi-ai`'s `compat.ts`
  imports `providers/all` relatively and pulls the whole catalog at module load.
  Waiting on a decision whether to accept editing upstream `providers/all.ts`
  (a fork divergence) for the larger binary win.
- The stub removes the `pi-tui` *library* but not `modes/interactive/*` code
  (editing `main.ts` would be needed for that). Confirm that residual
  interactive-mode code in the headless binary is acceptable for the
  rebase-friendliness win (residual `interactive.js` still bundles; it just
  cannot render because `pi-tui` classes are stubs).
- Whether to also stub/remove the native clipboard addon (`@mariozechner/
  /*clipboard*`) from the headless build.

## Follow-ups

- [x] Wire a headless fake-provider smoke test into `Makefile` (no real model),
  so headless produces a real reply without a provider API. Done via a local
  **fake OpenAI-compatible server** (`scripts/fake-provider-server.mjs`) + smoke
  script (`scripts/smoke-test-fake-provider.sh`), run by `make headless-test`
  and `make fake-provider-test`. Note: pi ships no binary-level fake provider —
  the `faux` provider exists only in-process (`test/suite/harness.ts`), so a real
  local server is required for binary smoke tests.
- [ ] Decide whether provider SDK trimming (editing upstream `providers/all.ts`)
  is ever worth the fork divergence; currently scoped out.