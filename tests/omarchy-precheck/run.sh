#!/usr/bin/env bash
# Test harness for omarchy-precheck
# No external test deps — uses plain bash assert helpers and temp fixtures.

set -uo pipefail
# NOTE: no `set -e` — a failing assert must not abort the whole suite; the
# harness tracks pass/fail counts manually and exits at the summary.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/bin/omarchy-precheck"

# ---------- assert helpers ----------
pass=0
fail=0
current_test=""

pass() {
    pass=$((pass + 1))
}

fail_msg() {
    fail=$((fail + 1))
    echo "  FAIL: $current_test: $1"
    return 1
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$actual" != "$expected" ]]; then
        local detail="expected '$expected', got '$actual'"
        fail_msg "${msg:+$msg: }$detail"
        return 1
    fi
}

assert_contains() {
    local needle="$1" haystack="$2" msg="${3:-}"
    if ! [[ "$haystack" == *"$needle"* ]]; then
        fail_msg "${msg:+$msg: }expected to find '$needle' in output"
        return 1
    fi
}

assert_not_contains() {
    local needle="$1" haystack="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        fail_msg "${msg:+$msg: }expected NOT to find '$needle' in output"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1" code="$2" msg="${3:-}"
    if [[ "$code" -ne "$expected" ]]; then
        fail_msg "${msg:+$msg: }expected exit code $expected, got $code"
        return 1
    fi
}

assert_file_exists() {
    local f="$1" msg="${2:-}"
    if [[ ! -f "$f" ]]; then
        fail_msg "${msg:+$msg: }expected file '$f' to exist"
        return 1
    fi
}

# ---------- fixture builders ----------

# Create a fake omarchy git repo at $1 with:
#   init commit: config/hypr/hyprland.conf, config/waybar/config.jsonc, default/hypr/hyprland.conf
#   tag v1
#   second commit: modify config/waybar/config.jsonc, add migrations/1778307905.sh
#   tag v2
#   bare origin remote (created, then added as remote to the working repo)
create_fake_omarchy_repo() {
    local dest="$1"
    mkdir -p "$dest"

    # Build fixture in a tmp dir, then clone --bare to create origin
    local work_dir; work_dir=$(mktemp -d)
    # clean up on exit
    echo "$work_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true

    git -C "$work_dir" init --initial-branch=main >/dev/null 2>&1
    git -C "$work_dir" config user.email "test@test"
    git -C "$work_dir" config user.name "Test"

    mkdir -p "$work_dir/config/hypr" "$work_dir/config/waybar" "$work_dir/default/hypr" "$work_dir/migrations"

    echo 'some_window_rule' > "$work_dir/config/hypr/hyprland.conf"
    echo 'old_waybar_config' > "$work_dir/config/waybar/config.jsonc"
    echo 'default_window_rule' > "$work_dir/default/hypr/hyprland.conf"

    git -C "$work_dir" add -A
    git -C "$work_dir" commit -m "initial commit" >/dev/null 2>&1

    git -C "$work_dir" tag v1

    # Second commit: modify waybar config, add a migration
    echo 'new_waybar_config' > "$work_dir/config/waybar/config.jsonc"
    cat > "$work_dir/migrations/1778307905.sh" <<'EOF'
echo "fix something"
rm -f ~/.config/hypr/old_hyprland.conf
EOF
    git -C "$work_dir" add -A
    git -C "$work_dir" commit -m "update waybar config and add migration" >/dev/null 2>&1

    git -C "$work_dir" tag v2

    # Create bare origin and push
    local bare_dir; bare_dir=$(mktemp -d)
    echo "$bare_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    git init --bare "$bare_dir/origin.git" >/dev/null 2>&1
    git -C "$work_dir" remote add origin "$bare_dir/origin.git"
    git -C "$work_dir" push origin --all >/dev/null 2>&1
    git -C "$work_dir" push origin --tags >/dev/null 2>&1

    # Set up the "local" repo to simulate a pending update: checked out at v1,
    # aware only of tag v1. The remote has both v1 and v2.
    git -C "$dest" init --initial-branch=main >/dev/null 2>&1
    git -C "$dest" config user.email "test@test"
    git -C "$dest" config user.name "Test"
    git -C "$dest" remote add origin "$bare_dir/origin.git"
    git -C "$dest" pull origin main >/dev/null 2>&1
    git -C "$dest" fetch --tags origin >/dev/null 2>&1
    git -C "$dest" checkout v1 >/dev/null 2>&1
    git -C "$dest" tag -d v2 >/dev/null 2>&1

    # Return the bare dir path so tests can reference it
    echo "$bare_dir/origin.git"
}

# Create a fake HOME at $1 with a diverging .config file and optional symlinks
create_fake_home() {
    local dest="$1"
    # diverging config — different from v1 default
    mkdir -p "$dest/.config/hypr"
    echo 'my_custom_rule' > "$dest/.config/hypr/hyprland.conf"
    # identical config (matches v1 default)
    echo 'default_window_rule' > "$dest/.config/hypr/identical_hack.conf"
}

# ---------- setup / teardown ----------

cleanup_all() {
    local cleanup_file="${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$"
    if [[ -f "$cleanup_file" ]]; then
        while IFS= read -r dir; do
            [[ -n "$dir" && -d "$dir" ]] && rm -rf "$dir" 2>/dev/null || true
        done < "$cleanup_file"
        rm -f "$cleanup_file"
    fi
}
trap cleanup_all EXIT

# ---------- tests ----------

test_skeleton_no_args() {
    current_test="skeleton: no args runs report subcommand (default)"

    local out exit_code=0
    out=$(OMARCHY_PATH="/nonexistent" "$SCRIPT_UNDER_TEST" 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "no args should exit 1 (missing omarchy repo)"
    assert_contains "Error:" "$out" "should report error about missing omarchy repo"
    pass
}

test_skeleton_bad_subcommand() {
    current_test="skeleton: bad subcommand exits non-zero"

    local out exit_code=0
    out=$("$SCRIPT_UNDER_TEST" nonexistent 2>&1) || exit_code=$?

    assert_exit_code 2 "$exit_code" "bad subcommand should exit 2"
    assert_contains "Usage:" "$out" "should print usage"
    pass
}

test_skeleton_report_subcommand() {
    current_test="skeleton: 'report' subcommand accepted (missing repo handled)"

    local out exit_code=0
    out=$(OMARCHY_PATH="/nonexistent" "$SCRIPT_UNDER_TEST" report 2>&1) || exit_code=$?

    assert_not_contains "Usage:" "$out" "should not print usage"
    pass
}

test_skeleton_verify_subcommand() {
    current_test="skeleton: 'verify' subcommand accepted (missing snapshot handled)"

    local out exit_code=0
    out=$("$SCRIPT_UNDER_TEST" verify "/nonexistent/snapshot" 2>&1) || exit_code=$?

    assert_contains "Error:" "$out" "should report snapshot not found"
    pass
}

# ---------- Task 2: Tag detection ----------

test_tag_current_is_v1() {
    current_test="tag: current tag detected as v1 before fetch"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    local out exit_code=0
    out=$(OMARCHY_PATH="$omarchy_dir" "$SCRIPT_UNDER_TEST" --print-tags 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "--print-tags should exit 0"
    assert_contains "CURRENT=v1" "$out" "should detect current tag v1"
    pass
}

test_tag_latest_is_v2() {
    current_test="tag: latest remote tag detected as v2"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    local out exit_code=0
    out=$(OMARCHY_PATH="$omarchy_dir" "$SCRIPT_UNDER_TEST" --print-tags 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "--print-tags should exit 0"
    assert_contains "LATEST=v2" "$out" "should detect latest tag v2"
    pass
}

test_tag_fetch_failure() {
    current_test="tag: fetch failure prints offline warning and exits non-zero"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null
    # Make the origin unreachable
    git -C "$omarchy_dir" remote set-url origin "https://0.0.0.0/invalid/repo.git"

    local out exit_code=0
    out=$(OMARCHY_PATH="$omarchy_dir" "$SCRIPT_UNDER_TEST" report 2>&1) || exit_code=$?

    assert_contains "offline" "$out" "should mention offline/unreachable"
    assert_exit_code 1 "$exit_code" "should exit 1 on fetch failure"
    pass
}

# Regression: current tag must reflect HEAD, not the latest local tag
# (the rev-list trick is blind when tags have been fetched without merging)
test_tag_current_is_HEAD_even_if_tags_ahead() {
    current_test="tag: current tag reflects HEAD even when local tags are ahead"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true

    # Linear history on same branch: v1 -> v2. HEAD at v1, tags include v1 and v2.
    git -C "$omarchy_dir" init --initial-branch=main >/dev/null 2>&1
    git -C "$omarchy_dir" config user.email "test@test"
    git -C "$omarchy_dir" config user.name "Test"
    echo 'v1 content' > "$omarchy_dir/file"
    git -C "$omarchy_dir" add -A
    git -C "$omarchy_dir" commit -m "v1" >/dev/null 2>&1
    git -C "$omarchy_dir" tag v1
    echo 'v2 content' > "$omarchy_dir/file"
    git -C "$omarchy_dir" add -A
    git -C "$omarchy_dir" commit -m "v2" >/dev/null 2>&1
    git -C "$omarchy_dir" tag v2
    # HEAD at v1 — both tags exist locally but HEAD is behind
    git -C "$omarchy_dir" checkout v1 >/dev/null 2>&1

    # Directly verify get_current_tag returns the tag at HEAD, not the latest tag
    local out exit_code=0
    out=$(OMARCHY_PATH="$omarchy_dir" "$SCRIPT_UNDER_TEST" --print-tags 2>&1 | head -1) || exit_code=$?

    assert_eq "CURRENT=v1" "$out" "current tag should be v1 (HEAD at v1)"
    pass
}

test_tag_describe_not_rev_list() {
    current_test="tag: get_current_tag uses describe HEAD, not rev-list trick"

    # Verify the script source doesn't contain the rev-list trick
    if grep -q 'rev-list.*--tags.*--max-count' "$SCRIPT_UNDER_TEST"; then
        fail_msg "get_current_tag should not use rev-list --tags --max-count (git describe --tags HEAD instead)"
    else
        pass
    fi
}

# ---------- Task 3: Report — changelog and changed files ----------

test_report_file_exists() {
    current_test="report: report file created at XDG_CACHE_HOME/omarchy-precheck/<tag>.md"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    assert_file_exists "$cache_dir/omarchy-precheck/v2.md" "report file should exist at v2.md"
    pass
}

test_report_has_changelog() {
    current_test="report: report file contains Changelog section"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "## Changelog" "$content" "should have a Changelog section"
    assert_contains "update waybar config" "$content" "should include v2 commit subjects"
    pass
}

test_report_has_changed_files() {
    current_test="report: report file contains Changed Files section"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "## Changed Files" "$content" "should have a Changed Files section"
    assert_contains "config/waybar/config.jsonc" "$content" "should show modified waybar config"
    assert_contains "migrations" "$content" "should show added migration file"
    pass
}

# ---------- Task 4: Report — pending migrations ----------

test_report_has_migrations_section() {
    current_test="report: pending migrations section present"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "## Pending Migrations" "$content" "should have a Pending Migrations section"
    pass
}

test_report_migration_shows_full_content() {
    current_test="report: migration content shown in full"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "fix something" "$content" "should contain migration body text"
    assert_contains "1778307905.sh" "$content" "should reference the migration filename"
    pass
}

# ---------- Task 5: Report — config defaults changed ----------

test_report_has_config_defaults_section() {
    current_test="report: config defaults changed section present"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "## Config Defaults Changed" "$content" "should have a Config Defaults Changed section"
    pass
}

test_report_config_defaults_shows_diff() {
    current_test="report: config defaults diff shows waybar changes"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "config/waybar/config.jsonc" "$content" "should show waybar config in the diff"
    assert_contains "new_waybar_config" "$content" "should show the new config value"
    assert_contains "old_waybar_config" "$content" "should show the old config value"
    pass
}

# ---------- Task 6: Report — customizations at risk ----------

test_report_customization_at_risk_flagged() {
    current_test="customizations: diverging file flagged as at risk"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    # User has a customized waybar config that differs from v1 default
    mkdir -p "$fake_home/.config/waybar"
    echo 'my_custom_waybar_config' > "$fake_home/.config/waybar/config.jsonc"

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" XDG_CONFIG_HOME="$fake_home/.config" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "## Customizations At Risk" "$content" "should have a Customizations At Risk section"
    assert_contains "waybar/config.jsonc" "$content" "should flag waybar config"
    assert_contains "your version differs" "$content" "should note that version differs from default"
    pass
}

test_report_customization_not_flagged_if_matches_default() {
    current_test="customizations: matching file NOT flagged"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    # User's config matches v1 default exactly — should NOT be flagged
    mkdir -p "$fake_home/.config/waybar"
    echo 'old_waybar_config' > "$fake_home/.config/waybar/config.jsonc"

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" XDG_CONFIG_HOME="$fake_home/.config" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_not_contains "## Customizations At Risk" "$content" "should NOT have a Customizations At Risk section when nothing is at risk"
    pass
}

# ---------- Task 7: Report — system profile (divergence manifest) ----------

test_report_divergence_manifest_shows_diverged_files() {
    current_test="divergence: user-modified file that upstream did NOT change appears in manifest"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null
    create_fake_home "$fake_home"

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" XDG_CONFIG_HOME="$fake_home/.config" DOTFILES_DIR="$fake_home/.dotfiles" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "## Divergence Manifest" "$content" "should have a Divergence Manifest section"
    assert_contains "hypr/hyprland.conf" "$content" "should list the diverged config file"
    assert_contains "differs from default" "$content" "should note the file differs from defaults"
    pass
}

# ---------- Task 8: Report — system profile (hooks, AUR, basics) ----------

test_report_hooks_listed() {
    current_test="system-profile: custom hooks are listed"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    # Create a hooks dir with one active hook and one sample
    mkdir -p "$fake_home/.config/omarchy/hooks"
    printf '#!/bin/bash\necho "theme changed to $1"\n' > "$fake_home/.config/omarchy/hooks/theme-set"
    chmod +x "$fake_home/.config/omarchy/hooks/theme-set"
    printf '#!/bin/bash\n# Sample hook\n' > "$fake_home/.config/omarchy/hooks/post-update.sample"

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" XDG_CONFIG_HOME="$fake_home/.config" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "Custom Hooks" "$content" "should have a Custom Hooks section"
    assert_contains "theme-set" "$content" "should list the active theme-set hook"
    assert_not_contains "post-update.sample" "$content" "should NOT list .sample files"
    pass
}

test_report_aur_packages_listed() {
    current_test="system-profile: AUR/foreign packages listed"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    # Stub pacman to return fake AUR packages
    local stub_dir; stub_dir=$(mktemp -d)
    echo "$stub_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    cat > "$stub_dir/pacman" << 'STUBEOF'
#!/usr/bin/env bash
if [[ "$*" == "-Qm" ]]; then
  echo "yay 12.4.2-1"
  echo "paru 2.1.0-1"
  echo "my-aur-pkg 1.0.0-1"
fi
STUBEOF
    chmod +x "$stub_dir/pacman"

    local extra_path="$stub_dir"

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" PATH="$extra_path:$PATH" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "AUR / Foreign Packages" "$content" "should have AUR packages section"
    assert_contains "yay" "$content" "should list yay"
    assert_contains "my-aur-pkg" "$content" "should list custom AUR package"
    pass
}

test_report_basics_section() {
    current_test="system-profile: basics section shows kernel, tag, snapper"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    # Stub snapper to be available
    local stub_dir; stub_dir=$(mktemp -d)
    echo "$stub_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    cat > "$stub_dir/snapper" << 'STUBEOF'
#!/usr/bin/env bash
echo "snapper stub"
STUBEOF
    chmod +x "$stub_dir/snapper"

    local extra_path="$stub_dir"

    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" XDG_CONFIG_HOME="$fake_home/.config" PATH="$extra_path:$PATH" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "System Basics" "$content" "should have System Basics section"
    assert_contains "v1" "$content" "should show current omarchy tag"
    assert_contains "Snapper" "$content" "should mention Snapper"
    assert_contains "available" "$content" "should indicate snapper is available"
    pass
}

# ---------- Task 9: Symlink integrity map ----------

test_symlink_map_stowed_symlinks_listed() {
    current_test="symlinks: stowed symlink appears in map"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    # Create dotfiles repo structure
    local dotfiles_dir="$fake_home/.dotfiles"
    mkdir -p "$dotfiles_dir/home/.config"
    echo 'stowed content' > "$dotfiles_dir/home/.config/stowed-file"

    # Create ~/.config with a stowed symlink
    mkdir -p "$fake_home/.config"
    ln -s "$dotfiles_dir/home/.config/stowed-file" "$fake_home/.config/stowed-file"
    # Non-dotfiles symlink
    ln -s "/some/external/path" "$fake_home/.config/external-link"
    # Real directory (not a symlink)
    mkdir -p "$fake_home/.config/real-dir"
    # Depth-1 symlink in ~/
    ln -s "$dotfiles_dir/home/.config/stowed-file" "$fake_home/top-level-link"

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" XDG_CONFIG_HOME="$fake_home/.config" DOTFILES_DIR="$fake_home/.dotfiles" HOME_DIR="$fake_home" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "## Symlink Integrity Map" "$content" "should have Symlink Integrity Map section"
    assert_contains "stowed-file" "$content" "should list stowed symlink"
    assert_contains "external-link" "$content" "should list non-dotfiles symlink"
    assert_not_contains "real-dir" "$content" "should NOT list real directories"
    assert_contains "top-level-link" "$content" "should list depth-1 symlinks in HOME"
    pass
}

test_symlink_map_stow_managed_marked() {
    current_test="symlinks: stow-managed symlinks marked in report"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    local dotfiles_dir="$fake_home/.dotfiles"
    mkdir -p "$dotfiles_dir/home/.config"
    touch "$dotfiles_dir/home/.config/stowed-file"

    mkdir -p "$fake_home/.config"
    ln -s "$dotfiles_dir/home/.config/stowed-file" "$fake_home/.config/stowed-file"
    ln -s "/external" "$fake_home/.config/external-link"

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" XDG_CONFIG_HOME="$fake_home/.config" DOTFILES_DIR="$fake_home/.dotfiles" HOME_DIR="$fake_home" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local content
    content=$(cat "$cache_dir/omarchy-precheck/v2.md") || true

    assert_contains "stow-managed" "$content" "stowed symlink should be marked as stow-managed"
    pass
}

test_symlink_snapshot_file_created() {
    current_test="symlinks: .symlinks snapshot file created with correct format"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    local dotfiles_dir="$fake_home/.dotfiles"
    mkdir -p "$dotfiles_dir/home/.config"
    echo 'content' > "$dotfiles_dir/home/.config/real-target"

    mkdir -p "$fake_home/.config"
    ln -s "$dotfiles_dir/home/.config/real-target" "$fake_home/.config/stowed-link"
    ln -s "/nonexistent" "$fake_home/.config/broken-link"

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" XDG_CONFIG_HOME="$fake_home/.config" DOTFILES_DIR="$fake_home/.dotfiles" HOME_DIR="$fake_home" "$SCRIPT_UNDER_TEST" report >/dev/null 2>&1 || true

    local symlinks_file="$cache_dir/omarchy-precheck/v2.symlinks"
    assert_file_exists "$symlinks_file" ".symlinks snapshot should exist"

    local sym_content
    sym_content=$(cat "$symlinks_file") || true

    # Should be tab-separated with 3 columns
    assert_contains "stowed-link" "$sym_content" "symlinks file should list stowed-link"
    assert_contains "broken-link" "$sym_content" "symlinks file should list broken-link"
    # Check tab-separated format (3 fields per line)
    while IFS=$'\t' read -r link target checksum rest; do
        if [[ -n "$link" && "$link" != "" ]]; then
            assert_contains "$link" "$link" "link present"
        fi
    done <<< "$sym_content"
    pass
}

# ---------- Task 10: verify subcommand ----------

# Helper: create a snapshot file at $1 with lines of tab-separated link, target, checksum
make_snapshot() {
    local file="$1"
    shift
    printf '%s\n' "$@" > "$file"
}

test_verify_severed() {
    current_test="verify: symlink replaced by real file reported as SEVERED"

    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local snap_file="$cache_dir/snapshot.symlinks"

    # Fake home: was a symlink to /some/target
    ln -s "/some/target" "$fake_home/my-link"
    # Create snapshot recording the symlink
    printf '%s\t%s\t%s\n' "my-link" "/some/target" "" > "$snap_file"
    # Mutate: replace symlink with real file
    rm "$fake_home/my-link"
    echo 'real file content' > "$fake_home/my-link"

    local out exit_code=0
    out=$(HOME_DIR="$fake_home" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" verify "$snap_file" 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "verify should exit 1 with issues"
    assert_contains "SEVERED" "$out" "should report SEVERED"
    assert_contains "my-link" "$out" "should name the severed link"
    pass
}

test_verify_retargeted() {
    current_test="verify: symlink retargeted to different path reported"

    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local snap_file="$cache_dir/snapshot.symlinks"

    mkdir -p "$fake_home/.config"
    ln -s "/old/target" "$fake_home/.config/my-link"
    # Snapshot path is relative to XDG_CONFIG_HOME (the scan dir)
    printf '%s\t%s\t%s\n' "my-link" "/old/target" "" > "$snap_file"
    # Mutate: retarget
    rm "$fake_home/.config/my-link"
    ln -s "/new/target" "$fake_home/.config/my-link"

    local out exit_code=0
    out=$(HOME_DIR="$fake_home" XDG_CONFIG_HOME="$fake_home/.config" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" verify "$snap_file" 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "verify should exit 1 with issues"
    assert_contains "RETARGETED" "$out" "should report RETARGETED"
    assert_contains "my-link" "$out" "should name the retargeted link"
    pass
}

test_verify_retarget_omarchy_theme_excluded() {
    current_test="verify: omarchy/current/ retarget NOT reported (legitimate theme switch)"

    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local snap_file="$cache_dir/snapshot.symlinks"

    # Omarchy theme retarget: link under omarchy/current/
    mkdir -p "$fake_home/.config/omarchy/current"
    # Target file must exist for the link to be valid
    mkdir -p "$fake_home/.local/share/omarchy/themes/old"
    mkdir -p "$fake_home/.local/share/omarchy/themes/new"
    touch "$fake_home/.local/share/omarchy/themes/old/file"
    touch "$fake_home/.local/share/omarchy/themes/new/file"
    ln -s "$fake_home/.local/share/omarchy/themes/old" "$fake_home/.config/omarchy/current/current-theme"
    # Snapshot path relative to XDG_CONFIG_HOME (scan dir)
    printf '%s\t%s\t%s\n' "omarchy/current/current-theme" "$fake_home/.local/share/omarchy/themes/old" "" > "$snap_file"
    # Mutate: legitimate theme switch
    rm "$fake_home/.config/omarchy/current/current-theme"
    ln -s "$fake_home/.local/share/omarchy/themes/new" "$fake_home/.config/omarchy/current/current-theme"

    local out exit_code=0
    out=$(HOME_DIR="$fake_home" XDG_CONFIG_HOME="$fake_home/.config" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" verify "$snap_file" 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "verify should exit 0 (omarchy theme retarget excluded)"
    assert_not_contains "RETARGETED" "$out" "should NOT report RETARGETED for omarchy theme"
    pass
}

test_verify_target_content_changed() {
    current_test="verify: target file content change detected as TARGET-CHANGED"

    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local snap_file="$cache_dir/snapshot.symlinks"

    # Create a target file
    mkdir -p "$fake_home/.local/share"
    echo 'original content' > "$fake_home/.local/share/target-file"
    local orig_checksum
    orig_checksum=$(sha256sum "$fake_home/.local/share/target-file" | awk '{print $1}')

    # Create symlink pointing to it
    mkdir -p "$fake_home/.config"
    ln -s "$fake_home/.local/share/target-file" "$fake_home/.config/my-link"
    # Snapshot path relative to XDG_CONFIG_HOME
    printf '%s\t%s\t%s\n' "my-link" "$fake_home/.local/share/target-file" "$orig_checksum" > "$snap_file"

    # Mutate: change the target file content
    echo 'modified content' > "$fake_home/.local/share/target-file"

    local out exit_code=0
    out=$(HOME_DIR="$fake_home" XDG_CONFIG_HOME="$fake_home/.config" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" verify "$snap_file" 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "verify should exit 1 with content changes"
    assert_contains "TARGET-CHANGED" "$out" "should report TARGET-CHANGED"
    assert_contains "my-link" "$out" "should name the link"
    pass
}

test_verify_clean() {
    current_test="verify: clean re-scan reports no issues"

    local fake_home; fake_home=$(mktemp -d)
    echo "$fake_home" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local snap_file="$cache_dir/snapshot.symlinks"

    mkdir -p "$fake_home/.config"
    mkdir -p "$fake_home/.local/share"
    echo 'content' > "$fake_home/.local/share/target-file"
    local chk
    chk=$(sha256sum "$fake_home/.local/share/target-file" | awk '{print $1}')
    ln -s "$fake_home/.local/share/target-file" "$fake_home/.config/my-link"
    # Snapshot path relative to XDG_CONFIG_HOME
    printf '%s\t%s\t%s\n' "my-link" "$fake_home/.local/share/target-file" "$chk" > "$snap_file"

    local out exit_code=0
    out=$(HOME_DIR="$fake_home" XDG_CONFIG_HOME="$fake_home/.config" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" verify "$snap_file" 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "verify should exit 0 on clean state"
    assert_contains "no issues" "$out" "should report no issues"
    pass
}

# ---------- Task 11: Report flow polish ----------

test_report_up_to_date() {
    current_test="report: up-to-date tag exits cleanly with message"

    # Fixture with only one tag — no update available
    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true

    local work_dir; work_dir=$(mktemp -d)
    echo "$work_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local bare_dir; bare_dir=$(mktemp -d)
    echo "$bare_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true

    git -C "$work_dir" init --initial-branch=main >/dev/null 2>&1
    git -C "$work_dir" config user.email "test@test"
    git -C "$work_dir" config user.name "Test"
    echo 'content' > "$work_dir/file"
    git -C "$work_dir" add -A
    git -C "$work_dir" commit -m "init" >/dev/null 2>&1
    git -C "$work_dir" tag v1
    git init --bare "$bare_dir/origin.git" >/dev/null 2>&1
    git -C "$work_dir" remote add origin "$bare_dir/origin.git"
    git -C "$work_dir" push origin --all >/dev/null 2>&1
    git -C "$work_dir" push origin --tags >/dev/null 2>&1

    git -C "$omarchy_dir" init --initial-branch=main >/dev/null 2>&1
    git -C "$omarchy_dir" config user.email "test@test"
    git -C "$omarchy_dir" config user.name "Test"
    git -C "$omarchy_dir" remote add origin "$bare_dir/origin.git"
    git -C "$omarchy_dir" pull origin main >/dev/null 2>&1
    git -C "$omarchy_dir" fetch --tags origin >/dev/null 2>&1
    git -C "$omarchy_dir" checkout v1 >/dev/null 2>&1

    local out exit_code=0
    out=$(OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" report 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "up-to-date should exit 0"
    assert_contains "up to date" "$out" "should print up-to-date message"
    # No report file should be created
    if [[ -f "$cache_dir/omarchy-precheck/v1.md" ]]; then
        fail_msg "report file should NOT be created when up to date"
    else
        pass
    fi
}

test_report_printed_to_stdout() {
    current_test="report: report printed to stdout"

    local omarchy_dir; omarchy_dir=$(mktemp -d)
    echo "$omarchy_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    local cache_dir; cache_dir=$(mktemp -d)
    echo "$cache_dir" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true
    create_fake_omarchy_repo "$omarchy_dir" >/dev/null

    local stdout_file; stdout_file=$(mktemp)
    echo "$stdout_file" >> "${TMPDIR:-/tmp}/omarchy-precheck-test-cleanup.$$" 2>/dev/null || true

    OMARCHY_PATH="$omarchy_dir" XDG_CACHE_HOME="$cache_dir" "$SCRIPT_UNDER_TEST" report > "$stdout_file" 2>&1 || true

    # Both stdout and cache file should have the report
    local report_file="$cache_dir/omarchy-precheck/v2.md"
    assert_file_exists "$report_file" "report file should exist in cache"

    local stdout_content
    stdout_content=$(cat "$stdout_file") || true
    local file_content
    file_content=$(cat "$report_file") || true

    assert_contains "## Changelog" "$stdout_content" "stdout should contain the report"
    assert_eq "$file_content" "$stdout_content" "stdout and cache file content should match"
    pass
}

# ---------- main ----------

echo "=== omarchy-precheck test suite ==="
echo ""

# Check script exists and is executable
if [[ ! -x "$SCRIPT_UNDER_TEST" ]]; then
    echo "SKIP: $SCRIPT_UNDER_TEST not executable yet (expected before Task 1 step 4)"
    echo "       This is normal if only the test harness was written."
    echo ""
    echo "0 passed, 0 failed (4 skipped)"
    exit 0
fi

test_skeleton_no_args
test_skeleton_bad_subcommand
test_skeleton_report_subcommand
test_skeleton_verify_subcommand

test_tag_current_is_v1
test_tag_latest_is_v2
test_tag_fetch_failure
test_tag_current_is_HEAD_even_if_tags_ahead
test_tag_describe_not_rev_list

test_report_file_exists
test_report_has_changelog
test_report_has_changed_files

test_report_has_migrations_section
test_report_migration_shows_full_content

test_report_has_config_defaults_section
test_report_config_defaults_shows_diff

test_report_customization_at_risk_flagged
test_report_customization_not_flagged_if_matches_default

test_report_divergence_manifest_shows_diverged_files

test_report_hooks_listed
test_report_aur_packages_listed
test_report_basics_section

test_symlink_map_stowed_symlinks_listed
test_symlink_map_stow_managed_marked
test_symlink_snapshot_file_created

test_verify_severed
test_verify_retargeted
test_verify_retarget_omarchy_theme_excluded
test_verify_target_content_changed
test_verify_clean

test_report_up_to_date
test_report_printed_to_stdout

echo ""
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
