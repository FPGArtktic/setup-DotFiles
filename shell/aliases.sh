# shellcheck shell=sh disable=SC2139  # the eza aliases expand $_eza once, on purpose
# ===========================================================================
#  ~/.config/shell/aliases.sh - aliases shared by bash and zsh
#
#  Rule: the classic commands (ls, cat, grep) keep their meaning, because
#  scripts and habits (ls -lt) have to keep working. New tools get new names.
# ===========================================================================

alias ls='ls --color=auto --group-directories-first'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -color=auto'

if command -v eza >/dev/null 2>&1; then
  _eza='eza --icons=auto --group-directories-first'
  alias l="$_eza -lh --git"
  alias ll="$_eza -lah --git"
  alias la="$_eza -a"
  alias lt="eza --icons=auto -lh --sort=modified"     # newest at the bottom
  alias tree="$_eza --tree"
  alias t2="$_eza --tree --level=2"
  unset _eza
fi

if command -v bat >/dev/null 2>&1; then
  alias b='bat'
  alias bp='bat -p'                                    # no frame, cat with colours
fi

# podman only, no docker on this machine. Old commands, notes and scripts
# typed by hand keep working; podman takes the same arguments.
if command -v podman >/dev/null 2>&1; then
  alias docker='podman'
  command -v podman-compose >/dev/null 2>&1 && alias docker-compose='podman-compose'
fi

command -v lazygit    >/dev/null 2>&1 && alias lg='lazygit'
command -v podman-tui >/dev/null 2>&1 && alias lzp='podman-tui'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias df='df -h'
alias du1='du -h --max-depth=1 | sort -h'
alias free='free -h'
alias path='echo "$PATH" | tr : "\n"'
alias ports='ss -tulpn'
alias cpv='rsync -avh --progress'
alias dmesgw='sudo dmesg -wH'
alias serial='minicom -c on -D'                        # serial /dev/ttyUSB0
alias gs='git status -sb'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate --all'
