/**
 * Process @file CLI arguments into text content
 */

import { access, readFile, stat } from "node:fs/promises";
import chalk from "chalk";
import { resolve } from "path";
import { resolveReadPath } from "../core/tools/path-utils.ts";
import { IMAGE_ATTACHMENT_REFUSED_MESSAGE } from "../utils/image-process.ts";
import { detectSupportedImageMimeTypeFromFile } from "../utils/mime.ts";

export interface ProcessedFiles {
	text: string;
}

/** Process @file arguments into text content */
export async function processFileArguments(fileArgs: string[]): Promise<ProcessedFiles> {
	let text = "";

	for (const fileArg of fileArgs) {
		// Expand and resolve path (handles ~ expansion and macOS screenshot Unicode spaces)
		const absolutePath = resolve(resolveReadPath(fileArg, process.cwd()));

		// Check if file exists
		try {
			await access(absolutePath);
		} catch {
			console.error(chalk.red(`Error: File not found: ${absolutePath}`));
			process.exit(1);
		}

		// Check if file is empty
		const stats = await stat(absolutePath);
		if (stats.size === 0) {
			// Skip empty files
			continue;
		}

		const mimeType = await detectSupportedImageMimeTypeFromFile(absolutePath);

		if (mimeType) {
			// Image attachments are not supported; note the file and omit its contents.
			text += `<file name="${absolutePath}">${IMAGE_ATTACHMENT_REFUSED_MESSAGE}</file>\n`;
		} else {
			// Handle text file
			try {
				const content = await readFile(absolutePath, "utf-8");
				text += `<file name="${absolutePath}">\n${content}\n</file>\n`;
			} catch (error: unknown) {
				const message = error instanceof Error ? error.message : String(error);
				console.error(chalk.red(`Error: Could not read file ${absolutePath}: ${message}`));
				process.exit(1);
			}
		}
	}

	return { text };
}
