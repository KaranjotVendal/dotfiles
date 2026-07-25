#!/usr/bin/env bash
# omarchy-update-wrapper.bash — Source this from ~/.bashrc to shadow omarchy-update
# with a pre-flight check + interactive AI review + post-update symlink verification.
#
# Usage in ~/.bashrc:
#   source ~/.dotfiles/bin/omarchy-update-wrapper.bash
#
# To bypass:
#   omarchy-update --skip-precheck

omarchy-update() {
    # ---- escape hatch ----
    if [[ "${1:-}" == "--skip-precheck" ]]; then
        shift
        command omarchy-update "$@"
        return $?
    fi

    # ---- run precheck ----
    local precheck_rc=0
    local precheck_out
    precheck_out=$(omarchy-precheck 2>&1) || precheck_rc=$?

    # Always print the precheck output so the user sees it
    echo "$precheck_out"

    # ---- handle up-to-date ----
    if [[ "$precheck_out" == *"up to date"* ]]; then
        command omarchy-update "$@"
        return $?
    fi

    # ---- handle precheck failure (offline, error) ----
    if [[ "$precheck_rc" -ne 0 ]]; then
        echo ""
        echo "Warning: Precheck encountered an issue (offline or error)."
        read -p "Proceed with update anyway? [y/N] " -r
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            command omarchy-update "$@"
            return $?
        fi
        echo "Update aborted."
        return 1
    fi

    # ---- extract latest tag from report header ----
    local latest_tag
    latest_tag=$(echo "$precheck_out" | head -1 | grep -oP '(?<=→ )[^ ]+' || true)

    # ---- spawn AI review ----
    if [[ -n "$latest_tag" ]]; then
        local report_file="$HOME/.cache/omarchy-precheck/$latest_tag.md"
        if [[ -f "$report_file" ]]; then
            local seed_prompt
            seed_prompt='An Omarchy update is pending; the attached report shows exactly what changes. My configs are GNU Stow-managed from ~/.dotfiles and symlink integrity is my #1 concern. Investigate what could break on THIS system: read my real configs, inspect the pending migrations (especially any that touch stowed paths), check anything else relevant. Give a go/no-go assessment and a post-update checklist.'

            if [[ -n "${HERDR_ENV:-}" ]]; then
                # Inside herdr: create workspace, run pi in root pane
                local ws_id
                ws_id=$(herdr workspace create --cwd ~ --label "omarchy-update $latest_tag" 2>/dev/null | grep -oP 'ws-\w+' || true)
                if [[ -n "$ws_id" ]]; then
                    herdr pane run "$ws_id" "pi @$report_file \"$seed_prompt\""
                else
                    echo "Warning: Could not create herdr workspace. Run pi manually:"
                    echo "  pi @$report_file \"$seed_prompt\""
                fi
            else
                # Outside herdr: run pi interactively in current terminal
                echo ""
                echo "Starting AI review... (exit pi when done)"
                echo ""
                pi @"$report_file" "$seed_prompt"
            fi
        fi
    fi

    # ---- y/N gate ----
    echo ""
    read -p "Proceed with update? [y/N] " -r
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo "Update aborted. The report and pi session remain available."
        return 1
    fi

    # ---- run the real update ----
    command omarchy-update "$@"
    local update_rc=$?

    # ---- post-update symlink verification ----
    if [[ -n "$latest_tag" ]]; then
        local snapshot_file="$HOME/.cache/omarchy-precheck/$latest_tag.symlinks"
        if [[ -f "$snapshot_file" ]]; then
            echo ""
            echo "=== Post-Update Symlink Verification ==="
            omarchy-precheck verify "$snapshot_file"
            echo ""
            echo "Review any issues above. If symlinks were severed, re-stow:"
            echo "  cd ~/.dotfiles && stow --restow home"
        fi
    fi

    return ${update_rc:-0}
}
