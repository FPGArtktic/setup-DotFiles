# ===========================================================================
#  setup-DotFiles :: zsh configuration
#
#  Installed by setup-dotFiles.sh as ~/.zshrc.
#
#  This is the same configuration the podman_base work container carries in
#  /etc/skel/.zshrc: the same Oh My Zsh plugin set, the same mtsh theme, the
#  same history behaviour, the same aliases, the same fzf options and fzf-tab
#  previews, the same helper functions. Only the surroundings differ. That
#  image is air-gapped and owns every byte inside itself; this is a real
#  machine, with a network and with software the user installs and removes at
#  will. So here Oh My Zsh is allowed to keep itself up to date, and anything
#  that depends on a program which may not be installed is guarded with
#  `command -v`. A dotfile that prints "command not found" on every new
#  terminal is worse than no dotfile.
#
#  Kept deliberately in step with bashrc in this repository - switching shells
#  should not change what your fingers already know.
#
#  Put your own additions in ~/.zshrc.local - this file is overwritten when
#  the dotfiles are reinstalled, that one never is.
# ===========================================================================

# Some login paths (containers, `su` without a dash, a couple of display
# managers) leave USER empty, and enough tooling reads it that it is worth
# fixing at the source instead of working around later.
if [ -z "${USER:-}" ]; then
    export USER="$(id -un)"
fi

# Local helper, unset again at the bottom so it does not leak into the shell.
# The functions defined further down deliberately do NOT use it: they run long
# after this file has finished, so they spell `command -v` out themselves.
__dot_have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
#  Oh My Zsh
# ---------------------------------------------------------------------------
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"

# https://github.com/FPGArtktic/ohmyzsh-mtsh-theme - cloned into
# $ZSH/custom/themes/mtsh.zsh-theme by setup-dotFiles.sh. It needs a
# powerline-capable font selected in the TERMINAL EMULATOR; no shell
# configuration can supply one. An unknown theme name makes Oh My Zsh print a
# warning on every start, hence the stock fallback.
if [ -f "$ZSH/custom/themes/mtsh.zsh-theme" ]; then
    ZSH_THEME="mtsh"
else
    ZSH_THEME="robbyrussell"
fi

# The container's plugin list, in the container's order:
#   git fzf fzf-tab zsh-autosuggestions zsh-syntax-highlighting sudo tmux
#   command-not-found colored-man-pages
# git, fzf, sudo, tmux, command-not-found and colored-man-pages ship with Oh
# My Zsh. The other three are separate repositories cloned into
# $ZSH/custom/plugins by setup-dotFiles.sh, and naming a plugin that is not
# there makes Oh My Zsh complain on every start - so they are added only when
# their directory exists, and added in place rather than appended, because
# load order matters (zsh-syntax-highlighting must be loaded after anything
# else that hooks the line editor).
plugins=(git fzf)
__dot_omz_plugin() { [ -d "$ZSH/custom/plugins/$1" ] && plugins+=("$1"); }
__dot_omz_plugin fzf-tab
__dot_omz_plugin zsh-autosuggestions
__dot_omz_plugin zsh-syntax-highlighting
unset -f __dot_omz_plugin
plugins+=(sudo tmux command-not-found colored-man-pages)

# The container sets DISABLE_AUTO_UPDATE because it has no network at all and
# an update attempt there is pure noise. This machine has one, so Oh My Zsh is
# left free to update itself - but never with a question in front of a new
# terminal: that prompt blocks tmux panes, scripted shells and every window
# opened at login until somebody answers it. `zstyle ':omz:update' mode auto`
# is the current spelling and DISABLE_UPDATE_PROMPT the one older clones
# understand; both say the same thing, so setting both is safe.
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 7   # days between update checks
DISABLE_UPDATE_PROMPT="true"
UPDATE_ZSH_DAYS=7
ZSH_DISABLE_COMPFIX="true"

if [ -f "$ZSH/oh-my-zsh.sh" ]; then
    source "$ZSH/oh-my-zsh.sh"
else
    # Oh My Zsh is an optional step, and it is oh-my-zsh.sh that normally runs
    # compinit. Without this fallback a machine that declined it would have no
    # tab completion at all - including the extra definitions from the
    # zsh-completions package, which live on $fpath and only need compinit.
    # -u for the same reason ZSH_DISABLE_COMPFIX is set above: the
    # "insecure directories" question must never stop a new terminal.
    autoload -Uz compinit && compinit -u -d "${ZDOTDIR:-$HOME}/.zcompdump"
fi

# ---------------------------------------------------------------------------
#  History - unlimited, shared between sessions, timestamped
#  (must come AFTER oh-my-zsh.sh, which sets its own defaults)
# ---------------------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=1000000000
SAVEHIST=1000000000

setopt EXTENDED_HISTORY           # record timestamp and duration
setopt INC_APPEND_HISTORY         # write immediately, not on exit
setopt SHARE_HISTORY              # share across running sessions
setopt HIST_IGNORE_ALL_DUPS       # keep only the most recent copy
setopt HIST_IGNORE_SPACE          # skip commands starting with a space
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY                # expand !! and let you look before it runs
setopt HIST_FIND_NO_DUPS
unsetopt HIST_EXPIRE_DUPS_FIRST   # never expire - the file is unbounded

# ---------------------------------------------------------------------------
#  Environment  (same as bashrc)
# ---------------------------------------------------------------------------
if __dot_have nvim; then
    export EDITOR=nvim VISUAL=nvim
    export MANPAGER='nvim +Man!'
elif __dot_have vim; then
    export EDITOR=vim VISUAL=vim
fi
export PAGER=less
# -R keep colours, -F quit if it fits on one screen, -X do not clear the
# screen on exit, -i case-insensitive search.
export LESS='-R -F -X -i'

# PATH additions, in the same order the container's /etc/profile.d/wrk-env.sh
# uses:
#   ~/.local/bin                     pip --user, pipx, cargo, hand-built tools
#   ~/.local/share/nvim/mason/bin    the language servers, formatters and
#                                    linters Mason installs for neovim; outside
#                                    this directory they are invisible to
#                                    everything except nvim itself
#   ~/.fzf/bin                       where the standalone fzf installer puts
#                                    its binary (~/.fzf.bash does the same for
#                                    bash)
# The container can write /etc/profile.d; on a host that file belongs to the
# distribution, so the shell rc files are the right place. Listed in reverse
# because each entry is prepended, and case-guarded so that re-sourcing this
# file does not stack up duplicates.
for __d in "$HOME/.fzf/bin" "$HOME/.local/share/nvim/mason/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$__d:"*) ;;
        *) PATH="$__d:$PATH" ;;
    esac
done
unset __d
export PATH

# ---------------------------------------------------------------------------
#  Aliases  (kept in sync with bashrc)
#
#  The modern replacements are only aliased when they are actually installed;
#  yay-apps.txt pulls them in, but the package step is optional.
# ---------------------------------------------------------------------------
# rsync shows progress and resumes where cp cannot.
__dot_have rsync && alias cp='rsync -avh --progress'

if __dot_have eza; then
    alias ls='eza --group-directories-first'
    alias ll='eza -lah --group-directories-first --git'
    alias la='eza -a --group-directories-first'
    alias lt='eza --tree --level=2 --group-directories-first'
else
    alias ls='ls --color=auto'
    alias ll='ls -lah --color=auto'
    alias la='ls -A --color=auto'
fi

__dot_have bat  && alias cat='bat --paging=never'
__dot_have btop && alias htop='btop'
__dot_have nvim && { alias v='nvim'; alias vi='nvim'; }
__dot_have lazygit    && alias lg='lazygit'
__dot_have lazydocker && alias lzd='lazydocker'
# podman-tui is the closest thing podman has to lazydocker; lazydocker itself
# also works against podman once DOCKER_HOST points at the podman socket.
__dot_have podman-tui && alias lzp='podman-tui'
# The superfile package installs its binary as `spf`; alias the long name so
# both work.
__dot_have spf && alias superfile='spf'

alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias mv='mv -i'
alias rm='rm -i'
alias df='df -h'
alias du='du -h'
alias free='free -h'

alias gs='git status -sb'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate --all'
alias ..='cd ..'
alias ...='cd ../..'

# ---------------------------------------------------------------------------
#  fzf
#
#  ~/.fzf.bash - which bashrc sources, and which setup-dotFiles.sh installs
#  from fzf.bash in this repository - is bash syntax and cannot be sourced by
#  zsh. What follows is the zsh half of the same configuration, taken from the
#  container's .zshrc so that both environments behave identically.
#
#  The preview commands are the container's, with a plain fallback appended:
#  the image is built with bat and eza inside it, a host may not have them,
#  and a preview pane full of "command not found" is worse than a plain one.
# ---------------------------------------------------------------------------
if __dot_have fd; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
elif __dot_have rg; then
    export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
fi
export FZF_CTRL_T_COMMAND="${FZF_DEFAULT_COMMAND:-}"
export FZF_DEFAULT_OPTS="
  --height=60% --layout=reverse --border=rounded --info=inline
  --marker='+' --pointer='>' --prompt='  '
  --bind='ctrl-/:toggle-preview,ctrl-a:select-all,ctrl-y:execute-silent(echo {+} | wl-copy 2>/dev/null || echo {+} | xclip -sel clip)'
"
export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range=:200 {} 2>/dev/null || eza --tree --level=2 --color=always {} 2>/dev/null || cat {} 2>/dev/null || ls -la {}' --preview-window=right:60%:wrap"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {} 2>/dev/null || ls -la {}' --preview-window=right:60%"
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window=down:3:hidden:wrap --bind='?:toggle-preview'"

# Arch ships the shell integration as plain files; fzf 0.48 and newer can emit
# it itself, and the standalone installer drops it in ~/.fzf/shell.
if [ -f /usr/share/fzf/key-bindings.zsh ]; then
    source /usr/share/fzf/key-bindings.zsh
    [ -f /usr/share/fzf/completion.zsh ] && source /usr/share/fzf/completion.zsh
elif [ -f "$HOME/.fzf/shell/key-bindings.zsh" ]; then
    source "$HOME/.fzf/shell/key-bindings.zsh"
    [ -f "$HOME/.fzf/shell/completion.zsh" ] && source "$HOME/.fzf/shell/completion.zsh"
elif __dot_have fzf && fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
fi

# fzf-tab: use a preview pane for file and directory completion. These styles
# are inert when the plugin is not installed, so they need no guard.
zstyle ':fzf-tab:complete:cd:*' fzf-preview \
    'eza --tree --level=2 --color=always $realpath 2>/dev/null || ls -la $realpath'
zstyle ':fzf-tab:complete:*:*' fzf-preview \
    '[ -d $realpath ] && { eza --tree --level=2 --color=always $realpath 2>/dev/null || ls -la $realpath; } || { bat --style=numbers --color=always --line-range=:200 $realpath 2>/dev/null || cat $realpath; }'
zstyle ':fzf-tab:*' switch-group ',' '.'

# The same helper functions the container provides. They are defined only when
# fzf is installed, and they test for fd and bat at call time because
# __dot_have no longer exists by then.
if __dot_have fzf; then
    # fe - pick one or more files and open them in $EDITOR
    fe() {
        local files
        files=("${(@f)$(fzf --multi --query="${1:-}" \
            --preview 'bat --style=numbers --color=always --line-range=:200 {} 2>/dev/null || cat {}')}")
        [ -n "$files" ] && "${EDITOR:-vi}" "${files[@]}"
    }
    # fcd - jump to a directory
    fcd() {
        local dir
        if command -v fd >/dev/null 2>&1; then
            dir=$(fd --type d --hidden --follow --exclude .git . "${1:-.}" | fzf +m)
        else
            dir=$(find "${1:-.}" -type d 2>/dev/null | fzf +m)
        fi
        [ -n "$dir" ] && cd -- "$dir"
    }
    # fkill - pick a process to kill
    fkill() {
        local pid
        pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
        [ -n "$pid" ] && echo "$pid" | xargs kill "-${1:-9}"
    }
    # fgb - check out a git branch
    fgb() {
        local branch
        branch=$(git branch --all | grep -v HEAD | sed 's/^..//;s#remotes/[^/]*/##' | sort -u | fzf +m) \
            && git checkout "$branch"
    }
fi

# ---------------------------------------------------------------------------
#  Greeting  (set DOTFILES_NO_FETCH=1 to silence it)
#
#  The _SHOWN guard stops it firing again in every nested shell - tmux panes,
#  su, a subshell - which is what makes an unguarded fetch call so tiresome.
#  neofetch was archived by its author in 2024, hence the fastfetch first.
# ---------------------------------------------------------------------------
if [ -z "${DOTFILES_NO_FETCH:-}" ] && [ -t 1 ] && [ -z "${DOTFILES_FETCH_SHOWN:-}" ]; then
    export DOTFILES_FETCH_SHOWN=1
    if __dot_have fastfetch; then
        fastfetch
    elif __dot_have neofetch; then
        neofetch
    fi
fi

unset -f __dot_have

# ---------------------------------------------------------------------------
#  Local overrides - yours, never touched by a reinstall
# ---------------------------------------------------------------------------
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
