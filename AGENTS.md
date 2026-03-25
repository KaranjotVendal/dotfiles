# AI Agent Configurations

This directory contains configuration for AI coding agents.

## Supported Agents

| Agent | Config Location | Description |
|-------|-----------------|-------------|
| **PI** | `~/.pi/agent/` | Primary coding agent (minimax provider) |
| **Codex** | `~/.codex/` | OpenAI Codex agent |
| **OpenCode** | `~/.config/opencode/` | OpenCode AI assistant |

## Structure

```
home/
├── .pi/agent/
│   ├── settings.json       # Provider/model preferences
│   ├── extensions/         # Custom PI extensions
│   │   ├── plan-mode.ts
│   │   ├── readiness-report/
│   │   └── web-fetch.ts
│   └── auth.json          # API credentials (empty in repo)
│
├── .codex/
│   └── config.toml        # Codex model & project settings
│
└── .config/opencode/
    ├── opencode.json      # Main config
    └── skills/            # Shared skills (7 skills)
        ├── code-reviewer/
        ├── interview-sherpa/
        ├── leetcode-coach/
        ├── lore-archive/
        ├── lore-master/
        ├── ml-recursive-tutor/
        └── omarchy/
```

## Shared Skills

**Skills are stored in `~/.config/opencode/skills/`** and are the only shared component across agents.

On your system, PI symlinks to these skills:
```bash
~/.pi/agent/skills -> ~/.config/opencode/skills
```

This allows all agents to use the same skills without duplication.

## Agent Configurations

### PI
```json
{
  "defaultProvider": "minimax",
  "defaultModel": "MiniMax-M2.5",
  "hideThinkingBlock": true,
  "theme": "dark"
}
```

### Codex
```toml
model = "gpt-5.4"
personality = "pragmatic"

[projects."/path/to/project"]
trust_level = "trusted"
```

### OpenCode
```json
{
  "theme": "system"
}
```

## Environment Variables

API keys are NOT stored in dotfiles. Set these in your shell:

```bash
# ~/.bashrc or ~/.zshrc
export OPENAI_API_KEY="..."
export ANTHROPIC_API_KEY="..."
export MINIMAX_API_KEY="..."
```

## Excluded from Git

The following are excluded via `.gitignore`:
- `**/auth.json` (API credentials)
- `**/.env` (environment variables)
- `**/history.*` (chat history)
- `**/cache/` (cached data)
- `**/sessions/` (session data)
