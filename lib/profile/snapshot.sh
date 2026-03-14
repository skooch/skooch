# Profile system - snapshot, hashing, and drift detection

_profile_take_snapshot() {
    local profiles="$1"
    mkdir -p "$PROFILE_STATE_DIR"
    local hash=""
    for dir in $(_profile_collect_dirs "$profiles"); do
        for f in $(_profile_snapshot_files "$dir"); do
            [[ -f "$f" ]] && hash+=$(_platform_md5 "$f" 2>/dev/null)
        done
    done
    echo "$hash" > "$PROFILE_SNAPSHOT_FILE"

    # Local target file hashes (for three-way sync direction detection)
    local snap_local="$PROFILE_STATE_DIR/snapshot-local"
    : > "$snap_local"
    while IFS= read -r target_path; do
        if [[ -n "$target_path" && -f "$target_path" ]]; then
            local real_path="$target_path"
            [[ -L "$target_path" ]] && real_path=$(readlink "$target_path")
            printf '%s\t%s\n' "$target_path" "$(_platform_md5 "$real_path")" >> "$snap_local"
        fi
    done < <(_profile_target_paths "$profiles")
}

_profile_compute_hash() {
    local profiles="$1"
    local hash=""
    for dir in $(_profile_collect_dirs "$profiles"); do
        for f in $(_profile_snapshot_files "$dir"); do
            [[ -f "$f" ]] && hash+=$(_platform_md5 "$f" 2>/dev/null)
        done
    done
    echo "$hash"
}

# Retrieve snapshot hash for a local target file
_profile_local_snap_hash() {
    local target_path="$1"
    local snap_file="$PROFILE_STATE_DIR/snapshot-local"
    [[ -f "$snap_file" ]] || return
    local snap_path snap_hash
    while IFS=$'\t' read -r snap_path snap_hash <&3; do
        [[ "$snap_path" == "$target_path" ]] && { echo "$snap_hash"; return; }
    done 3< "$snap_file"
}

# --- Drift check ---

_profile_check_drift() {
    _profile_dedup_dotfiles
    _profile_check_remote

    local active=$(_profile_active)
    [[ -z "$active" ]] && return 0
    [[ ! -f "$PROFILE_SNAPSHOT_FILE" ]] && return 0

    local current_hash
    current_hash=$(_profile_compute_hash "$active")
    local stored_hash=$(cat "$PROFILE_SNAPSHOT_FILE" 2>/dev/null)

    if [[ "$current_hash" != "$stored_hash" ]]; then
        local display="${active// /, }"
        echo "Profile(s) '$display' have unsynced changes. Run 'profile sync' to reconcile."
    fi
}

# --- Remote check ---

_profile_check_remote() {
    [[ ! -d "$DOTFILES_DIR/.git" ]] && return 0

    # Use FETCH_HEAD age to avoid hitting the network every shell startup
    local fetch_head="$DOTFILES_DIR/.git/FETCH_HEAD"
    if [[ -f "$fetch_head" ]]; then
        local mtime
        mtime=$(stat -c %Y "$fetch_head" 2>/dev/null || stat -f %m "$fetch_head" 2>/dev/null)
        [[ "$mtime" =~ ^[0-9]+$ ]] || return 0
        local fetch_age=$(( $(date +%s) - mtime ))
        # Only check if last fetch was within the last hour (already cached)
        if [[ $fetch_age -gt 3600 ]]; then
            return 0
        fi
        local behind
        behind=$(git -C "$DOTFILES_DIR" rev-list --count HEAD..@{u} 2>/dev/null)
        if [[ -n "$behind" && "$behind" -gt 0 ]]; then
            echo "Dotfiles repo is $behind commit(s) behind remote. Run 'git -C $DOTFILES_DIR pull' to update."
        fi
    fi
}
