import stubPiTui from "../headless/stub-pi-tui.plugin.ts";
import { mkdir, rename } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { cwd } from "node:process";

const outfile = resolve(process.argv[2] ?? "");
if (!outfile) {
	console.error("usage: bun scripts/build-headless.mts <outfile>");
	process.exit(1);
}

await mkdir(dirname(outfile), { recursive: true });

// `bun build --compile` (via Bun.build) ignores `outfile` and always writes a
// single binary named after the entrypoint (`cli`) into `outdir`; capture it
// and rename onto the requested output path.
const result = await Bun.build({
	entrypoints: [resolve(cwd(), "dist/bun/cli.js")],
	plugins: [stubPiTui],
	target: "bun",
	compile: true,
	outdir: dirname(outfile),
});

if (!result.success) {
	for (const log of result.logs) console.error(log);
	process.exit(1);
}

const built = result.outputs?.[0]?.path;
if (built && resolve(built) !== outfile) {
	await rename(built, outfile);
}