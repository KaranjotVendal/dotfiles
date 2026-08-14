---
name: morcli
description: Use when you need to know which Moraine session belongs to a herdr stream/workspace, to see what a stream (or all streams) has been doing, or to search across all session history (BM25 keyword) and open any session/turn/event by handle — from the terminal, for the herdr parallel-stream / orchestration workflow. Prefer this over guessing by "most recently active session" or scraping panes for content.
---

# morcli

A thin CLI over the local Moraine trace stack and herdr: it resolves a herdr workspace
(or a plain directory) to its current Moraine session by matching cwd, then shows recent turns.

## Install

Check whether it's already installed first; only install if missing.

```bash
command -v morcli || uv tool install --editable .   # run install from the morcli repo
```

Always invoke the installed `morcli` binary. Do not use `uv run` (that's for dev tasks only —
tests, lint, type check).

## Prerequisites

- The Moraine stack must be running (`moraine up`). `morcli` queries ClickHouse at
  `http://127.0.0.1:8123` and spawns `moraine run mcp` for turn reconstruction.
- herdr is needed only to resolve workspace labels, numbers, and ids to a cwd. If you peek by
  directory path with `--cwd`, herdr is not required.

## Usage

Run `morcli --help`, or `morcli <command> --help` for the full reference.

Common operations:

- `morcli peek <selector> [--turns N] [--cwd] [--list] [--json]` — resolve a selector to a cwd,
  find the most-recent session there, and show its last N turns (default from
  `config.default_turns`, which ships at 3). The selector is a herdr workspace id, number, label, or
  unique label-substring — or a filesystem path when `--cwd` is passed.
- `morcli streams [--active] [--json]` — table of herdr workspaces joined to their current
  Moraine session. Columns: workspace, worktree, session, last_seen, status, last_prompt.
  `--active` shows only live streams (working or blocked).
- `morcli search <query> [--within <selector>] [--type T]... [--limit N] [--json]` — BM25 keyword
  search across all Moraine sessions. Global by default; `--within <selector>` scopes to one
  stream's current session (same selector as `peek`). `--type` is repeatable (event-type filter);
  `--limit` defaults to 10, clamped to 50. Each hit row carries an openable `event:` handle.
- `morcli open <handle> [--json]` — resolve a `session:` / `turn:` / `event:` handle to its
  content. event shows the full text; turn shows its event handles; session shows its turn handles.
  This is the drill target for a `search` hit.
- `morcli config [show | set <key> <value> | path]` — view and edit the config file.

Add `--json` to `peek` / `streams` / `search` / `open` for machine-readable output.

```bash
morcli peek stream-alpha              # by herdr label
morcli peek 15 --turns 5              # by workspace number, 5 turns
morcli peek /path/to/worktree --cwd   # by directory path (no herdr needed)
morcli peek stream-beta --list        # list all candidate sessions at that cwd
morcli peek 15 --json                 # machine-readable output

morcli streams                        # all workspaces
morcli streams --active               # only live (working or blocked) streams

morcli search "clickhouse deadline"                   # global BM25 keyword search
morcli search "handoff" --within w9 --limit 5         # scope to one stream's session
morcli search "cargo test" --type tool_response        # filter by event type
morcli open event:<handle>            # read a hit in full (drill from search)
morcli open session:<handle>          # session metadata + its turn handles

morcli config show
morcli config set default_turns 5
morcli config path
```

## When to use it

- To read a specific stream's recent activity **deterministically** — `morcli peek <selector>` —
  instead of guessing which Moraine session is which by "most recently active".
- To get a live overview of all streams at once — `morcli streams` (or `--active` for only the live
  ones).
- To find something across **all** session history — `morcli search "<query>"` (global) or
  `--within <selector>` to scope — then `morcli open <handle>` to read the full hit and drill into
  its parent turn/session. This is exact-text retrieval, not a pane scrape or a memory guess.
- Use morcli for stream **content / history**. Use `herdr pane read` only for live TUI state (e.g.
  whether a stream is blocked at a prompt right now) — the transcript trails the live pane by a
  flush.

## Gotchas

- A single worktree/cwd can host several sessions over time — `peek` shows the newest and warns;
  `--list` shows all candidates.
- The `peek` output's `source` line is `mcp` (native turn reconstruction) or `clickhouse`
  (automatic fallback when `moraine run mcp` is unavailable) — both are valid.
- **Selector resolution:** exact id/number/label first, else a unique label-substring. An ambiguous
  substring or an unknown selector exits non-zero with a listing to disambiguate.
- A selector that begins with `-` must be passed after `--` (e.g. `morcli peek -- -x`).
- `--cwd` takes a filesystem path and skips herdr — use it when herdr isn't running, or when the
  message tells you to.
- **Latency:** `peek` takes about 2-3s (dominated by `moraine run mcp` startup); `streams` about
  1s across ~24 workspaces.
- **Exit codes:** non-zero on unreachable ClickHouse ("is `moraine up` running?"), herdr absent
  (suggests `--cwd`), no session found, or an unresolvable selector.
- **Debugging:** `MORCLI_LOG_LEVEL=DEBUG` traces to stderr and `~/.morcli/logs/morcli.log`.
- **Handles are opaque** base64 — copy them from a `search` row or an `open` result; do not
  construct them. A stale or malformed handle exits non-zero with the MCP's message.
- **Search is BM25 keyword, not semantic** — use keyword queries (not natural-language questions)
  and work broad-to-narrow: a broad term first, then add words or `--within` / `--type` to narrow.
- **`search` / `open` are MCP-only** — no ClickHouse fallback, so they need `moraine up` (unlike
  `peek`). `search` is global unless `--within` scopes it to one stream's current session.

## Data storage

- `~/.config/morcli/config.json` — `clickhouse_url`, `default_turns`, `moraine_bin` (no secrets,
  no keychain). `MORCLI_CONFIG` overrides this path.
- `~/.morcli/logs/morcli.log` — full DEBUG log.
