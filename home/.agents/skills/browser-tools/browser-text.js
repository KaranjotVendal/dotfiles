#!/usr/bin/env node

import puppeteer from "puppeteer-core";
import { JSDOM } from "jsdom";
import { extractTextFromDocument } from "./lib/extract-text.js";

const args = process.argv.slice(2);
const selectorFlag = args.find((a) => a.startsWith("--selector="));
const maxLengthFlag = args.find((a) => a.startsWith("--max-length="));
const help = args.includes("--help") || args.includes("-h");

if (help) {
	console.log("Usage: browser-text.js [--selector=<css-selector>] [--max-length=<n>]");
	console.log("\nExamples:");
	console.log("  browser-text.js");
	console.log("  browser-text.js --selector=article");
	console.log("  browser-text.js --selector='main article' --max-length=2000");
	process.exit(0);
}

const selector = selectorFlag ? selectorFlag.slice("--selector=".length) : undefined;
const maxLength = maxLengthFlag ? Number(maxLengthFlag.slice("--max-length=".length)) : undefined;

if (maxLengthFlag && (!Number.isInteger(maxLength) || maxLength <= 0)) {
	console.error("✗ --max-length must be a positive integer");
	process.exit(1);
}

const browser = await Promise.race([
	puppeteer.connect({
		browserURL: "http://localhost:9222",
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

const html = await page.evaluate(() => document.documentElement.outerHTML);
const dom = new JSDOM(html, { url: page.url() });
const text = extractTextFromDocument(dom.window.document, { selector, maxLength });

console.log(text);

await browser.disconnect();
