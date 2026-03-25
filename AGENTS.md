# AI Agent Configurations

This directory contains configuration for AI coding agents.

## Supported Agents

| Agent | Config Location | Skills Location |
|-------|-----------------|-----------------|
| **PI** | `~/.pi/agent/` | `~/.pi/agent/skills/` → `~/.agents/skills/` |
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
├── .pi/agent/
│   ├── settings.json         # PI config
│   ├── extensions/           # PI extensions
│   ├── auth.json            # API credentials (empty in repo)
│   └── skills -> ../../.agents/skills   # Symlink to shared skills
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

This location is:
- ✅ **Codex native**: Automatically detected as USER scope
- ✅ **Shared**: PI and OpenCode symlink here
- ✅ **Neutral**: Not owned by any single agent

### Symlinks After Stow

```bash
# PI skills symlink
~/.pi/agent/skills -> ~/.agents/skills

# OpenCode skills symlink  
~/.config/opencode/skills -> ~/.agents/skills

# Codex: NO SYMLINK NEEDED
# Reads directly from ~/.agents/skills/ (USER scope)
```

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
