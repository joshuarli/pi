/**
 * Standalone binary asset extraction.
 *
 * Compiled binaries (make bun / make deno) have no files shipped next to the
 * executable. Theme files, HTML export templates, docs, examples, README,
 * CHANGELOG, and package.json are inlined at build time by
 * scripts/generate-embedded-assets.mjs and extracted here to a cache directory
 * at startup. PI_PACKAGE_DIR is pointed at that directory so every package
 * asset getter in config.ts resolves to the extracted files.
 *
 * This module must be imported (for its side effects) before config.ts is
 * evaluated, because config.ts reads package.json at module load.
 */

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { EMBEDDED_ASSETS, EMBEDDED_ASSETS_CACHE_KEY } from "./embedded-assets.generated.ts";

const COMPLETE_MARKER = ".complete";

function extractAssets(packageDir: string): void {
	for (const [relativePath, base64] of Object.entries(EMBEDDED_ASSETS)) {
		const filePath = join(packageDir, relativePath);
		mkdirSync(dirname(filePath), { recursive: true });
		writeFileSync(filePath, Buffer.from(base64, "base64"));
	}
	writeFileSync(join(packageDir, COMPLETE_MARKER), EMBEDDED_ASSETS_CACHE_KEY);
}

const packageDir: string | undefined = (() => {
	if (Object.keys(EMBEDDED_ASSETS).length === 0) {
		return undefined;
	}
	const cacheDir = join(tmpdir(), `pi-embedded-${EMBEDDED_ASSETS_CACHE_KEY}`);
	if (existsSync(join(cacheDir, COMPLETE_MARKER))) {
		return cacheDir;
	}
	try {
		extractAssets(cacheDir);
		return cacheDir;
	} catch {
		return undefined;
	}
})();

if (packageDir) {
	process.env.PI_PACKAGE_DIR ||= packageDir;
	process.env.PI_STANDALONE_BINARY ||= "1";
}
