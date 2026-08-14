#!/usr/bin/env node

import puppeteer from "puppeteer-core";

const BROWSER_URL = "http://localhost:9222";

try {
	const browser = await Promise.race([
		puppeteer.connect({
			browserURL: BROWSER_URL,
			defaultViewport: null,
		}),
		new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 3000)),
	]);
	await browser.disconnect();
	console.log("✓ Chrome is running on :9222");
} catch {
	console.log("✗ Chrome is not running on :9222");
	console.log("  Run: browser-start.js");
	process.exit(1);
}
