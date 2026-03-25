# AI Agent Configurations

This directory contains unified configuration for AI coding agents.

## Structure

```
home/
├── .pi/agent/           # PI coding agent
│   ├── settings.json    # Provider/model preferences
│   └── extensions/      # Custom extensions
├── .codex/              # OpenAI Codex
│   └── config.toml      # Codex configuration
├── .config/opencode/    # OpenCode AI
│   ├── opencode.json    # Main config
│   └── skills/          # Shared skills (symlinked from .pi)
└── .config/agents/      # 🆕 Future: unified agent configs
```

## Agent-Specific Notes

### PI
- Main config: `.pi/agent/settings.json`
- Extensions: `.pi/agent/extensions/`
- Skills symlinked to OpenCode skills directory

### Codex
- Config location: `~/.codex/config.toml`
- Data/cache: `~/.codex/` (excluded from git)

### OpenCode
- Config: `~/.config/opencode/opencode.json`
- Skills: `~/.config/opencode/skills/`
- Large data in `~/.local/share/opencode/` (excluded)

## Shared Skills

Skills are stored in `~/.config/opencode/skills/` and symlinked from PI:
- `~/.pi/agent/skills -> ~/.config/opencode/skills`

This allows skills to be shared across agents.

## Environment Variables

Agents may expect these in your shell:
```bash
# API keys (in ~/.bashrc or ~/.zshrc, not in git)
export OPENAI_API_KEY="..."
export ANTHROPIC_API_KEY="..."
```
