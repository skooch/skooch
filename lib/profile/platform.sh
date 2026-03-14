# Profile system - platform detection and cross-platform helpers

IS_MACOS=false
IS_LINUX=false

case "$(uname -s)" in
    Darwin) IS_MACOS=true ;;
    Linux)  IS_LINUX=true ;;
esac

# Cross-platform md5 hash of a file
_platform_md5() {
    if [[ "$IS_MACOS" == true ]]; then
        md5 -q "$1" 2>/dev/null
    else
        md5sum "$1" 2>/dev/null | cut -d' ' -f1
    fi
}

# Cross-platform sha256 (reads stdin)
_platform_sha256() {
    if command -v shasum &>/dev/null; then
        shasum -a 256
    else
        sha256sum
    fi
}
