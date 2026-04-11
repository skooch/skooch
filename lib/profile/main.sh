# Profile system - main entry point, status, hosts, and git helpers

# --- Status ---

_profile_status() {
    local active=$(_profile_active)
    if [[ -z "$active" ]]; then
        echo "No active profile. Run 'profile use <name>' first."
        return 0
    fi

    local display="${active// /, }"
    echo "Active profiles: $display"

    if [[ ! -f "$PROFILE_CHECKPOINT_FILE" ]]; then
        echo "No checkpoint found. Run 'profile use $active' or 'profile checkpoint' to create one."
        return 0
    fi

    _profile_check_remote true >/dev/null 2>&1 || true
    case "$_PROFILE_REMOTE_STATE" in
        current|ahead)
            echo "Remote: $_PROFILE_REMOTE_MESSAGE"
            ;;
        no_upstream|unavailable)
            echo "Remote: $_PROFILE_REMOTE_MESSAGE"
            ;;
        behind|diverged|stale|refresh_failed|unknown)
            echo "Remote: $_PROFILE_REMOTE_MESSAGE"
            ;;
    esac

    local checkpoint_state="current"
    if _profile_checkpoint_stale "$active"; then
        checkpoint_state="stale"
    fi
    echo "Checkpoint: $checkpoint_state"

    _profile_collect_reconcile_status "$active"

    if [[ "$checkpoint_state" == "current" && $_PROFILE_RECONCILE_SAFE_COUNT -eq 0 && $_PROFILE_RECONCILE_BLOCKED_COUNT -eq 0 && $_PROFILE_RECONCILE_CONFLICT_COUNT -eq 0 ]]; then
        echo "Everything is in sync."
        return 0
    fi

    if [[ "$checkpoint_state" == "stale" && $_PROFILE_RECONCILE_SAFE_COUNT -eq 0 && $_PROFILE_RECONCILE_BLOCKED_COUNT -eq 0 && $_PROFILE_RECONCILE_CONFLICT_COUNT -eq 0 ]]; then
        echo "Managed targets already match the canonical profile state."
        echo "Run 'profile checkpoint' to acknowledge the new baseline."
        return 0
    fi

    if [[ "$checkpoint_state" == "current" ]]; then
        echo "Managed state drift was detected outside the checkpointed file hash."
    fi

    (( _PROFILE_RECONCILE_SAFE_COUNT > 0 )) && echo "Safe sync actions: $_PROFILE_RECONCILE_SAFE_COUNT"
    (( _PROFILE_RECONCILE_BLOCKED_COUNT > 0 )) && echo "Blocked sync-back items: $_PROFILE_RECONCILE_BLOCKED_COUNT"
    (( _PROFILE_RECONCILE_CONFLICT_COUNT > 0 )) && echo "Conflicts requiring review: $_PROFILE_RECONCILE_CONFLICT_COUNT"

    local line=""
    for line in "${_PROFILE_RECONCILE_LINES[@]}"; do
        echo "  - $line"
    done

    if [[ "$_PROFILE_REMOTE_STATE" == "behind" || "$_PROFILE_REMOTE_STATE" == "diverged" || "$_PROFILE_REMOTE_STATE" == "stale" || "$_PROFILE_REMOTE_STATE" == "refresh_failed" || "$_PROFILE_REMOTE_STATE" == "unknown" ]]; then
        echo "Resolve the remote state above before running 'profile sync'."
    elif (( _PROFILE_RECONCILE_CONFLICT_COUNT > 0 || _PROFILE_RECONCILE_BLOCKED_COUNT > 0 )); then
        echo "Run 'profile sync' only after reviewing the items above."
    else
        echo "Run 'profile sync' to apply the safe changes above."
    fi
}

_profile_checkpoint() {
    local active=$(_profile_active)
    if [[ -z "$active" ]]; then
        echo "No active profile. Run 'profile use <name>' first."
        return 1
    fi

    echo "Taking checkpoint..."
    _profile_take_snapshot "$active"
    local display="${active// /, }"
    echo "Checkpoint updated for: $display"
}

# --- Host mapping ---

_profile_register() {
    local machine_id
    machine_id=$(_profile_machine_id)
    local active=$(_profile_active)

    if [[ -z "$active" ]]; then
        echo "No active profiles. Run 'profile use <name>' first."
        return 1
    fi

    local -a profile_list=(${=active})
    local json_array
    json_array=$(printf '%s\n' "${profile_list[@]}" | jq -R . | jq -s .)

    if [[ -f "$HOSTS_FILE" ]]; then
        local updated
        updated=$(jq --arg host "$machine_id" --argjson profiles "$json_array" \
            '.[$host] = $profiles' "$HOSTS_FILE")
        echo "$updated" > "$HOSTS_FILE"
    else
        jq -n --arg host "$machine_id" --argjson profiles "$json_array" \
            '{($host): $profiles}' > "$HOSTS_FILE"
    fi

    local display="${active// /, }"
    echo "Registered $machine_id -> [$display] in hosts.json"
}

_profile_hosts() {
    if [[ ! -f "$HOSTS_FILE" ]]; then
        echo "No hosts.json found. Run 'profile register' to create one."
        return 0
    fi

    local current_id
    current_id=$(_profile_machine_id)
    echo "Host mappings:"
    echo ""
    jq -r 'to_entries[] | "  \(.key): \(.value | join(", "))"' "$HOSTS_FILE" | while IFS= read -r line; do
        local host="${line%%:*}"
        local trimmed_host="${host## }"
        if [[ "$trimmed_host" == "$current_id" ]]; then
            echo "$line  (this machine)"
        else
            echo "$line"
        fi
    done
}

# --- Git sync helpers ---

_profile_offer_commit_push() {
    local changes
    changes=$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)
    [[ -z "$changes" ]] && return 0

    echo ""
    echo "Uncommitted dotfiles changes:"
    git -C "$DOTFILES_DIR" status --short
    echo ""
    echo "Diff:"
    git -C "$DOTFILES_DIR" diff
    git -C "$DOTFILES_DIR" diff --cached
    echo ""
    printf "Commit and push? [y/N] "
    local answer
    read -r answer
    if [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]; then
        git -C "$DOTFILES_DIR" add -A
        git -C "$DOTFILES_DIR" commit -m "Update profiles"
        git -C "$DOTFILES_DIR" push
    fi
}

# --- Main entry point ---

profile() {
    local subcmd="${1:-help}"
    shift 2>/dev/null

    case "$subcmd" in
        cache)
            "$DOTFILES_DIR/lib/git-cache/control.sh" "${@:-status}"
            ;;
        use|s)
            _profile_check_deps || return 1
            # Parse -f/--force flag
            local force=false
            local -a args=()
            for arg in "$@"; do
                case "$arg" in
                    -f|--force) force=true ;;
                    *) args+=("$arg") ;;
                esac
            done
            set -- "${args[@]}"

            if [[ $# -eq 0 ]]; then
                set -- "default"
            fi
            for p in "$@"; do
                if [[ ! -d "$PROFILES_DIR/$p" ]]; then
                    echo "Error: profile '$p' not found" >&2
                    return 1
                fi
            done
            local active_set=""
            for p in "$@"; do
                [[ "$p" == "default" ]] && continue
                if [[ -n "$active_set" ]]; then
                    active_set+=" $p"
                else
                    active_set="$p"
                fi
            done
            [[ -z "$active_set" ]] && active_set="default"

            # No-op detection
            if [[ "$force" == "false" ]]; then
                local current_active=$(_profile_active)
                if [[ "$active_set" == "$current_active" ]]; then
                    local current_hash
                    current_hash=$(_profile_compute_hash "$active_set")
                    local stored_hash=$(cat "$PROFILE_SNAPSHOT_FILE" 2>/dev/null)
                    if [[ "$current_hash" == "$stored_hash" ]]; then
                        echo "Already up to date."
                        return 0
                    fi
                fi
            fi

            if [[ "$force" == "false" ]]; then
                _profile_check_overwrite "$active_set" || return 1
            fi

            mkdir -p "$PROFILE_STATE_DIR"
            _profile_ensure_links
            _profile_apply_git "$active_set"
            _profile_apply_claude "$active_set"
            _profile_apply_codex "$active_set"
            _profile_apply_skills "$active_set"
            _profile_apply_vscode "$active_set"
            _profile_apply_iterm "$active_set"
            _profile_apply_tmux "$active_set"
            _profile_apply_mise "$active_set"
            _profile_apply_brew "$active_set"
            _profile_apply_cbm
            _profile_apply_git_cache
            echo "$active_set" > "$PROFILE_ACTIVE_FILE"

            # Record managed files
            local -a managed=()
            while IFS= read -r managed_path; do
                [[ -n "$managed_path" ]] && managed+=("$managed_path")
            done < <(_profile_target_paths "$active_set")
            _profile_write_managed "${managed[@]}"

            echo "Taking snapshot..."
            _profile_take_snapshot "$active_set"
            local display="${active_set// /, }"
            echo "Active profiles: $display"
            _profile_offer_commit_push
            ;;
        diff|d)
            _profile_check_deps || return 1
            if [[ $# -eq 0 ]]; then
                # Default to current active profiles
                local active=$(_profile_active)
                if [[ -z "$active" ]]; then
                    echo "Usage: profile diff <name> [name2 ...]"
                    return 1
                fi
                _profile_diff "$active"
            else
                for p in "$@"; do
                    if [[ ! -d "$PROFILES_DIR/$p" && "$p" != "default" ]]; then
                        echo "Error: profile '$p' not found" >&2
                        return 1
                    fi
                done
                local diff_set=""
                for p in "$@"; do
                    [[ "$p" == "default" ]] && continue
                    if [[ -n "$diff_set" ]]; then
                        diff_set+=" $p"
                    else
                        diff_set="$p"
                    fi
                done
                [[ -z "$diff_set" ]] && diff_set="default"
                _profile_diff "$diff_set"
            fi
            ;;
        sync|sy)
            _profile_check_deps || return 1
            local active=$(_profile_active)
            if [[ -z "$active" ]]; then
                echo "No active profile. Run 'profile use <name>' first."
                return 1
            fi
            _profile_sync_preflight || return 1
            _profile_ensure_links
            local sync_result=0
            local domain_result=0
            _profile_sync_brew "$active"
            domain_result=$?
            (( domain_result > sync_result )) && sync_result=$domain_result
            _profile_sync_vscode "$active"
            domain_result=$?
            (( domain_result > sync_result )) && sync_result=$domain_result
            _profile_apply_git "$active"
            _profile_sync_mise "$active"
            domain_result=$?
            (( domain_result > sync_result )) && sync_result=$domain_result
            _profile_sync_claude "$active"
            domain_result=$?
            (( domain_result > sync_result )) && sync_result=$domain_result
            _profile_sync_codex "$active"
            domain_result=$?
            (( domain_result > sync_result )) && sync_result=$domain_result
            _profile_sync_skills "$active"
            domain_result=$?
            (( domain_result > sync_result )) && sync_result=$domain_result
            _profile_sync_iterm "$active"
            domain_result=$?
            (( domain_result > sync_result )) && sync_result=$domain_result
            _profile_sync_tmux "$active"
            domain_result=$?
            (( domain_result > sync_result )) && sync_result=$domain_result
            if (( sync_result >= 2 )); then
                echo ""
                echo "Checkpoint not updated because sync still requires review."
                return 2
            fi
            echo ""
            echo "Taking snapshot..."
            _profile_take_snapshot "$active"
            local display="${active// /, }"
            echo "Profiles synced: $display"
            _profile_offer_commit_push
            return $sync_result
            ;;
        checkpoint|cp)
            _profile_checkpoint
            ;;
        status|st)
            _profile_status
            ;;
        register)
            _profile_check_deps || return 1
            _profile_register
            _profile_offer_commit_push
            ;;
        hosts)
            _profile_hosts
            ;;
        help|*)
            echo "Usage: profile <command> [args]"
            echo ""
            echo "Commands:"
            echo "  use [name] [name2 ...]     (s)   Apply profiles (brew + vscode + iterm + git + mise + claude + codex + tmux); default alone if no args"
            echo "  diff [name] [name2 ...]    (d)   Preview what use would change"
            echo "  sync                       (sy)  Bidirectional sync — detects which direction changed and reconciles"
            echo "  checkpoint                 (cp)  Acknowledge the current managed state without reconciling changes"
            echo "  status                     (st)  Show active profiles, checkpoint state, and reconcile guidance"
            echo "  cache                            Manage the local Git cache (on, off, status, clear)"
            echo "  register                         Save machine ID + active profiles to hosts.json"
            echo "  hosts                            Show all host mappings"
            echo ""
            echo "Flags:"
            echo "  -f, --force                      Force use even if already up to date"
            echo ""
            echo "Available profiles:"
            local active=$(_profile_active)
            for dir in "$PROFILES_DIR"/*/; do
                local name=$(basename "$dir")
                local marker=""
                [[ " $active " == *" $name "* || "$active" == "$name" ]] && marker=" (active)"
                echo "  $name$marker"
            done
            ;;
    esac
}
