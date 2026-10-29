# ===========================================================================
#  zshrc - zsh + Oh My Zsh
#  Author: Mateusz Okulanis
#  License: GPLv3 or later
#
#  Installed by setup-dotFiles.sh as ~/.config/setup-dotfiles/zshrc and
#  sourced from ONE guarded line in ~/.zshrc.
#
#  Shared with bash:  ~/.config/shell/{env,aliases,functions,fzf}.sh
#  Prompt:            `prompt-use mtsh` | `prompt-use starship`
#                     (the choice is kept in ~/.config/shell/prompt)
#  Your own stuff:    ~/.config/shell/local.sh or ~/.zshrc.local
#  Silence the fastfetch greeting: DOTFILES_NO_FETCH=1
# ===========================================================================

SHELLCFG="${XDG_CONFIG_HOME:-$HOME/.config}/shell"
[[ -r $SHELLCFG/env.sh ]] && source "$SHELLCFG/env.sh"

# fastfetch greeting - but not in tmux, VS Code, Claude Code shells or a
# nested shell that has already shown it.
if [[ -z $DOTFILES_NO_FETCH && -z $DOTFILES_FETCH_SHOWN && -z $TMUX && -z $CLAUDECODE \
      && $TERM_PROGRAM != vscode && -t 1 ]] && (( $+commands[fastfetch] )); then
  export DOTFILES_FETCH_SHOWN=1
  fastfetch
fi

# --- Oh My Zsh ----------------------------------------------------------------
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"

# The prompt: mtsh (an Oh My Zsh theme) or starship. The file is read only
# when it exists - $(<file) does not silence a missing file in zsh.
SHELL_PROMPT=mtsh
[[ -r $SHELLCFG/prompt ]] && SHELL_PROMPT=$(<"$SHELLCFG/prompt")
if [[ $SHELL_PROMPT == starship ]] && (( $+commands[starship] )); then
  ZSH_THEME=""
elif [[ -f $ZSH/custom/themes/mtsh.zsh-theme ]]; then
  ZSH_THEME="mtsh"
else
  ZSH_THEME="robbyrussell"
fi

zstyle ':omz:update' mode reminder
HIST_STAMPS="yyyy-mm-dd"
DISABLE_UNTRACKED_FILES_DIRTY="true"   # faster in huge repositories (buildroot, poky)
ZSH_DISABLE_COMPFIX="true"

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=40
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

# Completions from ~/.local (anything installed without a package). Must be
# in fpath BEFORE oh-my-zsh.sh, which is where compinit runs.
fpath=("$HOME/.local/share/zsh/site-functions" $fpath)

# Order matters: fzf-tab after compinit but before the plugins that wrap ZLE
# widgets; fast-syntax-highlighting and history-substring-search last. A
# custom plugin that is not cloned is simply left out instead of erroring.
plugins=(git sudo extract colored-man-pages command-not-found copypath copybuffer)
for __p in fzf-tab zsh-autosuggestions fast-syntax-highlighting zsh-history-substring-search; do
  [[ -d $ZSH/custom/plugins/$__p ]] && plugins+=("$__p")
done
unset __p

if [[ -f $ZSH/oh-my-zsh.sh ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  autoload -Uz compinit && compinit -u -d "${ZDOTDIR:-$HOME}/.zcompdump"
fi

# --- history ------------------------------------------------------------------
HISTFILE=~/.zsh_history
HISTSIZE=1000000
SAVEHIST=1000000
setopt EXTENDED_HISTORY        # timestamp in the history file
setopt SHARE_HISTORY           # one history across open terminals
setopt HIST_IGNORE_ALL_DUPS    # drop the older duplicate
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE       # a command starting with a space is not saved
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY             # !! shows the command instead of running it

# --- behaviour ----------------------------------------------------------------
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT
setopt INTERACTIVE_COMMENTS NO_BEEP
WORDCHARS=${WORDCHARS//[\/.=-]}   # Ctrl-W deletes one path segment, not the whole path

# --- completion + fzf-tab -----------------------------------------------------
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu no                      # fzf-tab does the menu
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:*' fzf-flags --height=50%
zstyle ':fzf-tab:complete:(cd|z|ls|eza|l|ll):*' fzf-preview 'eza -1 --icons=always --color=always $realpath'
zstyle ':fzf-tab:complete:(cat|bat|b|vim|nvim|less):*' fzf-preview 'bat --color=always --line-range :200 $realpath 2>/dev/null || eza -1 --color=always $realpath'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps -o pid,user,%cpu,%mem,cmd -p $word'
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word'
zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview 'git diff --color=always $word | delta 2>/dev/null'

# --- keys ---------------------------------------------------------------------
if (( $+widgets[history-substring-search-up] )); then
  bindkey '^[[A' history-substring-search-up        # up/down search by the typed prefix
  bindkey '^[[B' history-substring-search-down
  [[ -n ${terminfo[kcuu1]} ]] && bindkey "${terminfo[kcuu1]}" history-substring-search-up
  [[ -n ${terminfo[kcud1]} ]] && bindkey "${terminfo[kcud1]}" history-substring-search-down
fi
(( $+widgets[autosuggest-accept] )) && bindkey '^ ' autosuggest-accept   # Ctrl-Space takes the suggestion
bindkey '^[[1;5C' forward-word                    # Ctrl-Right / Ctrl-Left
bindkey '^[[1;5D' backward-word

# --- tools --------------------------------------------------------------------
[[ -r $SHELLCFG/fzf.sh ]] && source "$SHELLCFG/fzf.sh"
# After Oh My Zsh: its lib/key-bindings.zsh binds Ctrl-R, and fzf has to win.
(( $+commands[fzf] )) && source <(fzf --zsh)        # Ctrl-R history, Ctrl-T file, Alt-C directory
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"   # z <fragment>, zi interactively

[[ -r $SHELLCFG/aliases.sh ]]   && source "$SHELLCFG/aliases.sh"
[[ -r $SHELLCFG/functions.sh ]] && source "$SHELLCFG/functions.sh"
alias reload='exec zsh'
alias zshrc='${EDITOR:-vim} ~/.zshrc.local'

# prompt-use mtsh|starship - switch the prompt and restart the shell
prompt-use() {
  [[ $1 == (mtsh|starship) ]] || { print -u2 "usage: prompt-use mtsh|starship"; return 1; }
  mkdir -p "$SHELLCFG" && print -r -- $1 >| "$SHELLCFG/prompt" && exec zsh
}

[[ -z $ZSH_THEME ]] && eval "$(starship init zsh)"

# --- local overrides, last ----------------------------------------------------
[[ -r $SHELLCFG/local.sh ]] && source "$SHELLCFG/local.sh"
[[ -r $HOME/.zshrc.local ]] && source "$HOME/.zshrc.local"
