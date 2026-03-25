/**
 * Plan Mode Extension - OpenCode Style
 *
 * Implements plan mode like OpenCode: switches to a different agent/model
 * that is configured to be read-only.
 *
 * Usage:
 * - /plan - Switch to plan mode (switches to plan model)
 * - /build - Switch to build mode (switches back to default model)
 *
 * Configuration (in settings.json):
 * - planMode.planModel: model ID to use for plan mode (e.g., "minimax/MiniMax-M2.5")
 * - planMode.planProvider: provider ID (defaults to same as default)
 *
 * Without model configuration, falls back to tool restriction + system prompt.
 */

import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

// Strong system reminder like OpenCode
const PLAN_MODE_SYSTEM_REMINDER = `
================================================================================
SYSTEM REMINDER
================================================================================
Plan mode ACTIVE - you are in READ-ONLY phase

STRICTLY FORBIDDEN:
- ANY file edits, modifications, or system changes
- Using write, edit, or any tool that modifies files
- Running commands that modify the system (git commit, npm install, etc.)

YOU MAY ONLY:
- Read files and explore the codebase
- Analyze and understand the code
- Create plans and describe what changes would need to be made
- Use read, bash (read-only commands only), grep, find

The user indicated that they do not want you to execute yet.
================================================================================
`;

const BUILD_MODE_SYSTEM_REMINDER = `
================================================================================
SYSTEM REMINDER
================================================================================
Build mode ACTIVE - full access enabled

You can now:
- Read, write, edit files
- Execute commands
- Make changes to the codebase

Execute the plan created in plan mode.
================================================================================
`;

export default function planModeExtension(pi: ExtensionAPI): void {
	// Module-level state
	let planModeEnabled = false;
	let planModelConfigured = false;

	// Get configuration from settings
	function getPlanModelConfig(): { modelId: string; provider: string } | null {
		// Check if there's a plan model configured
		// This would need to be set in settings.json or via environment
		const planModelId = process.env.PI_PLAN_MODEL || "minimax-coding-plan/MiniMax-M2.5";
		const planProvider = process.env.PI_PLAN_PROVIDER || "minimax";
		
		// If env vars are set, consider it configured
		if (process.env.PI_PLAN_MODEL) {
			return { modelId: planModelId, provider: planProvider };
		}
		return null;
	}

	// Helper to update UI status
	function updateStatus(ctx: ExtensionContext): void {
		if (planModeEnabled) {
			ctx.ui.setStatus("plan-mode", "PLAN");
		} else {
			ctx.ui.setStatus("plan-mode", undefined);
		}
	}

	// Switch to plan mode
	async function enterPlanMode(ctx: ExtensionContext): Promise<void> {
		planModeEnabled = true;
		persistState();

		const config = getPlanModelConfig();
		if (config && planModelConfigured) {
			// Try to switch to plan model
			const success = await pi.setModel({ provider: config.provider, id: config.modelId } as any);
			if (success) {
				ctx.ui.notify(`Plan mode: switched to ${config.modelId}`, "info");
			} else {
				ctx.ui.notify(`Plan mode: model switch failed, using tool restriction`, "warning");
			}
		}

		// Always restrict tools
		pi.setActiveTools(["read", "bash"]);
		updateStatus(ctx);
	}

	// Switch to build mode
	async function exitPlanMode(ctx: ExtensionContext): Promise<void> {
		planModeEnabled = false;
		persistState();

		// Note: We can't easily switch back to the original model
		// The user will need to select it manually or we could store the original
		ctx.ui.notify("Build mode: full access restored", "success");

		// Restore full tools
		pi.setActiveTools(["read", "bash", "edit", "write", "grep", "find", "glob"]);
		updateStatus(ctx);
	}

	// Persist state to session
	function persistState(): void {
		pi.appendEntry("plan-mode-state", {
			enabled: planModeEnabled,
		});
	}

	// Register /plan command
	pi.registerCommand("plan", {
		description: "Switch to plan mode (read-only analysis)",
		parameters: Type.Object({}),
		handler: async (args, ctx) => {
			await enterPlanMode(ctx);
		},
	});

	// Register /build command
	pi.registerCommand("build", {
		description: "Switch to build mode (full access)",
		parameters: Type.Object({}),
		handler: async (args, ctx) => {
			await exitPlanMode(ctx);
		},
	});

	// Add system reminder before agent starts
	pi.on("before_agent_start", async (event, ctx) => {
		if (planModeEnabled) {
			return {
				systemPrompt: event.systemPrompt + "\n\n" + PLAN_MODE_SYSTEM_REMINDER,
			};
		} else {
			return {
				systemPrompt: event.systemPrompt + "\n\n" + BUILD_MODE_SYSTEM_REMINDER,
			};
		}
	});

	// Apply tool restrictions when agent starts
	pi.on("agent_start", async (event, ctx) => {
		if (planModeEnabled) {
			pi.setActiveTools(["read", "bash"]);
			updateStatus(ctx);
		}
	});

	// Restore state on session start/resume
	pi.on("session_start", async (event, ctx) => {
		const entries = ctx.sessionManager.getEntries();

		// Find most recent plan-mode-state entry
		let foundState = null;
		for (let i = entries.length - 1; i >= 0; i--) {
			const entry = entries[i];
			if (entry.type === "custom" && entry.customType === "plan-mode-state") {
				foundState = entry.data as { enabled: boolean } | undefined;
				break;
			}
		}

		// Restore state if found
		if (foundState?.enabled !== undefined) {
			planModeEnabled = foundState.enabled;
		}

		// Apply tools if in plan mode
		if (planModeEnabled) {
			pi.setActiveTools(["read", "bash"]);
		}

		updateStatus(ctx);
	});
}
