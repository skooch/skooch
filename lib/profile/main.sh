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

    if [[ ! -f "$PROFILE_SNAPSHOT_FILE" ]]; then
        echo "No snapshot found. Run 'profile use $active' to create one."
        return 0
    fi

    local current_hash
    current_hash=$(_profile_compute_hash "$active")
    local stored_hash=$(cat "$PROFILE_SNAPSHOT_FILE" 2>/dev/null)

    if [[ "$current_hash" == "$stored_hash" ]]; then
        echo "Everything is in sync."
    else
        echo "Profile files have changed since last switch."
        echo "Run 'profile sync' to reconcile changes."
    fi
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
            _profile_apply_vscode "$active_set"
            _profile_apply_iterm "$active_set"
            _profile_apply_tmux "$active_set"
            _profile_apply_mise "$active_set"
            _profile_apply_brew "$active_set"
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
            _profile_ensure_links
            _profile_sync_brew "$active"
            _profile_sync_vscode "$active"
            _profile_apply_git "$active"
            _profile_sync_mise "$active"
            _profile_sync_claude "$active"
            _profile_sync_iterm "$active"
            _profile_sync_tmux "$active"
            echo ""
            echo "Taking snapshot..."
            _profile_take_snapshot "$active"
            local display="${active// /, }"
            echo "Profiles synced: $display"
            _profile_offer_commit_push
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
            echo "  use [name] [name2 ...]     (s)   Apply profiles (brew + vscode + iterm + git + mise + claude + tmux); default alone if no args"
            echo "  diff [name] [name2 ...]    (d)   Preview what use would change"
            echo "  sync                       (sy)  Bidirectional sync — detects which direction changed and reconciles"
            echo "  status                     (st)  Show active profiles and drift"
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
