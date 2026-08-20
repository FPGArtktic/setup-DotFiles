# ===========================================================================
#  setup-DotFiles :: bash configuration
#
#  Installed by setup-dotFiles.sh and sourced from ~/.bashrc.
#
#  This runs on a REAL machine, not inside an image whose contents we control,
#  so every alias and integration that depends on a tool which may not be
#  installed is guarded. A dotfile that prints "command not found" on every new
#  terminal is worse than no dotfile.
#
#  Put your own additions in ~/.bashrc.local - this file is overwritten when
#  the dotfiles are reinstalled, that one never is.
# ===========================================================================

# Only interactive shells from here on. Without this guard the prompt work and
# the greeting below would also run for scp/rsync/sftp sessions, and any byte
# written to stdout during a non-interactive session corrupts the protocol
# those tools speak.
case $- in
    *i*) ;;
      *) return;;
esac

# Local helper, removed again at the bottom so it does not leak into the shell.
__dot_have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
#  History - unlimited, shared between terminals, timestamped
# ---------------------------------------------------------------------------
HISTFILE="$HOME/.bash_history"
HISTSIZE=-1                       # unlimited in memory
HISTFILESIZE=-1                   # unlimited on disk
HISTCONTROL=ignoreboth            # skip duplicates and space-prefixed commands
HISTTIMEFORMAT='%F %T '           # YYYY-MM-DD HH:MM:SS in front of every entry
HISTIGNORE='ls:ll:la:cd:pwd:exit:clear:history'

shopt -s histappend               # append, never truncate
shopt -s cmdhist                  # a multi-line command is one history entry
shopt -s checkwinsize             # keep $LINES/$COLUMNS right after a resize
shopt -s globstar 2>/dev/null     # ** matches across directories
shopt -s autocd 2>/dev/null       # "somedir" alone means "cd somedir"

# Flush after every command so a second terminal sees what this one just ran,
# and nothing is lost if the session dies. Prepending rather than assigning
# keeps whatever the distribution already put in PROMPT_COMMAND.
case "$PROMPT_COMMAND" in
    *'history -a'*) ;;
    '')  PROMPT_COMMAND='history -a' ;;
    *)   PROMPT_COMMAND="history -a; $PROMPT_COMMAND" ;;
esac

# ---------------------------------------------------------------------------
#  Prompt
#
#  time, user, host, abbreviated path, git branch on its own line.
#
#  Every colour escape MUST sit inside a \[ ... \] pair. Bash turns \[ into
#  \001 and \] into \002 so readline knows which bytes take up no width. An
#  unmatched \] is emitted to the terminal as a literal \002 (^B) byte and,
#  worse, throws off the width bookkeeping that decides where a long command
#  line wraps. Measured on a real pty: an earlier version of this file, whose
#  HOST, TIME and BRANCH each opened with a bare \033, wrote 4 stray ^B bytes
#  on every prompt draw. The pairs below are balanced - it writes none.
# ---------------------------------------------------------------------------
git_branch() { git branch 2>/dev/null | sed -e "/^[^*]/d" -e "s/* \(.*\)/\1/"; }

# Containers and some login paths leave USER empty, which would silently
# relabel every prompt as root.
if [ -z "${USER:-}" ]; then
    USER="$(id -un 2>/dev/null || echo root)"
fi

__ps1_time='\[\033[01;31m\]\t \[\033[01;32m\]'
__ps1_host=' \[\033[02;36m\]\h'
# Long paths collapse to  /a/b/c/_/y/z  instead of pushing the prompt off screen.
__ps1_location='\[\033[01;33m\]`pwd | sed "s#\(/[^/]\{1,\}/[^/]\{1,\}/[^/]\{1,\}/\).*\(/[^/]\{1,\}/[^/]\{1,\}\)/\{0,1\}#\1_\2#g"`\[\033[00m\]'
__ps1_branch=' \[\033[00;33m\]$(git_branch)\[\033[00m\]\n$ '

PS1="${__ps1_time}${USER}${__ps1_host}${__ps1_location}${__ps1_branch}"
PS2='\[\033[01;36m\]>\[\033[00m\] '

# ---------------------------------------------------------------------------
#  Environment
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

case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH

# ---------------------------------------------------------------------------
#  Aliases
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
__dot_have lazygit   && alias lg='lazygit'
__dot_have lazydocker && alias lzd='lazydocker'
# podman-tui is the closest thing podman has to lazydocker; lazydocker itself
# also works against podman once DOCKER_HOST points at the podman socket.
__dot_have podman-tui && alias lzp='podman-tui'

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
#  The full option set lives in ~/.fzf.bash, which setup-dotFiles.sh installs
#  from fzf.bash in this repository. Sourcing it here rather than duplicating
#  the settings keeps one copy of the truth.
# ---------------------------------------------------------------------------
[ -f "$HOME/.fzf.bash" ] && source "$HOME/.fzf.bash"

# ---------------------------------------------------------------------------
#  Completion
# ---------------------------------------------------------------------------
if ! shopt -oq posix; then
    [ -f /usr/share/bash-completion/bash_completion ] && \
        source /usr/share/bash-completion/bash_completion
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
[ -f "$HOME/.bashrc.local" ] && source "$HOME/.bashrc.local"
