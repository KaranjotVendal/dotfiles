#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const SCRAPING_DIR = path.join(os.homedir(), ".cache", "browser-tools");
const PID_FILE = path.join(SCRAPING_DIR, "browser.pid");

function readPid() {
	try {
		return Number(fs.readFileSync(PID_FILE, "utf8").trim());
	} catch {
		return null;
	}
}

function isAlive(pid) {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}

const pid = readPid();

if (!pid || !isAlive(pid)) {
	console.log("✗ No managed Chrome instance is currently running");
	// Clean up stale pidfile/locks even if already dead.
	try {
		fs.rmSync(PID_FILE, { force: true });
	} catch {}
	for (const lock of ["SingletonLock", "SingletonSocket", "SingletonCookie"]) {
		try {
			fs.rmSync(path.join(SCRAPING_DIR, lock), { force: true });
		} catch {}
	}
	process.exit(0);
}

try {
	process.kill(pid, "SIGTERM");
} catch (e) {
	console.error("✗ Failed to stop Chrome:", e.message);
	process.exit(1);
}

// Wait briefly for the process to exit.
let stopped = false;
for (let i = 0; i < 20; i++) {
	if (!isAlive(pid)) {
		stopped = true;
		break;
	}
	await new Promise((r) => setTimeout(r, 250));
}

if (!stopped) {
	console.error("✗ Chrome did not stop gracefully; sending SIGKILL");
	try {
		process.kill(pid, "SIGKILL");
	} catch (e) {
		console.error("✗ Failed to kill Chrome:", e.message);
		process.exit(1);
	}
}

// Clean up pidfile and locks.
try {
	fs.rmSync(PID_FILE, { force: true });
} catch {}
for (const lock of ["SingletonLock", "SingletonSocket", "SingletonCookie"]) {
	try {
		fs.rmSync(path.join(SCRAPING_DIR, lock), { force: true });
	} catch {}
}

console.log("✓ Chrome stopped");
