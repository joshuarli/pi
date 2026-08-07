import { createRequire } from "module";
import { dirname, join } from "path";
import { pathToFileURL } from "url";

export type ClipboardModule = {
	getText: () => Promise<string>;
	setText: (text: string) => Promise<void>;
	hasImage: () => boolean;
	getImageBinary: () => Promise<Array<number>>;
};

type ClipboardRequire = (id: string) => unknown;

const moduleRequire = createRequire(import.meta.url);
const executableDirRequire = createRequire(pathToFileURL(join(dirname(process.execPath), "package.json")).href);
const hasDisplay = process.platform !== "linux" || Boolean(process.env.DISPLAY || process.env.WAYLAND_DISPLAY);

// The QuickJS Deno build intentionally does not provide the V8/Node-API host
// symbols required by native addons. `@mariozechner/clipboard` tries several
// platform bindings during require(), and each failed binding otherwise emits
// a diagnostic from the runtime before we can catch the load error.
type RuntimeVersions = { deno?: string; typescript?: string };

export function supportsNativeNodeAddons(versions: RuntimeVersions = process.versions as RuntimeVersions): boolean {
	return !(versions.deno && versions.typescript === "n/a");
}

export function loadClipboardNative(
	requires: readonly ClipboardRequire[] = [moduleRequire, executableDirRequire],
): ClipboardModule | null {
	for (const requireClipboard of requires) {
		try {
			return requireClipboard("@mariozechner/clipboard") as ClipboardModule;
		} catch {
			// Try the next resolution root.
		}
	}
	return null;
}

const clipboard =
	!process.env.TERMUX_VERSION && hasDisplay && supportsNativeNodeAddons() ? loadClipboardNative() : null;

export { clipboard };
