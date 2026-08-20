# ===========================================================================
#  setup-DotFiles :: bash login-shell configuration
#
#  Installed by setup-dotFiles.sh as ~/.bash_profile. In the podman_base work
#  container this file is two lines - it can be, because the image controls
#  every file in the home directory. On a real machine the distribution and
#  the user may already have put something in ~/.profile or ~/.bash_login, so
#  the same two lines need a little care around them.
#
#  LOGIN VERSUS NON-LOGIN - the distinction everybody gets wrong:
#
#    * A LOGIN shell (a text console login, `ssh host`, `su -`, `bash -l`, and
#      on many systems the very first shell of a graphical session) reads
#      /etc/profile and then THE FIRST of ~/.bash_profile, ~/.bash_login,
#      ~/.profile that exists - and stops there. It does NOT read ~/.bashrc.
#    * A NON-LOGIN interactive shell (every terminal window opened inside an
#      already running desktop session, every new tmux pane, every `bash`
#      typed at a prompt) reads ~/.bashrc and nothing else.
#
#  So the prompt, aliases, history settings and PATH additions in ~/.bashrc
#  are invisible to a login shell unless this file pulls them in. That is the
#  one job it has, and the reason an SSH session so often looks nothing like
#  the terminal on the desktop.
#
#  Two consequences of "the first that exists, and stops there":
#
#    1. Creating this file shadows ~/.bash_login and ~/.profile. Whatever the
#       distribution or the user put there - PATH entries, locale, XDG
#       variables, a proxy - would silently stop being read. Hence the loop
#       below, which sources the file bash WOULD have read, in bash's own
#       order, before handing over to ~/.bashrc.
#    2. A ~/.profile that ends with "source ~/.bashrc" (Debian's default does
#       exactly that) then means ~/.bashrc is read twice. That is harmless:
#       everything in this repository's bashrc is written to be idempotent -
#       PATH entries are case-guarded, PROMPT_COMMAND is only extended when it
#       does not already contain `history -a`, aliases are plain assignments,
#       and the greeting is suppressed by the exported DOTFILES_FETCH_SHOWN.
#
#  This file must stay silent: it also runs for non-interactive login shells
#  such as `bash -lc ...` and `ssh host command`, where any byte written to
#  stdout corrupts what scp, rsync and sftp are speaking. ~/.bashrc returns
#  early for those, and nothing here prints.
# ===========================================================================

# Re-entry guard. A hand-written ~/.profile that sources ~/.bash_profile back
# would otherwise recurse until bash runs out of stack. Deliberately not
# exported - a nested `bash -l` is a new process and must run this file in
# full - and unset again at the end, so re-sourcing it by hand still works.
if [ -n "${DOTFILES_BASH_PROFILE:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
DOTFILES_BASH_PROFILE=1

# The file bash would have read had this one not existed, in bash's order:
# ~/.bash_login first, then ~/.profile, and only the first of the two.
for __dot_prev in "$HOME/.bash_login" "$HOME/.profile"; do
    if [ -f "$__dot_prev" ]; then
        . "$__dot_prev"
        break
    fi
done
unset __dot_prev

# The actual point of the file: give the login shell the same configuration
# every other terminal gets.
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"

unset DOTFILES_BASH_PROFILE
