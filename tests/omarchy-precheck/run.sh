#!/usr/bin/env bash
# Test harness for omarchy-precheck and omarchy-safe-update
# No external test deps — uses plain bash assert helpers and temp fixtures.
#
# Model under test (Omarchy 4.x): the installed version comes from the pacman
# package (stubbed here, or injected via OMARCHY_CURRENT_VERSION) and history
# comes from a cached clone of the upstream repo (a local fixture repo here,
# via OMARCHY_UPSTREAM_URL). Nothing touches the real ~/.cache or ~/.config.

set -uo pipefail
# NOTE: no `set -e` — a failing assert must not abort the whole suite; the
# harness tracks pass/fail counts manually and exits at the summary.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/bin/omarchy-precheck"
SAFE_UPDATE_SCRIPT="$REPO_ROOT/bin/omarchy-safe-update"

# ---------- assert helpers ----------
passed_count=0
failed_count=0
current_test=""
current_test_failed=false

begin_test() {
    current_test="$1"
    current_test_failed=false
}

end_test() {
    if $current_test_failed; then
        failed_count=$((failed_count + 1))
    else
        passed_count=$((passed_count + 1))
    fi
}

fail_msg() {
    current_test_failed=true
    echo "  FAIL: $current_test: $1"
    return 1
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$actual" != "$expected" ]]; then
        fail_msg "${msg:+$msg: }expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local needle="$1" haystack="$2" msg="${3:-}"
    if ! [[ "$haystack" == *"$needle"* ]]; then
        fail_msg "${msg:+$msg: }expected to find '$needle' in output"
    fi
}

assert_not_contains() {
    local needle="$1" haystack="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        fail_msg "${msg:+$msg: }expected NOT to find '$needle' in output"
    fi
}

assert_exit_code() {
    local expected="$1" code="$2" msg="${3:-}"
    if [[ "$code" -ne "$expected" ]]; then
        fail_msg "${msg:+$msg: }expected exit code $expected, got $code"
    fi
}

assert_file_exists() {
    local file_path="$1" msg="${2:-}"
    if [[ ! -f "$file_path" ]]; then
        fail_msg "${msg:+$msg: }expected file '$file_path' to exist"
    fi
}

assert_file_missing() {
    local file_path="$1" msg="${2:-}"
    if [[ -e "$file_path" ]]; then
        fail_msg "${msg:+$msg: }expected '$file_path' NOT to exist"
    fi
}

# Assert every ';'-separated needle is present (or absent) in the haystack.
assert_contains_all() {
    local needles="$1" haystack="$2" msg="${3:-}"
    local needle
    local -a needle_list
    IFS=';' read -ra needle_list <<< "$needles"
    for needle in "${needle_list[@]}"; do
        [[ -n "$needle" ]] && assert_contains "$needle" "$haystack" "$msg"
    done
}

assert_contains_none() {
    local needles="$1" haystack="$2" msg="${3:-}"
    local needle
    local -a needle_list
    IFS=';' read -ra needle_list <<< "$needles"
    for needle in "${needle_list[@]}"; do
        [[ -n "$needle" ]] && assert_not_contains "$needle" "$haystack" "$msg"
    done
}

# ---------- sandbox ----------

SANDBOX_DIR=$(mktemp -d)
trap 'rm -rf "$SANDBOX_DIR"' EXIT

make_temp_dir() {
    mktemp -d "$SANDBOX_DIR/tmp.XXXXXX"
}

# Isolate every run from the real system: defaults point into the sandbox, so
# a test that forgets an override can never clone into or scan the real home.
export XDG_CACHE_HOME="$SANDBOX_DIR/default-cache"
export XDG_CONFIG_HOME="$SANDBOX_DIR/default-home/.config"
export HOME_DIR="$SANDBOX_DIR/default-home"
export DOTFILES_DIR="$SANDBOX_DIR/default-home/.dotfiles"
export OMARCHY_UPSTREAM_URL="$SANDBOX_DIR/no-upstream-configured"
unset OMARCHY_SOURCE_REPO OMARCHY_CURRENT_VERSION HC_TERMINAL_ID
mkdir -p "$XDG_CONFIG_HOME"

# Deterministic git identity and config for fixture repos.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@test
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@test

# Stubs on PATH: pacman (installed package + AUR list) and snapper.
STUB_BIN_DIR="$SANDBOX_DIR/stub-bin"
mkdir -p "$STUB_BIN_DIR"
cat > "$STUB_BIN_DIR/pacman" <<'STUBEOF'
#!/usr/bin/env bash
# PACMAN_OMARCHY_PACKAGE: what `pacman -Q omarchy` prints (empty = not installed)
case "$*" in
    "-Qm")
        echo "yay 12.4.2-1"
        echo "paru 2.1.0-1"
        echo "my-aur-pkg 1.0.0-1"
        ;;
    "-Q omarchy")
        if [[ -z "${PACMAN_OMARCHY_PACKAGE:-}" ]]; then
            echo "error: package 'omarchy' was not found" >&2
            exit 1
        fi
        echo "$PACMAN_OMARCHY_PACKAGE"
        ;;
    *) exit 1 ;;
esac
STUBEOF
cat > "$STUB_BIN_DIR/snapper" <<'STUBEOF'
#!/usr/bin/env bash
echo "snapper stub"
STUBEOF
chmod +x "$STUB_BIN_DIR/pacman" "$STUB_BIN_DIR/snapper"
export PATH="$STUB_BIN_DIR:$PATH"
unset PACMAN_OMARCHY_PACKAGE

# ---------- fixture builders ----------

new_git_repo() {
    local repo_dir; repo_dir=$(make_temp_dir)
    git -C "$repo_dir" init --quiet --initial-branch=main
    echo "$repo_dir"
}

# Commit everything in the repo (empty commits allowed) and tag it.
commit_and_tag() {
    local repo_dir="$1" tag="$2" message="${3:-release $2}"
    git -C "$repo_dir" add -A
    git -C "$repo_dir" commit --quiet --allow-empty -m "$message"
    git -C "$repo_dir" tag "$tag"
}

# Upstream repo whose tags are created in the given order, one commit each.
create_tagged_upstream() {
    local repo_dir; repo_dir=$(new_git_repo)
    local tag
    for tag in "$@"; do
        commit_and_tag "$repo_dir" "$tag"
    done
    echo "$repo_dir"
}

# Standard upstream fixture:
#   v1: config/hypr/hyprland.conf, config/waybar/config.jsonc, default/hypr/hyprland.conf
#   v2: waybar config modified, migrations/1778307905.sh added
create_standard_upstream() {
    local repo_dir; repo_dir=$(new_git_repo)
    mkdir -p "$repo_dir/config/hypr" "$repo_dir/config/waybar" "$repo_dir/default/hypr"
    echo 'some_window_rule' > "$repo_dir/config/hypr/hyprland.conf"
    echo 'old_waybar_config' > "$repo_dir/config/waybar/config.jsonc"
    echo 'default_window_rule' > "$repo_dir/default/hypr/hyprland.conf"
    commit_and_tag "$repo_dir" v1 "initial commit"

    mkdir -p "$repo_dir/migrations"
    echo 'new_waybar_config' > "$repo_dir/config/waybar/config.jsonc"
    cat > "$repo_dir/migrations/1778307905.sh" <<'EOF'
echo "fix something"
rm -f ~/.config/hypr/old_hyprland.conf
EOF
    commit_and_tag "$repo_dir" v2 "update waybar config and add migration"
    echo "$repo_dir"
}

# ---------- CLI surface ----------

test_cli_arguments() {
    # args|expected exit|expected output
    while IFS='|' read -r args expected_exit expected_output; do
        begin_test "cli: '$args' exits $expected_exit"
        local out exit_code=0
        # shellcheck disable=SC2086
        out=$("$SCRIPT_UNDER_TEST" $args 2>&1) || exit_code=$?
        assert_exit_code "$expected_exit" "$exit_code"
        assert_contains "$expected_output" "$out"
        end_test
    done <<'EOF'
nonexistent|2|Usage:
--help|2|check
verify|2|requires a snapshot
verify /nonexistent/snapshot|1|snapshot file not found
EOF
}

# ---------- item 1: installed version from the package ----------

test_current_version_detection() {
    local upstream; upstream=$(create_tagged_upstream v4.0.0 v4.0.6 v4.5.0)
    # OMARCHY_CURRENT_VERSION|pacman -Q omarchy output|expected CURRENT line
    while IFS='|' read -r version_override package_line expected_line; do
        begin_test "version: override='$version_override' package='$package_line' -> $expected_line"
        local cache_dir; cache_dir=$(make_temp_dir)
        local out exit_code=0
        out=$(OMARCHY_CURRENT_VERSION="$version_override" PACMAN_OMARCHY_PACKAGE="$package_line" \
            OMARCHY_UPSTREAM_URL="$upstream" XDG_CACHE_HOME="$cache_dir" \
            "$SCRIPT_UNDER_TEST" --print-tags 2>&1) || exit_code=$?
        assert_exit_code 0 "$exit_code"
        assert_eq "$expected_line" "$(head -n 1 <<< "$out")"
        end_test
    done <<'EOF'
v4.0.0||CURRENT=v4.0.0
4.0.0-1||CURRENT=v4.0.0
1:4.0.6-2||CURRENT=v4.0.6
|omarchy 4.0.0-1|CURRENT=v4.0.0
|omarchy 4.5.0-3|CURRENT=v4.5.0
v4.0.6|omarchy 4.0.0-1|CURRENT=v4.0.6
EOF
}

# ---------- item 3: latest = newest stable tag ----------

test_latest_stable_tag() {
    # tags in creation order|expected LATEST line
    while IFS='|' read -r tag_list expected_line; do
        begin_test "latest tag: [$tag_list] -> $expected_line"
        # shellcheck disable=SC2086
        local upstream; upstream=$(create_tagged_upstream $tag_list)
        local cache_dir; cache_dir=$(make_temp_dir)
        local out exit_code=0
        out=$(OMARCHY_CURRENT_VERSION="${tag_list%% *}" OMARCHY_UPSTREAM_URL="$upstream" \
            XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" --print-tags 2>&1) || exit_code=$?
        assert_exit_code 0 "$exit_code"
        # exact line match: a substring check would accept LATEST=v4.5.0-rc3 for v4.5.0
        assert_eq "$expected_line" "$(grep '^LATEST=' <<< "$out")"
        end_test
    done <<'EOF'
v1 v2|LATEST=v2
v4.0.0 v4.0.6 v4.5.0-rc1 v4.5.0-rc2 v4.5.0-rc3 v4.5.0|LATEST=v4.5.0
v4.0.0 v4.5.0 v4.5.0-rc3|LATEST=v4.5.0
v4.0.0 v4.0.6 v4.5.0-rc3|LATEST=v4.0.6
v4.0.0 v4.1.0-beta1 v4.1.0-alpha2|LATEST=v4.0.0
v4.9.0 v4.10.0|LATEST=v4.10.0
EOF
}

# ---------- item 2: cached upstream clone ----------

test_source_clone_cached_and_refreshed() {
    begin_test "source: cloned into XDG_CACHE_HOME on first use, new tags fetched after"
    local upstream; upstream=$(create_tagged_upstream v1 v2)
    local cache_dir; cache_dir=$(make_temp_dir)

    local out
    out=$(OMARCHY_CURRENT_VERSION=v1 OMARCHY_UPSTREAM_URL="$upstream" XDG_CACHE_HOME="$cache_dir" \
        "$SCRIPT_UNDER_TEST" --print-tags 2>&1)
    assert_contains "LATEST=v2" "$out" "first run"
    assert_file_exists "$cache_dir/omarchy-precheck/source/HEAD" "bare clone at default location"

    commit_and_tag "$upstream" v3
    out=$(OMARCHY_CURRENT_VERSION=v1 OMARCHY_UPSTREAM_URL="$upstream" XDG_CACHE_HOME="$cache_dir" \
        "$SCRIPT_UNDER_TEST" --print-tags 2>&1)
    assert_contains "LATEST=v3" "$out" "second run should fetch the new tag"
    end_test

    begin_test "source: OMARCHY_SOURCE_REPO overrides the clone location"
    local source_dir; source_dir="$(make_temp_dir)/custom-source"
    cache_dir=$(make_temp_dir)
    out=$(OMARCHY_CURRENT_VERSION=v1 OMARCHY_UPSTREAM_URL="$upstream" XDG_CACHE_HOME="$cache_dir" \
        OMARCHY_SOURCE_REPO="$source_dir" "$SCRIPT_UNDER_TEST" --print-tags 2>&1)
    assert_contains "LATEST=v3" "$out"
    assert_file_exists "$source_dir/HEAD" "clone at override location"
    assert_file_missing "$cache_dir/omarchy-precheck/source" "no clone at default location"
    end_test
}

# ---------- item 4: offline vs error ----------

test_offline_versus_error() {
    local upstream; upstream=$(create_tagged_upstream v1 v2)
    # scenario|expected exit|expected message|message that must NOT appear
    while IFS='|' read -r scenario expected_exit expected_message forbidden_message; do
        begin_test "failure: $scenario -> exit $expected_exit"
        local cache_dir; cache_dir=$(make_temp_dir)
        local upstream_url="$upstream" current_version="v1"
        case "$scenario" in
            unreachable-host) upstream_url="https://0.0.0.0/invalid/repo.git" ;;
            connection-refused) upstream_url="http://127.0.0.1:9/omarchy.git" ;;
            unresolvable-host) upstream_url="https://omarchy-precheck.invalid/repo.git" ;;
            offline-after-clone)
                OMARCHY_CURRENT_VERSION=v1 OMARCHY_UPSTREAM_URL="$upstream" XDG_CACHE_HOME="$cache_dir" \
                    "$SCRIPT_UNDER_TEST" --print-tags >/dev/null 2>&1
                upstream_url="https://0.0.0.0/invalid/repo.git"
                ;;
            upstream-not-a-repo) upstream_url="$SANDBOX_DIR/does-not-exist" ;;
            source-cache-corrupt)
                mkdir -p "$cache_dir/omarchy-precheck/source"
                echo 'junk' > "$cache_dir/omarchy-precheck/source/junk"
                ;;
            version-not-upstream) current_version="v9" ;;
            package-not-installed) current_version="" ;;
        esac

        local out exit_code=0
        out=$(OMARCHY_CURRENT_VERSION="$current_version" \
            OMARCHY_UPSTREAM_URL="$upstream_url" XDG_CACHE_HOME="$cache_dir" \
            "$SCRIPT_UNDER_TEST" report 2>&1) || exit_code=$?
        assert_exit_code "$expected_exit" "$exit_code" "report"
        assert_contains "$expected_message" "$out" "report"
        assert_not_contains "$forbidden_message" "$out" "report"
        assert_file_missing "$cache_dir/omarchy-precheck/v2.md" "no report written"

        local check_out check_exit=0
        check_out=$(OMARCHY_CURRENT_VERSION="$current_version" \
            OMARCHY_UPSTREAM_URL="$upstream_url" XDG_CACHE_HOME="$cache_dir" \
            "$SCRIPT_UNDER_TEST" check 2>&1) || check_exit=$?
        assert_exit_code 1 "$check_exit" "check stays silent"
        assert_eq "" "$check_out" "check output"
        end_test
    done <<'EOF'
unreachable-host|3|Offline: could not reach upstream|Error:
connection-refused|3|Offline: could not reach upstream|Error:
unresolvable-host|3|Offline: could not reach upstream|Error:
offline-after-clone|3|Offline: could not reach upstream|Error:
upstream-not-a-repo|1|Error: could not update the upstream source clone|Offline
source-cache-corrupt|1|is not a git repository|Offline
version-not-upstream|1|Error: installed omarchy version v9 has no matching tag upstream|Offline
package-not-installed|1|Error: could not determine installed omarchy version|Offline
EOF
}

test_print_tags_offline() {
    begin_test "print-tags: offline prints LATEST=unknown and exits 3"
    local cache_dir; cache_dir=$(make_temp_dir)
    local out exit_code=0
    out=$(OMARCHY_CURRENT_VERSION=v1 OMARCHY_UPSTREAM_URL="https://0.0.0.0/invalid/repo.git" \
        XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" --print-tags 2>&1) || exit_code=$?
    assert_exit_code 3 "$exit_code"
    assert_contains "CURRENT=v1" "$out"
    assert_contains "LATEST=unknown" "$out"
    end_test
}

# ---------- report: full scenario ----------

# One report run against a fake home that exercises every section, then a
# table of expectations against it.
test_standard_report() {
    local upstream; upstream=$(create_standard_upstream)
    local cache_dir; cache_dir=$(make_temp_dir)
    local fake_home; fake_home=$(make_temp_dir)
    local dotfiles_dir="$fake_home/.dotfiles"

    # Customised waybar config (upstream changes it -> at risk)
    mkdir -p "$fake_home/.config/waybar" "$fake_home/.config/hypr"
    echo 'my_custom_waybar_config' > "$fake_home/.config/waybar/config.jsonc"
    # Diverged hypr config (upstream does not change it -> divergence manifest)
    echo 'my_custom_rule' > "$fake_home/.config/hypr/hyprland.conf"
    # Hooks: one active, one sample
    mkdir -p "$fake_home/.config/omarchy/hooks"
    printf '#!/bin/bash\necho "theme changed to $1"\n' > "$fake_home/.config/omarchy/hooks/theme-set"
    chmod +x "$fake_home/.config/omarchy/hooks/theme-set"
    printf '#!/bin/bash\n# Sample hook\n' > "$fake_home/.config/omarchy/hooks/post-update.sample"
    # Symlinks: stowed, external, broken, depth-1 in home; plus a real dir
    mkdir -p "$dotfiles_dir/home/.config" "$fake_home/.config/real-dir"
    echo 'stowed content' > "$dotfiles_dir/home/.config/stowed-file"
    ln -s "$dotfiles_dir/home/.config/stowed-file" "$fake_home/.config/stowed-file"
    ln -s "/some/external/path" "$fake_home/.config/external-link"
    ln -s "/nonexistent" "$fake_home/.config/broken-link"
    ln -s "$dotfiles_dir/home/.config/stowed-file" "$fake_home/top-level-link"

    local stdout_file="$cache_dir/stdout"
    local exit_code=0
    OMARCHY_CURRENT_VERSION=v1 OMARCHY_UPSTREAM_URL="$upstream" XDG_CACHE_HOME="$cache_dir" \
        XDG_CONFIG_HOME="$fake_home/.config" DOTFILES_DIR="$dotfiles_dir" HOME_DIR="$fake_home" \
        "$SCRIPT_UNDER_TEST" report > "$stdout_file" 2>&1 || exit_code=$?

    local report_file="$cache_dir/omarchy-precheck/v2.md"
    local report_content="" stdout_content
    [[ -f "$report_file" ]] && report_content=$(cat "$report_file")
    stdout_content=$(cat "$stdout_file")

    begin_test "report: written to cache, printed to stdout, exit 0"
    assert_exit_code 0 "$exit_code"
    assert_file_exists "$report_file"
    assert_eq "$report_content" "$stdout_content" "stdout and cache file should match"
    end_test

    # contains|not_contains <TAB-free needle> <description>
    while IFS='|' read -r expectation needle description; do
        begin_test "report: $description"
        if [[ "$expectation" == "contains" ]]; then
            assert_contains "$needle" "$report_content"
        else
            assert_not_contains "$needle" "$report_content"
        fi
        end_test
    done <<'EOF'
contains|# Omarchy Update Report: v1 → v2|header parsed by omarchy-safe-update
contains|## Changelog|changelog section
contains|update waybar config|changelog lists v2 commit subjects
contains|## Changed Files|changed files section
contains|config/waybar/config.jsonc|changed files list modified waybar config
contains|## Pending Migrations|pending migrations section
contains|### migrations/1778307905.sh|migration filename shown
contains|fix something|migration content shown in full
contains|## Config Defaults Changed|config defaults section
contains|old_waybar_config|config diff shows old value
contains|new_waybar_config|config diff shows new value
contains|## Customizations At Risk|customizations at risk section
contains|`waybar/config.jsonc` — your version differs|customised waybar config flagged
contains|## Divergence Manifest|divergence manifest section
contains|`hypr/hyprland.conf` — differs from default|diverged hypr config listed
contains|## Custom Hooks|custom hooks section
contains|`theme-set`|active hook listed
not_contains|post-update.sample|sample hooks not listed
contains|## AUR / Foreign Packages|AUR section
contains|my-aur-pkg|AUR packages listed
contains|## System Basics|system basics section
contains|Current omarchy tag: `v1`|current tag in basics
contains|Snapper: available|snapper detected
contains|## Symlink Integrity Map|symlink integrity map section
contains|(stow-managed)|stowed symlink marked stow-managed
contains|`external-link` → `/some/external/path`|non-dotfiles symlink listed unmarked
contains|top-level-link|depth-1 home symlink listed
not_contains|real-dir|real directories not listed
EOF

    begin_test "report: .symlinks snapshot written with tab-separated entries"
    local snapshot_file="$cache_dir/omarchy-precheck/v2.symlinks"
    assert_file_exists "$snapshot_file"
    local snapshot_content=""
    [[ -f "$snapshot_file" ]] && snapshot_content=$(cat "$snapshot_file")
    assert_contains "stowed-file"$'\t'"$dotfiles_dir/home/.config/stowed-file"$'\t' "$snapshot_content"
    assert_contains "broken-link"$'\t'"/nonexistent"$'\t' "$snapshot_content"
    end_test
}

test_report_customization_matching_default_not_flagged() {
    begin_test "report: config matching the current default is not at risk"
    local upstream; upstream=$(create_standard_upstream)
    local cache_dir; cache_dir=$(make_temp_dir)
    local fake_home; fake_home=$(make_temp_dir)
    mkdir -p "$fake_home/.config/waybar"
    echo 'old_waybar_config' > "$fake_home/.config/waybar/config.jsonc"

    local out
    out=$(OMARCHY_CURRENT_VERSION=v1 OMARCHY_UPSTREAM_URL="$upstream" XDG_CACHE_HOME="$cache_dir" \
        XDG_CONFIG_HOME="$fake_home/.config" HOME_DIR="$fake_home" "$SCRIPT_UNDER_TEST" report 2>&1)
    assert_contains "## Changelog" "$out"
    assert_not_contains "## Customizations At Risk" "$out"
    end_test
}

test_report_and_check_by_installed_version() {
    local upstream; upstream=$(create_standard_upstream)
    # installed version|subcommand|expected exit|expected output (empty = no output)
    while IFS='|' read -r installed_version subcommand expected_exit expected_output; do
        begin_test "$subcommand: installed $installed_version -> exit $expected_exit"
        local cache_dir; cache_dir=$(make_temp_dir)
        local out exit_code=0
        out=$(OMARCHY_CURRENT_VERSION="$installed_version" OMARCHY_UPSTREAM_URL="$upstream" \
            XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" "$subcommand" 2>&1) || exit_code=$?
        assert_exit_code "$expected_exit" "$exit_code"
        if [[ -z "$expected_output" ]]; then
            assert_eq "" "$out"
        else
            assert_contains "$expected_output" "$out"
        fi
        if [[ "$installed_version" == "v2" ]]; then
            assert_file_missing "$cache_dir/omarchy-precheck/v2.md" "no report when up to date"
        fi
        end_test
    done <<'EOF'
v2|report|0|Omarchy is up to date (v2)
1-1|report|0|# Omarchy Update Report: v1 → v2
v1|check|0|Omarchy update available (v1 → v2)
2-1|check|1|
EOF
}

test_report_no_null_byte_warnings() {
    begin_test "report: binary config files cause no null-byte warnings"
    local upstream; upstream=$(new_git_repo)
    mkdir -p "$upstream/config/hypr"
    printf 'text\x00binary\x00content' > "$upstream/config/hypr/binary.conf"
    echo 'text config' > "$upstream/config/hypr/text.conf"
    commit_and_tag "$upstream" v1
    echo 'v2 content' > "$upstream/config/hypr/text.conf"
    commit_and_tag "$upstream" v2

    local cache_dir; cache_dir=$(make_temp_dir)
    local fake_home; fake_home=$(make_temp_dir)
    mkdir -p "$fake_home/.config/hypr"
    printf 'different\x00binary' > "$fake_home/.config/hypr/binary.conf"
    echo 'custom text' > "$fake_home/.config/hypr/text.conf"

    local out
    out=$(OMARCHY_CURRENT_VERSION=v1 OMARCHY_UPSTREAM_URL="$upstream" XDG_CACHE_HOME="$cache_dir" \
        XDG_CONFIG_HOME="$fake_home/.config" HOME_DIR="$fake_home" "$SCRIPT_UNDER_TEST" report 2>&1)
    assert_not_contains "null byte" "$out"
    assert_contains "binary.conf" "$out" "binary file still in divergence manifest"
    end_test
}

test_migration_impact_analysis() {
    local upstream; upstream=$(new_git_repo)
    echo 'dummy' > "$upstream/config"
    commit_and_tag "$upstream" v1
    mkdir -p "$upstream/migrations"
    # Migration 1: variable-indirected commands, includes a duplicate sed line
    cat > "$upstream/migrations/1778307905.sh" << 'MIGEOF'
#!/bin/bash
tmux_config="$HOME/.config/tmux/tmux.conf"
alacritty_config="$HOME/.config/alacritty/alacritty.toml"
hypr_rule="$HOME/.config/hypr/myrule.conf"
sed -i 's/old/new/' "$tmux_config"
sed -i 's/foo/bar/' "$tmux_config"
rm -f "$alacritty_config"
echo 'new rule' > "$hypr_rule"
MIGEOF
    # Migration 2: different write command targeting a different path
    cat > "$upstream/migrations/1780000000.sh" << 'MIGEOF'
#!/bin/bash
nvim_config="$HOME/.config/nvim/init.lua"
sed -i 's/old/ newer/' "$nvim_config"
MIGEOF
    commit_and_tag "$upstream" v2 "add impact migration"

    local cache_dir; cache_dir=$(make_temp_dir)
    local fake_home; fake_home=$(make_temp_dir)
    local dotfiles_dir="$fake_home/.dotfiles/home"
    # ~/.config/tmux/ -> DIR symlink into dotfiles (dir-level stow)
    mkdir -p "$dotfiles_dir/.config/tmux" "$fake_home/.config"
    echo 'set -g prefix C-a' > "$dotfiles_dir/.config/tmux/tmux.conf"
    ln -s "$dotfiles_dir/.config/tmux" "$fake_home/.config/tmux"
    # ~/.config/alacritty/alacritty.toml -> FILE symlink (file-level stow)
    mkdir -p "$dotfiles_dir/.config/alacritty" "$fake_home/.config/alacritty"
    echo 'colors = "default"' > "$dotfiles_dir/.config/alacritty/alacritty.toml"
    ln -s "$dotfiles_dir/.config/alacritty/alacritty.toml" "$fake_home/.config/alacritty/alacritty.toml"
    # ~/.config/hypr/ and ~/.config/nvim/ -> real dirs (not stowed)
    mkdir -p "$fake_home/.config/hypr" "$fake_home/.config/nvim"
    echo 'my rule' > "$fake_home/.config/hypr/myrule.conf"
    echo 'vim.g.mapleader = " "' > "$fake_home/.config/nvim/init.lua"

    local out
    out=$(OMARCHY_CURRENT_VERSION=v1 OMARCHY_UPSTREAM_URL="$upstream" XDG_CACHE_HOME="$cache_dir" \
        XDG_CONFIG_HOME="$fake_home/.config" DOTFILES_DIR="$fake_home/.dotfiles" HOME_DIR="$fake_home" \
        "$SCRIPT_UNDER_TEST" report 2>&1)

    # needle|description
    while IFS='|' read -r needle description; do
        begin_test "migration-impact: $description"
        assert_contains "$needle" "$out"
        end_test
    done <<'EOF'
## Migration Impact Analysis|section present
### migrations/1778307905.sh|migration 1 has its own header
### migrations/1780000000.sh|migration 2 has its own header
tmux/tmux.conf` → writes land in|sed -i inside a dir symlink classified
link safe (stow-managed)|dir symlink into dotfiles is safe and stow-managed
alacritty/alacritty.toml` → SEVERS link|rm on a file symlink severs it
direct write (real file)|echo > on a real file is a direct write
nvim/init.lua|migration 2 target listed
EOF

    begin_test "migration-impact: no duplicate lines in the section"
    local impact_section impact_duplicates
    impact_section=$(sed -n '/^## Migration Impact Analysis/,/^## Symlink/p' <<< "$out" | head -n -1)
    impact_duplicates=$(sort <<< "$impact_section" | uniq -d | grep -v '^$' || true)
    assert_eq "" "$impact_duplicates" "duplicate lines"
    end_test
}

# ---------- verify subcommand ----------

test_verify_severed() {
    begin_test "verify: symlink replaced by real file reported as SEVERED"
    local fake_home; fake_home=$(make_temp_dir)
    local snapshot_file; snapshot_file="$(make_temp_dir)/snapshot.symlinks"
    ln -s "/some/target" "$fake_home/my-link"
    printf '%s\t%s\t%s\n' "my-link" "/some/target" "" > "$snapshot_file"
    rm "$fake_home/my-link"
    echo 'real file content' > "$fake_home/my-link"

    local out exit_code=0
    out=$(HOME_DIR="$fake_home" "$SCRIPT_UNDER_TEST" verify "$snapshot_file" 2>&1) || exit_code=$?
    assert_exit_code 1 "$exit_code"
    assert_contains "SEVERED: my-link" "$out"
    end_test
}

test_verify_retargeted() {
    begin_test "verify: symlink retargeted to a different path reported"
    local fake_home; fake_home=$(make_temp_dir)
    local snapshot_file; snapshot_file="$(make_temp_dir)/snapshot.symlinks"
    mkdir -p "$fake_home/.config"
    ln -s "/old/target" "$fake_home/.config/my-link"
    printf '%s\t%s\t%s\n' "my-link" "/old/target" "" > "$snapshot_file"
    rm "$fake_home/.config/my-link"
    ln -s "/new/target" "$fake_home/.config/my-link"

    local out exit_code=0
    out=$(HOME_DIR="$fake_home" XDG_CONFIG_HOME="$fake_home/.config" \
        "$SCRIPT_UNDER_TEST" verify "$snapshot_file" 2>&1) || exit_code=$?
    assert_exit_code 1 "$exit_code"
    assert_contains "RETARGETED: my-link" "$out"
    end_test
}

test_verify_retarget_omarchy_theme_excluded() {
    begin_test "verify: omarchy/current/ retarget NOT reported (legitimate theme switch)"
    local fake_home; fake_home=$(make_temp_dir)
    local snapshot_file; snapshot_file="$(make_temp_dir)/snapshot.symlinks"
    local themes_dir="$fake_home/.local/share/omarchy/themes"
    mkdir -p "$fake_home/.config/omarchy/current" "$themes_dir/old" "$themes_dir/new"
    touch "$themes_dir/old/file" "$themes_dir/new/file"
    ln -s "$themes_dir/old" "$fake_home/.config/omarchy/current/current-theme"
    printf '%s\t%s\t%s\n' "omarchy/current/current-theme" "$themes_dir/old" "" > "$snapshot_file"
    rm "$fake_home/.config/omarchy/current/current-theme"
    ln -s "$themes_dir/new" "$fake_home/.config/omarchy/current/current-theme"

    local out exit_code=0
    out=$(HOME_DIR="$fake_home" XDG_CONFIG_HOME="$fake_home/.config" \
        "$SCRIPT_UNDER_TEST" verify "$snapshot_file" 2>&1) || exit_code=$?
    assert_exit_code 0 "$exit_code"
    assert_not_contains "RETARGETED" "$out"
    end_test
}

test_verify_target_content_changed() {
    begin_test "verify: target file content change detected as TARGET-CHANGED"
    local fake_home; fake_home=$(make_temp_dir)
    local snapshot_file; snapshot_file="$(make_temp_dir)/snapshot.symlinks"
    mkdir -p "$fake_home/.local/share" "$fake_home/.config"
    echo 'original content' > "$fake_home/.local/share/target-file"
    local original_checksum
    original_checksum=$(sha256sum "$fake_home/.local/share/target-file" | awk '{print $1}')
    ln -s "$fake_home/.local/share/target-file" "$fake_home/.config/my-link"
    printf '%s\t%s\t%s\n' "my-link" "$fake_home/.local/share/target-file" "$original_checksum" > "$snapshot_file"
    echo 'modified content' > "$fake_home/.local/share/target-file"

    local out exit_code=0
    out=$(HOME_DIR="$fake_home" XDG_CONFIG_HOME="$fake_home/.config" \
        "$SCRIPT_UNDER_TEST" verify "$snapshot_file" 2>&1) || exit_code=$?
    assert_exit_code 1 "$exit_code"
    assert_contains "TARGET-CHANGED: my-link" "$out"
    end_test
}

test_verify_clean() {
    begin_test "verify: clean re-scan reports no issues"
    local fake_home; fake_home=$(make_temp_dir)
    local snapshot_file; snapshot_file="$(make_temp_dir)/snapshot.symlinks"
    mkdir -p "$fake_home/.config" "$fake_home/.local/share"
    echo 'content' > "$fake_home/.local/share/target-file"
    local checksum
    checksum=$(sha256sum "$fake_home/.local/share/target-file" | awk '{print $1}')
    ln -s "$fake_home/.local/share/target-file" "$fake_home/.config/my-link"
    printf '%s\t%s\t%s\n' "my-link" "$fake_home/.local/share/target-file" "$checksum" > "$snapshot_file"

    local out exit_code=0
    out=$(HOME_DIR="$fake_home" XDG_CONFIG_HOME="$fake_home/.config" \
        "$SCRIPT_UNDER_TEST" verify "$snapshot_file" 2>&1) || exit_code=$?
    assert_exit_code 0 "$exit_code"
    assert_contains "no issues" "$out"
    end_test
}

# ---------- omarchy-safe-update ----------

# Stubs: omarchy-precheck (behaviour from PRECHECK_STUB_MODE), pi, hc (logs its
# argv to HC_STUB_LOG, exit code from HC_STUB_EXIT), and a fake
# $OMARCHY_PATH/bin/omarchy-update so the real update can never run.
create_safe_update_stubs() {
    local stub_root="$1"
    mkdir -p "$stub_root/bin" "$stub_root/omarchy/bin"
    cat > "$stub_root/bin/omarchy-precheck" <<'STUBEOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "verify" ]]; then
    echo "VERIFY_RAN $2"
    exit 0
fi
case "$PRECHECK_STUB_MODE" in
    report)
        echo "warning: command substitution: ignored null byte in input" >&2
        echo "# Omarchy Update Report: v1 → v2"
        echo ""
        echo "## Changelog"
        echo "abc1234 update"
        exit 0
        ;;
    up-to-date) echo "Omarchy is up to date (v2)"; exit 0 ;;
    offline) echo "Offline: could not reach upstream https://example.invalid" >&2; exit 3 ;;
    error) echo "Error: installed omarchy version v9 has no matching tag upstream" >&2; exit 1 ;;
esac
STUBEOF
    cat > "$stub_root/bin/pi" <<'STUBEOF'
#!/usr/bin/env bash
echo "PI_RAN $*"
STUBEOF
    cat > "$stub_root/bin/hc" <<'STUBEOF'
#!/usr/bin/env bash
echo "HC_RAN $*" >> "$HC_STUB_LOG"
[[ "${HC_STUB_EXIT:-0}" -eq 0 ]] || echo "error: name omarchy-review is taken"
exit "${HC_STUB_EXIT:-0}"
STUBEOF
    cat > "$stub_root/omarchy/bin/omarchy-update" <<'STUBEOF'
#!/usr/bin/env bash
echo "REAL_UPDATE_RAN_WITH: $*"
exit "${UPDATE_STUB_EXIT:-0}"
STUBEOF
    chmod +x "$stub_root"/bin/* "$stub_root/omarchy/bin/omarchy-update"
}

test_safe_update_flows() {
    # scenario|precheck mode|answer|HC_TERMINAL_ID|hc exit|must contain (;-separated)|must not contain
    while IFS='|' read -r scenario precheck_mode answer terminal_id hc_exit required_needles forbidden_needles; do
        begin_test "safe-update: $scenario"
        local stub_root; stub_root=$(make_temp_dir)
        create_safe_update_stubs "$stub_root"
        local cache_dir="$stub_root/cache"
        mkdir -p "$cache_dir/omarchy-precheck"
        echo 'fake report' > "$cache_dir/omarchy-precheck/v2.md"
        local hc_log="$stub_root/hc.log"
        touch "$hc_log"

        local out
        out=$(echo "$answer" | PRECHECK_STUB_MODE="$precheck_mode" HC_TERMINAL_ID="$terminal_id" \
            HC_STUB_EXIT="$hc_exit" HC_STUB_LOG="$hc_log" OMARCHY_PATH="$stub_root/omarchy" \
            XDG_CACHE_HOME="$cache_dir" PATH="$stub_root/bin:$PATH" \
            bash "$SAFE_UPDATE_SCRIPT" 2>&1)
        out+=$'\n'"$(cat "$hc_log")"
        required_needles="${required_needles//@REPORT@/$cache_dir/omarchy-precheck/v2.md}"
        assert_contains_all "$required_needles" "$out"
        assert_contains_none "$forbidden_needles" "$out"
        end_test
    done <<'EOF'
report reviewed inline without hc|report|n||0|Starting AI review...;PI_RAN @@REPORT@;Update aborted|HC_RAN;REAL_UPDATE_RAN
report reviewed in hc terminal|report|n|t7|0|HC_RAN run --bg --no-parent --name omarchy-review --cwd;-- pi @@REPORT@ An Omarchy update is pending;hc attach omarchy-review;Update aborted|PI_RAN;REAL_UPDATE_RAN
hc failure falls back to inline review|report|n|t7|1|Could not start the review in an hc terminal;name omarchy-review is taken;PI_RAN @@REPORT@|REAL_UPDATE_RAN
report approved runs the update|report|y||0|PI_RAN;REAL_UPDATE_RAN_WITH|
up to date runs the update directly|up-to-date|n||0|No new omarchy version;REAL_UPDATE_RAN_WITH|PI_RAN;Warning: Precheck
offline is labelled offline|offline|n||0|could not reach the omarchy upstream (offline?);Update aborted|failed with an error;REAL_UPDATE_RAN
error is not labelled offline|error|n||0|Precheck failed with an error (exit 1,;Update aborted|offline;REAL_UPDATE_RAN
error can still proceed on y|error|y||0|Precheck failed with an error;REAL_UPDATE_RAN_WITH|offline
EOF
}

test_safe_update_verifies_after_update() {
    # scenario|update exit code
    while IFS='|' read -r scenario update_exit; do
        begin_test "safe-update: symlinks verified after $scenario"
        local stub_root; stub_root=$(make_temp_dir)
        create_safe_update_stubs "$stub_root"
        local cache_dir="$stub_root/cache"
        mkdir -p "$cache_dir/omarchy-precheck"
        echo 'fake report' > "$cache_dir/omarchy-precheck/v2.md"
        local snapshot_file="$cache_dir/omarchy-precheck/v2.symlinks"
        touch "$snapshot_file"

        local out exit_code=0
        out=$(echo y | PRECHECK_STUB_MODE=report UPDATE_STUB_EXIT="$update_exit" HC_TERMINAL_ID= \
            OMARCHY_PATH="$stub_root/omarchy" XDG_CACHE_HOME="$cache_dir" PATH="$stub_root/bin:$PATH" \
            bash "$SAFE_UPDATE_SCRIPT" 2>&1) || exit_code=$?
        assert_contains "REAL_UPDATE_RAN_WITH" "$out"
        assert_contains "VERIFY_RAN $snapshot_file" "$out"
        assert_exit_code "$update_exit" "$exit_code" "safe-update returns the update's exit code"
        end_test
    done <<'EOF'
a successful update|0
a failed update|7
EOF
}

test_safe_update_source() {
    local source_content
    source_content=$(cat "$SAFE_UPDATE_SCRIPT")
    # must contain|needle|description
    while IFS='|' read -r expectation needle description; do
        begin_test "safe-update source: $description"
        if [[ "$expectation" == "contains" ]]; then
            assert_contains "$needle" "$source_content"
        else
            assert_not_contains "$needle" "$source_content"
        fi
        end_test
    done <<'EOF'
contains|GROUND TRUTH|seed prompt cites Migration Impact Analysis as ground truth
contains|replicate|seed prompt requires empirical replication
contains|evidence|seed prompt requires evidence for claims
not_contains|herdr|herdr TUI path removed
EOF
}

# ---------- main ----------

echo "=== omarchy-precheck test suite ==="
echo ""

if [[ ! -x "$SCRIPT_UNDER_TEST" ]]; then
    echo "SKIP: $SCRIPT_UNDER_TEST not executable"
    exit 0
fi

test_cli_arguments
test_current_version_detection
test_latest_stable_tag
test_source_clone_cached_and_refreshed
test_offline_versus_error
test_print_tags_offline
test_standard_report
test_report_customization_matching_default_not_flagged
test_report_and_check_by_installed_version
test_report_no_null_byte_warnings
test_migration_impact_analysis
test_verify_severed
test_verify_retargeted
test_verify_retarget_omarchy_theme_excluded
test_verify_target_content_changed
test_verify_clean
test_safe_update_flows
test_safe_update_verifies_after_update
test_safe_update_source

echo ""
echo "$passed_count passed, $failed_count failed"
[[ "$failed_count" -eq 0 ]]
