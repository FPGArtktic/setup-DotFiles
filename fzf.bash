#!/bin/bash

# Setup fzf
# ---------
if [[ ! "$PATH" == */home/$USER/.fzf/bin* ]]; then
  PATH="${PATH:+${PATH}:}/home/$USER/.fzf/bin"
fi

# FZF options
# -----------

# Use ripgrep if available for faster search
if command -v rg >/dev/null; then
  export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
elif command -v fd >/dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
else
  export FZF_DEFAULT_COMMAND='find . -type f -not -path "*/\.git/*" -not -path "*/node_modules/*"'
fi

# Preview options based on available tools
if command -v bat >/dev/null; then
  export FZF_PREVIEW_COMMAND="bat --style=numbers,changes --wrap never --color always {} || cat {} || ls -la {}"
elif command -v highlight >/dev/null; then
  export FZF_PREVIEW_COMMAND="highlight -O ansi -l {} || cat {} || ls -la {}"
else
  export FZF_PREVIEW_COMMAND="cat {} || ls -la {}"
fi

# Default options with preview window and better colors
export FZF_DEFAULT_OPTS="
  --height 80% 
  --layout=reverse 
  --border=rounded
  --preview-window=right:60%:wrap
  --marker='✓'
  --pointer='▶'
  --prompt='❯ '
  --info=inline
  --bind='ctrl-/:toggle-preview'
  --bind='ctrl-d:preview-page-down'
  --bind='ctrl-u:preview-page-up'
  --bind='?:toggle-preview-wrap'
  --bind='alt-j:preview-down'
  --bind='alt-k:preview-up'
  --color=dark
  --color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#ffffff,bg+:#44475a,hl+:#d858fe
  --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4
"

# CTRL-T config - show file search
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="
  --preview '($FZF_PREVIEW_COMMAND) 2> /dev/null'
  --bind 'ctrl-/:change-preview-window(down|hidden|)'
"

# ALT-C config - show directory search
export FZF_ALT_C_COMMAND="find . -type d -not -path '*/\.git/*' -not -path '*/node_modules/*'"
if command -v fd >/dev/null; then
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi
export FZF_ALT_C_OPTS="
  --preview 'ls -la --color=always {}'
  --bind 'ctrl-/:change-preview-window(down|hidden|)'
"

# Ctrl+R - historia poleceń
export FZF_CTRL_R_OPTS="
  --preview 'echo {}'
  --preview-window up:3:wrap
  --bind 'ctrl-/:toggle-preview'
"

# Custom functions
# ---------------

# fzf-cd - cd to selected directory
fcd() {
  local dir
  dir=$(find ${1:-.} -type d 2> /dev/null | fzf +m) && cd "$dir"
}

# fzf-open - open file with default editor
fo() {
  local file
  file=$(fzf --query="$1" --select-1 --exit-0) && [ -n "$file" ] && ${EDITOR:-vim} "$file"
}

# fzf-grep - search file contents and open matches
fgr() {
  local file line
  if command -v rg >/dev/null; then
    { IFS=: read -r file line < <(rg --color=always --line-number "$@" | fzf -0 -1 --ansi --delimiter : \
      --preview "bat --color=always --highlight-line {2} {1} || highlight -O ansi -l {1} || cat {1}"); } 2>/dev/null
  else
    { IFS=: read -r file line < <(grep --color=always --line-number "$@" . | fzf -0 -1 --ansi --delimiter : \
      --preview "cat {1} | head -500"); } 2>/dev/null
  fi
  [ -n "$file" ] && ${EDITOR:-vim} "$file" +"$line"
}

# fzf-git-checkout - checkout git branch/tag
fbr() {
  local branches branch
  branches=$(git --no-pager branch -a) &&
  branch=$(echo "$branches" | fzf +s +m -e) &&
  git checkout $(echo "$branch" | sed "s:.* remotes/origin/::" | sed "s:.* ::")
}

# fzf-kill-process - kill process
fkill() {
  local pid
  pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
  if [ "x$pid" != "x" ]; then
    echo $pid | xargs kill -${1:-9}
  fi
}

# Bardziej czytelne aliasy
alias fzp="fzf --preview '($FZF_PREVIEW_COMMAND) 2> /dev/null'"
alias fzd="cd \$(find . -type d | fzf --preview 'ls -la --color=always {}')"

# Evaluate fzf bash completion
eval "$(fzf --bash)"
