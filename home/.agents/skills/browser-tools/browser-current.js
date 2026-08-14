#!/usr/bin/env node

import puppeteer from "puppeteer-core";

const BROWSER_URL = "http://localhost:9222";

const browser = await Promise.race([
	puppeteer.connect({
		browserURL: BROWSER_URL,
		defaultViewport: null,
	}),
	new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 5000)),
]).catch((e) => {
	console.error("✗ Could not connect to browser:", e.message);
	console.error("  Run: browser-start.js");
	process.exit(1);
});

const page = (await browser.pages()).at(-1);
if (!page) {
	console.error("✗ No active tab found");
	await browser.disconnect();
	process.exit(1);
}

const title = await page.title();
const url = page.url();

console.log(`Title: ${title}`);
console.log(`URL:   ${url}`);

await browser.disconnect();
