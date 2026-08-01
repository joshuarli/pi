import { describe, expect, it } from "vitest";
import { SettingsManager } from "../src/core/settings-manager.ts";

describe("blockImages setting", () => {
	it("should default blockImages to false", () => {
		const manager = SettingsManager.inMemory({});
		expect(manager.getBlockImages()).toBe(false);
	});

	it("should return true when blockImages is set to true", () => {
		const manager = SettingsManager.inMemory({ images: { blockImages: true } });
		expect(manager.getBlockImages()).toBe(true);
	});

	it("should persist blockImages setting via setBlockImages", () => {
		const manager = SettingsManager.inMemory({});
		expect(manager.getBlockImages()).toBe(false);

		manager.setBlockImages(true);
		expect(manager.getBlockImages()).toBe(true);

		manager.setBlockImages(false);
		expect(manager.getBlockImages()).toBe(false);
	});
});
