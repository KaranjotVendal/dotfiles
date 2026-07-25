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
    current_test="skeleton: 'verify' subcommand accepted"

    local out exit_code=0
    out=$("$SCRIPT_UNDER_TEST" verify 2>&1) || exit_code=$?

    assert_not_contains "Usage:" "$out" "should not print usage"
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

echo ""
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
