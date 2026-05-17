# Dotfiles

My dotfiles managed with GNU Stow.

## Structure

```
.dotfiles/
├── home/                      # Configuration files (stowed to ~)
│   ├── .gitconfig           # Git config
│   ├── .codex/              # OpenAI Codex agent
│   ├── .pi/                 # PI coding agent
│   │   └── agent/
│   │       ├── settings.json
│   │       └── extensions/
│   └── .config/
│       ├── alacritty/       # Terminal emulator
│       ├── diffnav/         # Git diff viewer
│       ├── ghostty/         # Terminal emulator
│       ├── git/             # Git configuration
│       ├── gh/              # GitHub CLI
│       ├── gh-dash/         # GitHub dashboard TUI
│       ├── lazygit/         # Git TUI
│       ├── nvim/            # Neovim editor
│       ├── opencode/        # OpenCode AI assistant
│       ├── starship.toml    # Shell prompt
│       ├── tmux/            # Terminal multiplexer
│       ├── uv/              # Python package manager
│       ├── zed/             # Zed editor
│       └── zellij/          # Terminal multiplexer
├── packages/                  # Package manifests (optional)
├── AGENTS.md                  # AI agent documentation
└── README.md
```

## What's Included

| Category | Tools |
|----------|-------|
| **Terminals** | alacritty, ghostty |
| **Editors** | nvim, zed |
| **Multiplexers** | tmux, zellij |
| **Git Tools** | git, gh, gh-dash, lazygit |
| **AI Agents** | pi, codex, opencode |
| **Dev Tools** | uv, diffnav, starship |

## Setup

### Prerequisites
- GNU Stow: `brew install stow` or `sudo pacman -S stow`

### Installation

```bash
# Clone
git clone https://github.com/YOUR_USERNAME/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# Stow all configs
stow home
```

### After making changes

```bash
# Re-stow to update symlinks
cd ~/.dotfiles && stow -R home
```

## AI Agents

See [AGENTS.md](./AGENTS.md) for AI agent configuration details.

## Reference

Inspired by [dmmulroy/.dotfiles](https://github.com/dmmulroy/.dotfiles)
