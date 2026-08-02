import { fileURLToPath } from "node:url";

const STUB_PATH = fileURLToPath(new URL("./pi-tui-stub.ts", import.meta.url));

/**
 * bun build plugin that swaps `@earendil-works/pi-tui` (the TUI) for a no-op
 * stub so the headless binary carries none of the interactive UI code.
 *
 * A tsconfig `paths` remap is not reliable here: in this monorepo the package
 * resolves through the root `tsconfig.json` `paths` (pointing at
 * `packages/tui/src`) plus a `node_modules` symlink, both of which win over a
 * per-package `--tsconfig` `paths` entry. A plugin's `onResolve` runs for every
 * encountered import and returns a fully-absolute file path, which cannot be
 * shadowed by package resolution.
 *
 * Both the exact specifier `@earendil-works/pi-tui` and its subpath form
 * (`@earendil-works/pi-tui/...`) are redirected to the single stub module.
 */
export default {
	name: "stub-pi-tui",
	setup(build) {
		build.onResolve({ filter: /^@earendil-works\/pi-tui$/ }, () => {
			return { path: STUB_PATH, namespace: "file" };
		});
		build.onResolve({ filter: /^@earendil-works\/pi-tui\// }, () => {
			return { path: STUB_PATH, namespace: "file" };
		});
	},
};