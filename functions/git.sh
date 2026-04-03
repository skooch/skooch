git() {
    local subcmd="${1:-}"
    case "$subcmd" in
        clone|fetch|pull|ls-remote)
            gitcache "$@"
            ;;
        submodule)
            case "${2:-}" in
                update)
                    shift 2
                    gitcache submodule-update "$@"
                    ;;
                *)
                    command git "$@"
                    ;;
            esac
            ;;
        remote)
            case "${2:-}" in
                update)
                    shift 2
                    gitcache remote-update "$@"
                    ;;
                *)
                    command git "$@"
                    ;;
            esac
            ;;
        *)
            command git "$@"
            ;;
    esac
}

trifecta() {
    git add -u
    git commit --amend --no-edit
    git push --force
}
