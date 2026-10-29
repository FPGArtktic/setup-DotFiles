# shellcheck shell=bash
# ===========================================================================
#  ~/.config/shell/functions.sh - functions shared by bash and zsh
# ===========================================================================

# mkdir + cd
mkcd() { mkdir -p -- "$1" && cd -- "$1" || return; }

# up [N] - cd N directories up
up() { local d='' i; for ((i = 0; i < ${1:-1}; i++)); do d="../$d"; done; cd "${d:-..}" || return; }

# hlp <cmd> - coloured --help through bat (bash's builtin `help` is left alone)
hlp() { "$@" --help 2>&1 | bat -p -l help; }

# x <archive> - unpack anything. `function x {` and not `x() {`: Oh My Zsh's
# extract plugin defines an ALIAS x, and zsh expands aliases while parsing
# `x() {`, which turns into "parse error near ()". The keyword form is not
# expanded.
function x {
  [ -f "$1" ] || { echo "x: no such file: $1" >&2; return 1; }
  case "$1" in
    *.tar.bz2|*.tbz2) tar xjf "$1" ;;
    *.tar.gz|*.tgz)   tar xzf "$1" ;;
    *.tar.xz|*.txz)   tar xJf "$1" ;;
    *.tar.zst)        tar --zstd -xf "$1" ;;
    *.tar)            tar xf "$1" ;;
    *.bz2)            bunzip2 "$1" ;;
    *.gz)             gunzip "$1" ;;
    *.xz)             unxz "$1" ;;
    *.zst)            unzstd "$1" ;;
    *.zip)            unzip "$1" ;;
    *.7z)             7z x "$1" ;;
    *.rar)            unrar x "$1" ;;
    *)                echo "x: do not know how to unpack $1" >&2; return 1 ;;
  esac
}
