# AI Agent Configurations

This directory contains configuration for AI coding agents.

## Supported Agents

| Agent | Config Location | Skills Location |
|-------|-----------------|-----------------|
| **PI** | `~/.pi/agent/` | Auto-detected from `~/.agents/skills/` or project |
| **Codex** | `~/.codex/` | `~/.agents/skills/` (USER scope) |
| **OpenCode** | `~/.config/opencode/` | `~/.config/opencode/skills/` → `~/.agents/skills/` |

## Structure

```
home/
├── .agents/                  # 🆕 Neutral shared skills location
│   └── skills/               # All agent skills (Codex USER scope)
│       ├── code-reviewer/
│       ├── interview-sherpa/
│       ├── leetcode-coach/
│       ├── lore-archive/
│       ├── lore-master/
│       ├── ml-recursive-tutor/
│       └── omarchy/
│
├── .pi/
│   └── agent/
│       ├── settings.json     # PI config
│       ├── extensions/       # PI extensions
│       └── auth.json        # API credentials (empty in repo)
│
├── .codex/
│   └── config.toml          # Codex config
│   # Note: Codex reads skills from ~/.agents/skills/ (USER scope)
│   # and keeps system skills in ~/.codex/skills/.system/
│
└── .config/opencode/
    ├── opencode.json        # OpenCode config
    ├── bun.lock
    ├── package.json
    └── skills -> ../.agents/skills   # Symlink to shared skills
```

## Shared Skills

**All skills are stored in `~/.agents/skills/`**, following the [Codex USER scope convention](https://developers.openai.com/codex/skills).

### How Each Agent Accesses Skills

| Agent | Method | Notes |
|-------|--------|-------|
| **Codex** | Native | Reads `~/.agents/skills/` automatically (USER scope) |
| **OpenCode** | Symlink | `~/.config/opencode/skills/` → `~/.agents/skills/` |
| **PI** | Auto-detect | Detects skills from git projects or configure skills path |

### PI Skills Configuration

PI loads skills from `~/.agents/skills/` via the `skills` array in `settings.json`:

```json
{
  "skills": [
    "~/.agents/skills"
  ]
}
```

PI also auto-detects skills from:
- `~/.pi/agent/skills/` (global)
- `~/.agents/skills/` (global) 
- `.pi/skills/` and `.agents/skills/` in project directories
- Git repositories (when running PI from that directory)

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
- `**/*.db` (databases)
- `**/*.sqlite*` (sqlite files)
