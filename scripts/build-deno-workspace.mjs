// Build the packages needed by the Deno standalone entrypoint.
//
// The repository's normal package scripts are Bun-oriented because Bun remains
// the supported local build runtime. Deno images use this explicit build path
// so the prebuilt Deno binary owns dependency installation, TypeScript builds,
// model-data hydration, and asset preparation from start to finish.

const repoRoot = Deno.cwd();
const deno = Deno.execPath();

async function run(args, cwd = repoRoot) {
	const command = new Deno.Command(deno, {
		args: ["run", "--allow-all", ...args],
		cwd,
		stdout: "inherit",
		stderr: "inherit",
	});
	const output = await command.output();
	if (!output.success) {
		throw new Error(`Deno command failed (${output.code}): ${args.join(" ")}`);
	}
}

async function runTool(name, args) {
	await run([`node_modules/.bin/${name}`, ...args]);
}

async function copyDirectory(source, destination) {
	await Deno.mkdir(destination, { recursive: true });
	for await (const entry of Deno.readDir(source)) {
		const sourcePath = `${source}/${entry.name}`;
		const destinationPath = `${destination}/${entry.name}`;
		if (entry.isDirectory) await copyDirectory(sourcePath, destinationPath);
		else if (entry.isFile) await Deno.copyFile(sourcePath, destinationPath);
	}
}

async function removeIfPresent(path) {
	try {
		await Deno.remove(path, { recursive: true });
	} catch (error) {
		if (!(error instanceof Deno.errors.NotFound)) throw error;
	}
}

await run(["packages/ai/scripts/generate-models.ts", "--strict", "--data-only"]);

await runTool("tsgo", ["-p", "packages/tui/tsconfig.build.json"]);
await runTool("tsgo", ["-p", "packages/telemetry/tsconfig.build.json"]);
await run(["packages/ai/scripts/check-model-data.ts"]);
await runTool("tsgo", ["-p", "packages/ai/tsconfig.build.json"]);
await removeIfPresent("packages/ai/dist/providers/data");
await copyDirectory("packages/ai/src/providers/data", "packages/ai/dist/providers/data");
await runTool("tsgo", ["-p", "packages/agent/tsconfig.build.json"]);
await runTool("tsgo", ["-p", "packages/session-backends/sqlite-node/tsconfig.build.json"]);
await run(["packages/session-backends/sqlite-node/scripts/prepare-dist.mjs", "copy-sqlite-migrations"]);
await runTool("tsgo", ["-p", "packages/protocol/tsconfig.build.json"]);
await runTool("tsgo", ["-p", "packages/client/tsconfig.build.json"]);
await runTool("tsgo", ["-p", "packages/server/tsconfig.build.json"]);

await run(["scripts/generate-version.mjs"]);
await run(["scripts/generate-embedded-assets.mjs"]);
await runTool("tsgo", ["-p", "packages/coding-agent/tsconfig.build.json"]);
await runTool("shx", ["chmod", "+x", "packages/coding-agent/dist/cli.js", "packages/coding-agent/dist/rpc-entry.js"]);

const codingAgent = "packages/coding-agent";
await runTool("shx", ["mkdir", "-p", `${codingAgent}/dist/modes/interactive/theme`]);
await runTool("shx", ["cp", `${codingAgent}/src/modes/interactive/theme/*.json`, `${codingAgent}/dist/modes/interactive/theme/`]);
await runTool("shx", ["mkdir", "-p", `${codingAgent}/dist/modes/interactive/assets`]);
await runTool("shx", ["cp", `${codingAgent}/src/modes/interactive/assets/*.png`, `${codingAgent}/dist/modes/interactive/assets/`]);
await runTool("shx", ["mkdir", "-p", `${codingAgent}/dist/core/export-html/vendor`]);
await runTool("shx", ["cp", `${codingAgent}/src/core/export-html/template.html`, `${codingAgent}/src/core/export-html/template.css`, `${codingAgent}/src/core/export-html/template.js`, `${codingAgent}/dist/core/export-html/`]);
await runTool("shx", ["cp", `${codingAgent}/src/core/export-html/vendor/*.js`, `${codingAgent}/dist/core/export-html/vendor/`]);
