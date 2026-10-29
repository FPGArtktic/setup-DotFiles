# shellcheck shell=bash
# ===========================================================================
#  ~/.config/shell/fzf.sh - fzf options and helpers shared by bash and zsh
#
#  The key bindings (Ctrl-R, Ctrl-T, Alt-C) are wired in bashrc and zshrc,
#  because `fzf --bash` and `fzf --zsh` are shell-specific.
# ===========================================================================

command -v fzf >/dev/null 2>&1 || return 0

if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
else
  export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
fi
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

_fzf_file_preview='bat --style=numbers,changes --color=always --line-range :300 {} 2>/dev/null || cat {}'
_fzf_dir_preview='eza --tree --level=2 --icons=always --color=always {} 2>/dev/null || ls -la {}'

# Colours by ANSI name, so fzf follows the terminal palette like starship does.
export FZF_DEFAULT_OPTS="
  --height=60% --layout=reverse --border=rounded --info=inline-right
  --prompt='❯ ' --pointer='▶' --marker='✓' --separator='─' --scrollbar='│'
  --preview-window=right:55%:wrap:border-left
  --bind='ctrl-/:toggle-preview,ctrl-d:preview-page-down,ctrl-u:preview-page-up'
  --bind='alt-j:preview-down,alt-k:preview-up,?:toggle-preview-wrap'
  --color=fg:-1,bg:-1,hl:magenta:bold,fg+:bright-white:bold,bg+:black,hl+:magenta:bold
  --color=info:yellow,prompt:green,pointer:red,marker:green,spinner:yellow
  --color=header:blue,border:bright-black,separator:bright-black,scrollbar:bright-black
"
export FZF_CTRL_T_OPTS="--preview '$_fzf_file_preview'"
export FZF_ALT_C_OPTS="--preview '$_fzf_dir_preview'"
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window=up:3:hidden:wrap --bind='ctrl-/:toggle-preview'"
export _fzf_file_preview _fzf_dir_preview

# fcd - cd into a chosen directory
fcd() { local d; d=$(fd --type d --hidden --exclude .git . "${1:-.}" | fzf --preview "$_fzf_dir_preview") && cd "$d" || return; }

# fo - open a file in $EDITOR
fo() { local f; f=$(fzf --query="${1:-}" --select-1 --exit-0 --preview "$_fzf_file_preview") && ${EDITOR:-vim} "$f"; }

# fgr <pattern> - rg + fzf, opens the match in $EDITOR on its line
fgr() {
  local sel file line
  sel=$(rg --color=always --line-number --no-heading "$@" |
    fzf --ansi --delimiter=: -0 -1 \
      --preview 'bat --color=always --highlight-line {2} {1}' \
      --preview-window='right:55%:+{2}-/2') || return
  file=${sel%%:*}; line=${sel#*:}; line=${line%%:*}
  ${EDITOR:-vim} "$file" +"$line"
}

# fbr - git checkout of a local or remote branch
fbr() {
  local b
  # shellcheck disable=SC2016  # expanded by fzf's preview shell, not here
  b=$(git branch -a --color=always --sort=-committerdate | grep -v HEAD |
    fzf --ansi --no-sort --preview 'git log --oneline --graph --color=always -20 $(echo {} | sed "s/^[* ]*//")') || return
  b=$(echo "$b" | sed 's/^[* ]*//; s#^remotes/[^/]*/##')
  git checkout "$b"
}

# fkill [SIGNAL] - kill the chosen processes (TERM by default)
fkill() {
  local pid
  pid=$(ps -ef | sed 1d | fzf -m --header='[kill]' | awk '{print $2}')
  [ -n "$pid" ] && echo "$pid" | xargs kill -"${1:-15}"
}

# flog - browse the git history
flog() {
  git log --oneline --color=always --decorate "$@" |
    fzf --ansi --no-sort --preview 'git show --color=always {1} | delta 2>/dev/null || git show --color=always {1}' |
    awk '{print $1}'
}
