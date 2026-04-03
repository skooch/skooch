gitcache() {
    local subcmd="${1:-help}"
    case "$subcmd" in
        setup|install|start|stop|restart|status|logs|disable)
            "$HOME/projects/skooch/lib/git-cache/setup.sh" "$@"
            ;;
        clone|fetch|pull|ls-remote|submodule-update|remote-update)
            "$HOME/projects/skooch/lib/git-cache/git.sh" "$@"
            ;;
        push)
            echo "gitcache push is intentionally unsupported. Push directly with git push." >&2
            return 2
            ;;
        help|-h|--help|"")
            "$HOME/projects/skooch/lib/git-cache/git.sh" help
            ;;
        *)
            echo "Unknown gitcache command: $subcmd" >&2
            "$HOME/projects/skooch/lib/git-cache/git.sh" help >&2
            return 1
            ;;
    esac
}
