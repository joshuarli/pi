import { readFile, writeFile } from "node:fs/promises";
import { transform } from "esbuild";

const [inputPath, outputPath] = process.argv.slice(2);

if (!inputPath || !outputPath) {
	throw new Error("usage: node scripts/prepare-deno-bundle.mjs <input> <output>");
}

let source = await readFile(inputPath, "utf8");

// CommonJS has no top-level await, while these are the only top-level awaits
// emitted by the Deno entrypoint. The CLI promise remains live through its
// event loop after this sequencing is made fire-and-forget.
const topLevelAwaitExpressions = [
	"await Promise.resolve().then(() => (init_register_bedrock(), register_bedrock_exports));",
	"await Promise.resolve().then(() => (init_cli(), cli_exports));",
];
for (const expression of topLevelAwaitExpressions) {
	if (!source.includes(expression)) {
		throw new Error(`expected top-level await expression was not found: ${expression}`);
	}
	source = source.replace(expression, expression.slice("await ".length));
}

const transformed = await transform(source, {
	format: "cjs",
	platform: "node",
	supported: { "dynamic-import": false },
});

// esbuild represents import.meta with an empty object for CommonJS. Give the
// bundled runtime a stable file URL so createRequire(), path resolution, and
// the standalone extension loader retain their normal semantics.
const importMeta =
	'const import_meta = { url: require("node:url").pathToFileURL(process.execPath).href, resolve: (specifier) => new URL(specifier, require("node:url").pathToFileURL(process.execPath).href).href };';
if (!transformed.code.includes("const import_meta = {};")) {
	throw new Error("expected esbuild CommonJS import.meta binding was not found");
}
const output = transformed.code.replace("const import_meta = {};", importMeta);

await writeFile(outputPath, output);
