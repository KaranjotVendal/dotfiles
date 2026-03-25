# Dotfiles

My dotfiles managed with GNU Stow.

## Structure

```
.dotfiles/
├── home/                      # Configuration files (stowed to ~)
│   ├── .bashrc              # Bash shell config
│   ├── .zshrc               # Zsh shell config
│   ├── .gitconfig           # Git config
│   ├── .pi/                # PI coding agent
│   │   └── agent/
│   └── .config/
│       ├── alacritty/       # Terminal emulator
│       ├── btop/            # System monitor
│       ├── diffnav/         # Git diff viewer
│       ├── fastfetch/       # System info display
│       ├── fish/            # Fish shell
│       ├── gh/              # GitHub CLI
│       ├── gh-dash/         # GitHub dashboard TUI
│       ├── ghostty/         # Terminal emulator
│       ├── git/             # Git config
│       ├── hypr/            # Hyprland window manager
│       ├── kitty/           # Terminal emulator
│       ├── lazygit/         # Git TUI
│       ├── mise/            # Version manager
│       ├── opencode/        # AI coding assistant
│       ├── starship/        # Shell prompt
│       ├── uv/              # Python package manager
│       ├── waybar/          # Wayland status bar
│       ├── zed/             # Code editor
│       └── zellij/         # Terminal multiplexer
├── packages/                  # Brewfiles (optional)
└── README.md
```

## What's Included (51 files)

| Config | Description |
|--------|-------------|
| **hypr** | Hyprland window manager |
| **starship** | Shell prompt |
| **lazygit** | Git TUI |
| **alacritty** | Terminal emulator |
| **ghostty** | Terminal emulator |
| **fastfetch** | System info display |
| **gh** | GitHub CLI |
| **zed** | Code editor |
| **waybar** | Wayland status bar |
| **btop** | System monitor |
| **uv** | Python package manager |
| **gh-dash** | GitHub dashboard TUI |
| **diffnav** | Git diff viewer |
| **opencode** | AI coding assistant |
| **pi** | PI coding agent |
| **git** | Git configuration |
| **bash/zsh** | Shell configuration |

## Setup

### Prerequisites
- GNU Stow: `brew install stow` or `sudo apt install stow`

### Installation

```bash
# Clone
git clone https://github.com/YOUR_USERNAME/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# Stow all configs
stow home

# Or stow specific packages
stow home -t ~ -d .
```

### After making changes

```bash
# Re-stow to update symlinks
stow -R home
```

## Reference

Inspired by [dmmulroy/.dotfiles](https://github.com/dmmulroy/.dotfiles)
