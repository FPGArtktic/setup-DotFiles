# shellcheck shell=sh
# ===========================================================================
#  ~/.config/shell/env.sh - environment shared by bash and zsh
#  Installed by setup-dotFiles.sh from shell/env.sh. A reinstall overwrites
#  it; machine-specific settings belong in ~/.config/shell/local.sh.
#
#  POSIX syntax only: this file is sourced by both shells.
# ===========================================================================

# Add a directory to PATH once, and only when it exists.
path_prepend() { case ":$PATH:" in *":$1:"*) ;; *) [ -d "$1" ] && PATH="$1:$PATH" ;; esac; }
path_append()  { case ":$PATH:" in *":$1:"*) ;; *) [ -d "$1" ] && PATH="$PATH:$1" ;; esac; }

path_prepend "$HOME/.local/bin"
path_append  "$HOME/.local/share/nvim/mason/bin"

# Neovim is the editor of this configuration (nvim/ in the repository); vim
# is the fallback on a machine that has not run the package step yet.
if command -v nvim >/dev/null 2>&1; then
  export EDITOR=nvim VISUAL=nvim
else
  export EDITOR=vim VISUAL=vim
fi
export PAGER=less
export LESS='-R -F -i -M -j.3'          # colours, quit if one screen, smart case
export LESSHISTFILE=-
export BAT_THEME=ansi                   # bat takes its colours from the terminal palette
export MANPATH="$HOME/.local/share/man:${MANPATH:-}"

export PATH
