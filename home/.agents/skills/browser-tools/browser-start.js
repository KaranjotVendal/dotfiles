#!/usr/bin/env node

import { spawn, execSync } from "node:child_process";
import puppeteer from "puppeteer-core";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const useProfile = process.argv[2] === "--profile";

if (process.argv[2] && process.argv[2] !== "--profile") {
	console.log("Usage: browser-start.js [--profile]");
	console.log("\nOptions:");
	console.log("  --profile  Copy your default Chrome profile (cookies, logins)");
	process.exit(1);
}

const SCRAPING_DIR = path.join(os.homedir(), ".cache", "browser-tools");
const PID_FILE = path.join(SCRAPING_DIR, "browser.pid");
const BROWSER_URL = "http://localhost:9222";

// Detect the browser executable and profile directory from BROWSER_TOOLS_CHROME.
function detectBrowser() {
	const exe = process.env.BROWSER_TOOLS_CHROME;
	if (!exe) {
		throw new Error(
			"Set BROWSER_TOOLS_CHROME to the full path of your browser executable (e.g. Helium, Chrome, or Chromium).",
		);
	}

	try {
		if (!fs.statSync(exe).isFile()) {
			throw new Error(`Not a file: ${exe}`);
		}
	} catch (e) {
		throw new Error(`Browser executable not found: ${exe}`);
	}

	const basename = path.basename(exe).toLowerCase();
	let profileName;
	if (basename.includes("helium")) {
		profileName = "net.imput.helium";
	} else if (basename.includes("chrome")) {
		profileName = "google-chrome";
	} else if (basename.includes("chromium")) {
		profileName = "chromium";
	} else {
		profileName = null;
	}

	let sourceProfile;
	if (profileName) {
		const platform = os.platform();
		if (platform === "darwin") {
			if (profileName === "net.imput.helium") {
				sourceProfile = path.join(os.homedir(), "Library", "Application Support", "Helium");
			} else {
				sourceProfile = path.join(os.homedir(), "Library", "Application Support", "Google", "Chrome");
			}
		} else if (platform === "linux") {
			sourceProfile = path.join(os.homedir(), ".config", profileName);
		}
	}

	return { exe, sourceProfile };
}

// Check if already running on :9222.
try {
	const browser = await puppeteer.connect({
		browserURL: BROWSER_URL,
		defaultViewport: null,
	});
	await browser.disconnect();
	console.log("✓ Chrome already running on :9222");
	process.exit(0);
} catch {}

// Setup profile directory.
fs.mkdirSync(SCRAPING_DIR, { recursive: true });

// Remove SingletonLock to allow new instance.
for (const lock of ["SingletonLock", "SingletonSocket", "SingletonCookie"]) {
	try {
		fs.rmSync(path.join(SCRAPING_DIR, lock), { force: true });
	} catch {}
}

const { exe: chromePath, sourceProfile } = detectBrowser();

if (useProfile) {
	if (!sourceProfile) {
		console.error("✗ Could not determine profile directory for this browser");
		process.exit(1);
	}

	if (!fs.existsSync(sourceProfile)) {
		console.error(`✗ Could not find profile to copy: ${sourceProfile}`);
		process.exit(1);
	}

	console.log("Syncing profile...");
	try {
		execSync(
			`rsync -a --delete \
				--exclude='SingletonLock' \
				--exclude='SingletonSocket' \
				--exclude='SingletonCookie' \
				--exclude='*/Sessions/*' \
				--exclude='*/Current Session' \
				--exclude='*/Current Tabs' \
				--exclude='*/Last Session' \
				--exclude='*/Last Tabs' \
				"${sourceProfile}/" "${SCRAPING_DIR}/"`,
			{ stdio: "pipe" },
		);
	} catch (e) {
		console.error("✗ Failed to sync profile:", e.message);
		process.exit(1);
	}
}

// Start Chrome with flags to force new instance.
const proc = spawn(
	chromePath,
	[
		"--remote-debugging-port=9222",
		`--user-data-dir=${SCRAPING_DIR}`,
		"--no-first-run",
		"--no-default-browser-check",
	],
	{ detached: true, stdio: "ignore" },
);
proc.unref();

fs.writeFileSync(PID_FILE, String(proc.pid));

// Wait for Chrome to be ready.
let connected = false;
for (let i = 0; i < 30; i++) {
	try {
		const browser = await puppeteer.connect({
			browserURL: BROWSER_URL,
			defaultViewport: null,
		});
		await browser.disconnect();
		connected = true;
		break;
	} catch {
		await new Promise((r) => setTimeout(r, 500));
	}
}

if (!connected) {
	console.error("✗ Failed to connect to Chrome");
	process.exit(1);
}

console.log(`✓ Chrome started on :9222${useProfile ? " with your profile" : ""}`);
