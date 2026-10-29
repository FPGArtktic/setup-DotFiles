# shellcheck shell=bash
# ===========================================================================
#  bashrc - bash: ble.sh + starship + fzf + zoxide
#  Author: Mateusz Okulanis
#  License: GPLv3 or later
#
#  Installed by setup-dotFiles.sh as ~/.config/setup-dotfiles/bashrc and
#  sourced from ONE guarded line in ~/.bashrc, so a reinstall updates this
#  file instead of appending another copy of it.
#
#  Shared with zsh:  ~/.config/shell/{env,aliases,functions,fzf}.sh
#  Your own stuff:   ~/.config/shell/local.sh or ~/.bashrc.local (both
#                    sourced last, never written by the installer)
#  Disable ble.sh for one session: NO_BLE=1 bash
#  Silence the fastfetch greeting:  DOTFILES_NO_FETCH=1
# ===========================================================================

# Interactive shells only.
case $- in
  *i*) ;;
  *) return ;;
esac

SHELLCFG="${XDG_CONFIG_HOME:-$HOME/.config}/shell"
BLESH="$HOME/.local/share/blesh/ble.sh"

# ble.sh (autosuggestions, syntax highlighting, better completion). Loaded
# as early as possible with --noattach and attached at the very end of this
# file, after starship and fzf have set their hooks. Without a real tty
# (bash -c, scp) ble.sh does not start, so it cannot break scripts.
# shellcheck disable=SC1090
[[ -z ${NO_BLE-} && -r $BLESH ]] && source "$BLESH" --noattach

# shellcheck disable=SC1091
[ -r "$SHELLCFG/env.sh" ] && . "$SHELLCFG/env.sh"

# fastfetch greeting - but not in tmux, VS Code, Claude Code shells or a
# nested shell that has already shown it.
if [[ -z ${DOTFILES_NO_FETCH-} && -z ${DOTFILES_FETCH_SHOWN-} && -z ${TMUX-} \
      && -z ${CLAUDECODE-} && ${TERM_PROGRAM-} != vscode ]] && [ -t 1 ] \
   && command -v fastfetch >/dev/null; then
  export DOTFILES_FETCH_SHOWN=1
  fastfetch
fi

# --- history ------------------------------------------------------------------
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=-1
HISTFILESIZE=-1
HISTTIMEFORMAT="%F %T "
HISTIGNORE="ls:ll:l:la:cd:pwd:exit:clear:history"
shopt -s histappend cmdhist
case "${PROMPT_COMMAND-}" in
  *'history -a'*) ;;
  *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
esac

# --- behaviour ----------------------------------------------------------------
shopt -s checkwinsize autocd cdspell dirspell globstar extglob no_empty_cmd_completion

if command -v dircolors >/dev/null; then
  if [ -r ~/.dircolors ]; then eval "$(dircolors -b ~/.dircolors)"; else eval "$(dircolors -b)"; fi
fi

if ! shopt -oq posix && [ -f /usr/share/bash-completion/bash_completion ]; then
  # shellcheck disable=SC1091
  . /usr/share/bash-completion/bash_completion
fi

# --- aliases and functions ----------------------------------------------------
# shellcheck disable=SC1091
[ -r "$SHELLCFG/aliases.sh" ]   && . "$SHELLCFG/aliases.sh"
# shellcheck disable=SC1091
[ -r "$SHELLCFG/functions.sh" ] && . "$SHELLCFG/functions.sh"
alias reload='exec bash'
alias bashrc='${EDITOR:-vim} ~/.bashrc.local'
alias cp='rsync -avh --progress'      # the old bash habit; plain cp is \cp
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# --- tools --------------------------------------------------------------------
# shellcheck disable=SC1091
[ -r "$SHELLCFG/fzf.sh" ] && . "$SHELLCFG/fzf.sh"
if command -v fzf >/dev/null; then
  if [[ ${BLE_VERSION-} ]]; then
    ble-import -d integration/fzf-completion
    ble-import -d integration/fzf-key-bindings
  else
    eval "$(fzf --bash)"
  fi
fi
command -v zoxide >/dev/null && eval "$(zoxide init bash)"

# --- prompt -------------------------------------------------------------------
if command -v starship >/dev/null; then
  eval "$(starship init bash)"
else
  # Fallback prompt: time user host directory (branch)
  git_branch() { git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'; }
  PS1='\[\e[1;31m\]\t \[\e[1;32m\]\u \[\e[2;36m\]\h \[\e[1;33m\]\w\[\e[0;33m\]$(git_branch)\[\e[0m\]\n\$ '
fi

# --- local overrides, last ----------------------------------------------------
# shellcheck disable=SC1091
[ -r "$SHELLCFG/local.sh" ] && . "$SHELLCFG/local.sh"
# shellcheck disable=SC1091
[ -r "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"

# ble.sh has to be attached at the very end.
[[ ${BLE_VERSION-} ]] && ble-attach
