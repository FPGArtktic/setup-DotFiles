#!/usr/bin/env bash
# ===========================================================================
#  setup-dotFiles - post-install setup for a fresh Arch Linux workstation
#  Author: Mateusz Okulanis
#  Email:  FPGArtktic@outlook.com
#  License: GPLv3 or later
#
#  The script walks through the setup in a fixed order and asks a Y/n
#  question before every step, so a run can be steered one answer at a time:
#
#      ./setup-dotFiles.sh                 # ask about every step
#      ./setup-dotFiles.sh --dry-run       # print what would happen, change nothing
#      ./setup-dotFiles.sh --yes           # answer yes to everything, ask nothing
#      ./setup-dotFiles.sh --dry-run --yes # full unattended rehearsal
#      ./setup-dotFiles.sh --yes --chsh    # unattended, zsh as the login shell
#
#  Every step is idempotent: running the script twice must leave the machine
#  in the same state as running it once. Run `./setup-dotFiles.sh --help` for
#  the full option reference.
#
#  The shell files are not pasted into ~/.bashrc and ~/.zshrc. Each one is
#  installed as a file of its own under ~/.config/setup-dotfiles/ and hooked
#  in with a single guarded source line, so a reinstall UPDATES the
#  configuration instead of appending another copy of it. ~/.bashrc.local and
#  ~/.zshrc.local stay yours and are never written to.
#
# Copyright (C) 2025 Mateusz Okulanis
# Email: FPGArtktic@outlook.com
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# ===========================================================================

set -euo pipefail

SCRIPT_VERSION="2.1.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"

# --- identity of the machine we are running on RIGHT NOW ---------------------
# $USER is not set under cron, `su`, `env -i` or some container shells, and an
# empty expansion would silently turn `usermod -aG docker $USER` into a
# missing-operand error. id -un always answers.
USER_NAME="${USER:-$(id -un)}"

# Every step writes into $HOME. Under `set -u` an unset HOME would abort with
# a bare "unbound variable" halfway through the constants below, so resolve it
# from passwd instead and say so plainly if even that fails. The output
# helpers are not defined yet, hence the raw printf.
if [ -z "${HOME:-}" ]; then
    HOME="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
    if [ -z "$HOME" ]; then
        printf 'setup-dotFiles.sh: HOME is not set and cannot be resolved\n' >&2
        exit 1
    fi
    export HOME
fi

# --- data files, always resolved against the script, never against $PWD ------
# The old version used ./bashrc and yay-apps.txt, so running the script from
# anywhere but the checkout quietly did nothing useful.
BASHRC_SRC="$SCRIPT_DIR/bashrc"
ZSHRC_SRC="$SCRIPT_DIR/zshrc"
BASH_PROFILE_SRC="$SCRIPT_DIR/bash_profile"
FZF_SRC="$SCRIPT_DIR/fzf.bash"
TMUX_SRC="$SCRIPT_DIR/tmux.conf"
NVIM_SRC="$SCRIPT_DIR/nvim"
PKG_LIST="$SCRIPT_DIR/yay-apps.txt"

# --- where the installed copies live -----------------------------------------
# XDG_CONFIG_HOME is honoured because Neovim honours it: reading the config
# from ~/.config/nvim while Neovim reads $XDG_CONFIG_HOME/nvim would install
# an editor configuration that never loads.
XDG_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

# The shell files are installed here, and ~/.bashrc, ~/.zshrc and
# ~/.bash_profile only get a one-line guarded `source` of them.
#
# The alternative - appending the whole file inside markers - works, but it
# means every reinstall rewrites the user's own rc file, a hand edit made
# inside the markers is silently lost, and `diff` against this repository is
# impossible. One file plus one line keeps our configuration and the user's
# strictly separate: the marker block never changes again after the first
# install, and updating the dotfiles is a plain file copy.
MANAGED_DIR="$XDG_CONFIG_DIR/setup-dotfiles"

# Neovim reads exactly one directory, and it is not negotiable.
NVIM_DEST="$XDG_CONFIG_DIR/nvim"

# Oh My Zsh, and the upstream repositories podman_base clones at build time.
# Same URLs, same layout - the difference is only that a host clones them at
# install time instead of baking them into an image.
OMZ_DIR="${ZSH:-$HOME/.oh-my-zsh}"
OMZ_REPO="https://github.com/ohmyzsh/ohmyzsh.git"
MTSH_REPO="https://github.com/FPGArtktic/ohmyzsh-mtsh-theme.git"
TPM_DIR="$HOME/.tmux/plugins/tpm"
TPM_REPO="https://github.com/tmux-plugins/tpm"

# The three zsh plugins that are not part of Oh My Zsh itself, in the order
# zshrc expects to find them. "name url" per entry, split on the first space.
declare -a OMZ_PLUGIN_REPOS=(
    "zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git"
    "zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git"
    "fzf-tab https://github.com/Aloxaf/fzf-tab.git"
)

# --- defaults ----------------------------------------------------------------
# Precedence is flags > environment > built-in default.
DRY_RUN=0
VERBOSE=0
ASSUME_YES="${ASSUME_YES:-0}"

# Changing the login shell is the one action here that can leave somebody
# staring at a shell that does not start. It is therefore never implied:
#   ask  - the default; the zsh step asks, and refuses to act under --yes
#   yes  - --chsh, the explicit consent an unattended run needs
#   no   - --no-chsh, do not even ask
CHSH_MODE="ask"

# The git identity is only a fallback. It is applied when the machine has no
# global identity at all; an identity that is already configured is never
# overwritten unless GIT_AUTHOR/GIT_EMAIL or --git-name/--git-email say so.
# This repository is public, and silently stamping the maintainer's name on a
# stranger's commits is not a feature.
GIT_AUTHOR_DEFAULT="Mateusz Okulanis"
GIT_EMAIL_DEFAULT="FPGArtktic@outlook.com"
GIT_AUTHOR="${GIT_AUTHOR:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

# Where the RAM disk symlink goes, and what it must point at.
RAMDISC_LINK="$HOME/RAMDISC"
RAMDISC_TARGET="/dev/shm"

# Marker template for the managed blocks in the rc files (see rc_block).
BLOCK_TAG="setup-dotFiles"

# Filled in by do_step, reported by summary.
declare -a STEPS_DONE=() STEPS_SKIPPED=() STEPS_FAILED=()
CURRENT_STEP=""

# Set once the sudo credential cache has been primed.
SUDO_PRIMED=0

# ===========================================================================
#  Output helpers
# ===========================================================================
# The test is on fd 2, not fd 1, because every diagnostic in this script goes
# to stderr; stdout is reserved for data a caller could pipe (--version).
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'; C_BLUE=$'\033[0;34m'; C_CYAN=$'\033[0;36m'
    C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
else
    C_RESET=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=; C_BOLD=; C_DIM=
fi

log()   { printf '%s==>%s %s\n'  "$C_BLUE"   "$C_RESET" "$*" >&2; }
step()  { printf '%s ->%s %s\n'  "$C_CYAN"   "$C_RESET" "$*" >&2; }
ok()    { printf '%s  ok%s %s\n' "$C_GREEN"  "$C_RESET" "$*" >&2; }
warn()  { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%serr %s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }
hint()  { printf '%s     %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }

# Only under --verbose. A plain `[ "$VERBOSE" = "1" ] && printf ...` would
# return 1 when quiet, which is fatal for a function called as the last
# statement of another one under `set -e`.
dbg() {
    if [ "$VERBOSE" = "1" ]; then
        printf '%s     %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2
    fi
    return 0
}

have() { command -v "$1" >/dev/null 2>&1; }

# Print a path the way a person writes it. Only for messages - never for a
# command, which always gets the real path.
tilde() {
    case "$1" in
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *)         printf '%s' "$1" ;;
    esac
}

# ===========================================================================
#  The two helpers every step is built from
# ===========================================================================

# confirm - the single question loop. It replaces the eleven copy-pasted
# `while true; do read -r answer ...` blocks the previous version carried;
# every fix to the prompt logic now has exactly one place to land.
#
#   confirm "Install the bashrc file?" y || return 0
#
# --yes is answered here and nowhere else: ASSUME_YES=1 means "do not ask",
# it never means "do not act" - which is precisely the inversion that made
# --yes skip the system update and the post-install step before.
confirm() {
    local prompt="$1" default="${2:-y}" reply
    if [ "$ASSUME_YES" = "1" ]; then
        dbg "auto-yes: $prompt"
        return 0
    fi
    # A closed stdin used to answer "yes" to everything: `read` failed, left
    # $answer empty, and empty meant "default, go ahead". Piping this script
    # into bash therefore ran the whole thing unattended. Refuse instead.
    if [ ! -t 0 ]; then
        err "no terminal to ask: $prompt"
        die "stdin is not a terminal - re-run with --yes to accept every step"
    fi
    while true; do
        if [ "$default" = "y" ]; then
            printf '%s%s%s [Y/n] ' "$C_BOLD" "$prompt" "$C_RESET" >&2
        else
            printf '%s%s%s [y/N] ' "$C_BOLD" "$prompt" "$C_RESET" >&2
        fi
        if ! IFS= read -r reply; then
            printf '\n' >&2
            die "no more input on stdin - re-run with --yes to accept every step"
        fi
        reply="${reply#"${reply%%[![:space:]]*}"}"   # strip leading blanks
        reply="${reply%"${reply##*[![:space:]]}"}"   # strip trailing blanks
        reply="${reply:-$default}"
        # The old anchored ^[Yy]$ / ^[Nn]$ tests rejected "yes" and "no",
        # which are the two answers people actually type.
        case "${reply,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     warn "please answer y (yes) or n (no)" ;;
        esac
    done
}

# run - the single gate every system-changing command passes through.
# Under --dry-run it prints the command and returns success; under --verbose
# it echoes the command before executing it. Nothing that mutates the machine
# may bypass this, and that is the whole reason --dry-run can be trusted.
# It takes an argv, never a string, so package names and paths cannot be
# re-split or glob-expanded on the way through.
run() {
    if [ "$DRY_RUN" = "1" ]; then
        printf '%sdry%s  would run: %s\n' "$C_YELLOW" "$C_RESET" "$(quoted "$@")" >&2
        return 0
    fi
    if [ "$VERBOSE" = "1" ]; then
        printf '%s   $%s %s\n' "$C_DIM" "$C_RESET" "$(quoted "$@")" >&2
    fi
    "$@"
}

# Render an argv the way it would have to be typed, so that a dry-run line can
# be copied straight into a shell: an argument with spaces in it is a single
# argument here and has to stay one there.
quoted() {
    local a out=""
    for a in "$@"; do
        case "$a" in
            *\'*)                     out+=" $(printf '%q' "$a")" ;;
            *[![:alnum:]_@%+=:,./-]*) out+=" '$a'" ;;
            *)                        out+=" $a" ;;
        esac
    done
    printf '%s' "${out# }"
}

# do_step - runs one step, records the outcome and never lets a single
# failure abort the rest of the run. The `if` context also means a step's
# internal failure cannot trip `set -e` on the way out; every step therefore
# checks its own commands and returns 1 deliberately.
#
# The label lives here and nowhere else, so the name in the summary cannot
# drift away from the name in main's list.
do_step() {
    local fn="$2"
    CURRENT_STEP="$1"
    if "$fn"; then
        return 0
    fi
    STEPS_FAILED+=("$CURRENT_STEP")
    warn "step '$CURRENT_STEP' failed - continuing with the remaining steps"
    return 0
}

# Called by a step that the user declined, or that has nothing left to do.
skipped()   { STEPS_SKIPPED+=("$CURRENT_STEP"); dbg "skipping $CURRENT_STEP"; return 0; }
completed() { STEPS_DONE+=("$CURRENT_STEP"); return 0; }

# ===========================================================================
#  Small utilities
# ===========================================================================

need_file() {
    if [ ! -f "$1" ]; then
        err "required file not found: $1"
        hint "run $SCRIPT_NAME from its own checkout, or restore the missing file"
        return 1
    fi
    return 0
}

# systemd is not running inside a container, so every `systemctl enable` in
# there fails with "Unit not found". Detect it once and degrade to a warning
# rather than reporting a failure the test environment cannot avoid.
in_container() {
    [ -f /run/.containerenv ] && return 0
    [ -f /.dockerenv ] && return 0
    grep -qa 'container=' /proc/1/environ 2>/dev/null && return 0
    return 1
}

have_systemd() {
    have systemctl && [ -d /run/systemd/system ]
}

# Ask for the sudo password once, at the moment the first privileged step
# needs it, instead of stopping halfway through a build to prompt.
ensure_sudo() {
    if [ "$DRY_RUN" = "1" ] || [ "$SUDO_PRIMED" = "1" ]; then
        return 0
    fi
    if ! have sudo; then
        err "sudo is not installed - this step needs root"
        return 1
    fi
    if ! sudo -v; then
        err "could not obtain sudo credentials"
        return 1
    fi
    SUDO_PRIMED=1
    return 0
}

# pacman/yay/makepkg keep asking their own questions even when this script has
# stopped asking, so --yes has to be passed down to them or an unattended run
# simply hangs at the first transaction.
noconfirm_args() {
    if [ "$ASSUME_YES" = "1" ]; then
        printf '%s\n' "--noconfirm"
    fi
}

# Copy a file into place, keeping one timestamped backup when the destination
# exists and differs. Idempotent: an identical destination is left alone, so a
# second run creates no second backup.
install_file() {
    local src="$1" dst="$2"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        dbg "$dst is already up to date"
        return 0
    fi
    if [ -e "$dst" ]; then
        local backup
        backup="$dst.bak.$(date +%Y%m%d-%H%M%S)"
        warn "$dst exists and differs - keeping a backup at $backup"
        run cp -p "$dst" "$backup" || return 1
    fi
    run cp "$src" "$dst"
}

# copy_if_changed - install one of our own files, no backup.
#
# Deliberately not install_file: the destinations this is used for
# ($MANAGED_DIR/*) are copies of files in this repository, so "backing them
# up" would only litter the directory with copies of the previous version of
# a file that git already keeps. User-written files go through install_file,
# which does keep a backup.
copy_if_changed() {
    local src="$1" dst="$2"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        dbg "$dst is already up to date"
        return 0
    fi
    run cp "$src" "$dst"
}

# source_line - the one line an rc file gets for a managed file.
#
# Written with $HOME rather than the expanded path, so the rc file still says
# what it means when it is read by a human, and `[ -f ]`-guarded so a removed
# managed file degrades to a plain shell instead of an error on every start.
# POSIX `.` rather than bash's `source`, because the same line is written into
# ~/.zshrc as well.
source_line() {
    local file="$1" shown="$1"
    case "$file" in
        "$HOME"/*) shown="\$HOME${file#"$HOME"}" ;;
    esac
    printf 'if [ -f "%s" ]; then . "%s"; fi\n' "$shown" "$shown"
}

# rc_block - install a named, delimited block in an rc file.
#
# This is what makes the shell steps idempotent. `cat ./bashrc >> ~/.bashrc`
# appended another copy of the whole fragment on every run; here an existing
# block with the same name is removed first, so the file ends up with exactly
# one, whether the script runs once or twenty times.
#
# The payload is an argument, not stdin. That keeps --dry-run honest in two
# ways: `run rc_block ...` prints the exact text that would be written, and no
# pipeline is built for a reader that a dry run never starts.
#
# The body is a subshell - note the ( ) instead of { } - so that the EXIT trap
# below belongs to it alone. A RETURN trap would stay installed after this
# function returned and fire again on every later function return, by which
# time $tmp is out of scope and `set -u` turns the cleanup into a fatal
# "unbound variable".
rc_block() (
    local target="$1" name="$2" payload="$3"
    local begin="# >>> $BLOCK_TAG: $name >>>"
    local end="# <<< $BLOCK_TAG: $name <<<"
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/setup-dotfiles-rc.XXXXXX")" || return 1
    trap 'rm -f "$tmp"' EXIT

    if [ -f "$target" ]; then
        # Keep one pristine copy of whatever was there before this script
        # first touched the file. The "no managed block yet" test is what
        # makes it pristine: without it the second block installed in the
        # same run would snapshot the first one.
        if ! grep -q "^# >>> $BLOCK_TAG: " "$target" && [ ! -f "$target.orig.$BLOCK_TAG" ]; then
            cp -p "$target" "$target.orig.$BLOCK_TAG" || return 1
        fi
        awk -v b="$begin" -v e="$end" '
            $0 == b { skip = 1 }
            skip == 0 { print }
            $0 == e { skip = 0 }
        ' "$target" > "$tmp" || return 1
    fi

    {
        printf '%s\n' "$begin"
        printf '%s\n' "$payload"
        printf '%s\n' "$end"
    } >> "$tmp" || return 1

    # Match the existing permissions rather than mktemp's 0600.
    if [ -f "$target" ]; then
        chmod --reference="$target" "$tmp" 2>/dev/null || chmod 644 "$tmp"
    else
        chmod 644 "$tmp"
    fi
    mv -f "$tmp" "$target"
)

# rc_block_drop - remove a block this script installed earlier and leave the
# rest of the file untouched. Needed whenever a block stops being the right
# way to do something: without it an upgraded script installs the new
# mechanism while the old block keeps doing the old thing forever.
rc_block_drop() (
    local target="$1" name="$2"
    local begin="# >>> $BLOCK_TAG: $name >>>"
    local end="# <<< $BLOCK_TAG: $name <<<"
    local tmp
    [ -f "$target" ] || return 0
    grep -qxF "$begin" "$target" || return 0

    tmp="$(mktemp "${TMPDIR:-/tmp}/setup-dotfiles-rc.XXXXXX")" || return 1
    trap 'rm -f "$tmp"' EXIT
    awk -v b="$begin" -v e="$end" '
        $0 == b { skip = 1 }
        skip == 0 { print }
        $0 == e { skip = 0 }
    ' "$target" > "$tmp" || return 1
    chmod --reference="$target" "$tmp" 2>/dev/null || chmod 644 "$tmp"
    mv -f "$tmp" "$target"
)

# logged - run a very chatty command with its output captured, showing only
# the tail of it (all of it under --verbose, and more of it when the command
# failed, which is when it matters).
#
# Used as a prefix inside run(), the way one would write `run time cmd ...`,
# so a dry run still prints the real command line - `logged` in front of it is
# the honest description of what would happen. This exists for the Neovim
# bootstrap and the tmux plugin install: both write hundreds of progress lines
# that would bury every message this script prints.
logged() {
    local log rc=0
    log="$(mktemp "${TMPDIR:-/tmp}/setup-dotfiles-out.XXXXXX")" || return 1
    "$@" >"$log" 2>&1 || rc=$?
    if [ "$VERBOSE" = "1" ]; then
        sed 's/^/     /' "$log" >&2
    elif [ "$rc" -ne 0 ]; then
        tail -n 20 "$log" | sed 's/^/     /' >&2
    else
        tail -n 3 "$log" | sed 's/^/     /' >&2
    fi
    rm -f "$log"
    return "$rc"
}

# read_pkg_list - one package name per line, blank lines and #-comments
# dropped, duplicates dropped.
#
# `grep -v` exits 1 when it filters everything out, which under `pipefail`
# would abort the run on a comments-only list - hence the `|| true`. The
# result is consumed into an array, never interpolated as an unquoted
# $(cat ...) which the shell would happily glob-expand.
read_pkg_list() {
    local file="$1"
    need_file "$file" || return 1
    grep -vE '^[[:space:]]*(#|$)' "$file" | awk '!seen[$0]++' || true
}

# ===========================================================================
#  Usage, version, banner
# ===========================================================================
# There is exactly one usage function and exactly one name for it. The old
# code called a print_usage() that never existed, so --help printed a
# "command not found" and exited 0.
usage() {
    cat <<EOF
${C_BOLD}$SCRIPT_NAME${C_RESET} v$SCRIPT_VERSION - post-install setup for Arch Linux

  ${C_BOLD}usage:${C_RESET} $SCRIPT_NAME [options]

  --dry-run           print what would be done, change nothing
  -v, --verbose       show each command and each skipped step
  -y, --yes           answer yes to every question (implies non-interactive)
  --chsh              allow the zsh step to change your login shell
  --no-chsh           never offer to change your login shell
  --git-name NAME     global git user.name to configure
  --git-email ADDR    global git user.email to configure
  -V, --version       print the version and exit
  -h, --help          print this help and exit
  --                  end of options

The script asks before each step, so answering "n" is always an option; --yes
is for unattended runs. --dry-run and --yes combine into a full rehearsal that
touches nothing.

${C_BOLD}steps, in order${C_RESET}
  system update   full pacman -Syu plus base-devel and git
  bashrc          bashrc, sourced from ~/.bashrc
  bash profile    bash_profile, sourced from ~/.bash_profile
  yay             built from the AUR when it is not already installed
  packages        everything listed in yay-apps.txt
  zsh             zshrc, sourced from ~/.zshrc, plus Oh My Zsh,
                  zsh-autosuggestions, zsh-syntax-highlighting, fzf-tab and
                  the mtsh theme; offers to change the login shell
  ssh key         an ed25519 key, only when there is none
  docker          docker group membership and docker.service
  libvirt         libvirt group membership, libvirtd.socket and the
                  default guest network
  fzf             fzf.bash -> ~/.fzf.bash, plus the shell integration
  ram disk        ~/RAMDISC -> /dev/shm
  tmux            tmux.conf -> ~/.tmux.conf, plus tpm and its plugins
  neovim          nvim/ -> $(tilde "$NVIM_DEST"), then lazy.nvim, Mason, tree-sitter
  git rules       global user.name, user.email, core.fileMode
  tailscale       the package and tailscaled
  post-install    final upgrade and package-cache trim

${C_BOLD}how the shell files are installed${C_RESET}
bashrc, zshrc and bash_profile are copied to
  $(tilde "$MANAGED_DIR")/
and hooked into ~/.bashrc, ~/.zshrc and ~/.bash_profile with ONE guarded
source line each, between "# >>> $BLOCK_TAG: ... >>>" markers. A second run
rewrites the copy, not your rc file, so nothing is ever appended twice, and
the first version of your rc file is kept as <file>.orig.$BLOCK_TAG.
~/.bashrc.local and ~/.zshrc.local are sourced last by those files and are
never written to - put your own settings there.

${C_BOLD}the login shell${C_RESET}
--yes never changes it: an unattended run prints the chsh command and moves on.
Pass --chsh to allow the change, --no-chsh to not even be asked.

${C_BOLD}the neovim step needs the network${C_RESET}
It downloads every plugin, language server and tree-sitter parser - the same
set podman_base bakes into its image - and takes minutes on a fresh machine.
DOTFILES_BOOTSTRAP_TIMEOUT (milliseconds) bounds the wait; see nvim/README.md.

Environment: GIT_AUTHOR, GIT_EMAIL (same as the two git flags), NO_COLOR,
ASSUME_YES (same as --yes), XDG_CONFIG_HOME and ZDOTDIR are honoured.
Data files, all read from $SCRIPT_DIR:
  bashrc, zshrc, bash_profile, fzf.bash, tmux.conf, yay-apps.txt, nvim/
EOF
}
# Note: --script-gen-only was advertised by the previous usage() but was never
# parsed and never implemented - nothing in this script generates a script. It
# is dropped rather than faked.

version() {
    cat <<EOF
$SCRIPT_NAME $SCRIPT_VERSION
Copyright (C) 2025 Mateusz Okulanis
License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Written by Mateusz Okulanis.
EOF
}

welcome() {
    printf '%s%s v%s%s - post-install setup for Arch Linux\n' \
        "$C_BOLD" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$C_RESET" >&2
    printf '  repository ...... %s\n' "$SCRIPT_DIR" >&2
    printf '  user ............ %s (uid %s)\n' "$USER_NAME" "$(id -u)" >&2
    printf '  mode ............ %s\n' \
        "$([ "$DRY_RUN" = "1" ] && printf 'dry run' || printf 'live')" >&2
    printf '  questions ....... %s\n' \
        "$([ "$ASSUME_YES" = "1" ] && printf 'auto-yes' || printf 'interactive')" >&2
    printf '  login shell ..... %s\n' \
        "$(case "$CHSH_MODE" in
             yes) printf 'may be changed to zsh (--chsh)' ;;
             no)  printf 'left alone (--no-chsh)' ;;
             *)   printf 'asked about in the zsh step' ;;
           esac)" >&2
    hint "every step asks first; --help lists the options"
    return 0
}

# ===========================================================================
#  Argument parsing
# ===========================================================================
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)    DRY_RUN=1; shift ;;
            -v|--verbose) VERBOSE=1; shift ;;
            -y|--yes)     ASSUME_YES=1; shift ;;
            --chsh)       CHSH_MODE=yes; shift ;;
            --no-chsh)    CHSH_MODE=no; shift ;;
            --git-name)   GIT_AUTHOR="${2:?--git-name needs a name}"; shift 2 ;;
            --git-email)  GIT_EMAIL="${2:?--git-email needs an address}"; shift 2 ;;
            -V|--version) version; exit 0 ;;
            -h|--help)    usage; exit 0 ;;
            --)           shift; break ;;
            -*)           err "unknown option '$1' (try --help)"; usage >&2; exit 1 ;;
            *)            err "unexpected argument '$1' (this script takes options only)"
                          usage >&2; exit 1 ;;
        esac
    done
    if [ $# -gt 0 ]; then
        err "unexpected argument '$1' (this script takes options only)"
        usage >&2
        exit 1
    fi
    # The flags decide control flow; freezing them means a later assignment
    # cannot quietly turn a dry run into a live one.
    readonly DRY_RUN VERBOSE ASSUME_YES CHSH_MODE
}

# ===========================================================================
#  Preflight
# ===========================================================================
# Everything that makes the rest of the run pointless is checked here, once,
# with an actionable message. The previous version ran happily to completion
# on Ubuntu, as root, or from the wrong directory, and still exited 0.
preflight() {
    local problems=0

    # 4.4 is not arbitrary: expanding an empty array as "${arr[@]}" is an
    # "unbound variable" error under `set -u` before it, and the --noconfirm
    # arrays below are empty on every interactive run.
    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] ||
       { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 4 ]; }; then
        err "bash 4.4 or newer is required (found ${BASH_VERSION:-unknown})"
        problems=$((problems + 1))
    fi

    if [ "$(id -u)" -eq 0 ]; then
        err "do not run this script as root"
        hint "as root \$HOME is /root, so the dotfiles land in the wrong home,"
        hint "and makepkg refuses to build yay at all - run it as your user"
        problems=$((problems + 1))
    fi

    if have pacman; then
        ok "pacman found - Arch Linux family"
    else
        err "pacman not found - this branch targets Arch Linux only"
        hint "the apt-based versions live on the master/ubuntu*/debian branches"
        problems=$((problems + 1))
    fi

    if have sudo; then
        ok "sudo found"
    else
        err "sudo not found - the package steps cannot run"
        problems=$((problems + 1))
    fi

    local f missing=0 total=0
    for f in "$BASHRC_SRC" "$ZSHRC_SRC" "$BASH_PROFILE_SRC" "$FZF_SRC" \
             "$TMUX_SRC" "$PKG_LIST"; do
        total=$((total + 1))
        if [ ! -f "$f" ]; then
            warn "missing data file: $f"
            missing=$((missing + 1))
        fi
    done
    # nvim is a directory, not a file, and the editor step needs all of it.
    total=$((total + 1))
    if [ ! -d "$NVIM_SRC" ]; then
        warn "missing data directory: $NVIM_SRC"
        missing=$((missing + 1))
    fi
    if [ "$missing" -eq 0 ]; then
        ok "all $total data files present in $SCRIPT_DIR"
    else
        hint "the steps that need them will be reported as failures"
    fi

    if in_container; then
        warn "running inside a container - systemd steps will be skipped"
    fi

    if [ "$problems" -eq 0 ]; then
        ok "no blocking problems found"
        return 0
    fi
    err "$problems blocking problem(s) found"
    return 1
}

# ===========================================================================
#  Steps, in the order main runs them
# ===========================================================================

# 1. Full system upgrade plus the toolchain every later step depends on.
install_update_and_upgrade() {
    log "System update and build toolchain"
    confirm "Update the system and install the build toolchain?" y || { skipped; return 0; }
    ensure_sudo || return 1

    local -a nc=()
    mapfile -t nc < <(noconfirm_args)

    if ! run sudo pacman -Syu "${nc[@]}"; then
        err "pacman -Syu failed"
        return 1
    fi
    # base-devel and git are what makepkg needs later, so they get their own
    # transaction: a cosmetic extra that no longer exists in the repositories
    # must not be able to take the toolchain down with it.
    if ! run sudo pacman -S --needed "${nc[@]}" -- base-devel git; then
        err "could not install base-devel and git"
        return 1
    fi
    # neofetch was archived upstream and dropped from the Arch repositories,
    # so fastfetch is tried first and neither is fatal.
    run sudo pacman -S --needed "${nc[@]}" -- fastfetch \
        || warn "fastfetch not installed (cosmetic only, continuing)"

    ok "system updated"
    completed
}

# 2. The bash configuration: one file of our own, one line in ~/.bashrc.
install_bashrc() {
    log "Bash configuration"
    step "installs bashrc as $(tilde "$MANAGED_DIR")/bashrc"
    step "and adds one guarded source line to $(tilde "$HOME/.bashrc")"
    confirm "Install the bash configuration?" y || { skipped; return 0; }
    need_file "$BASHRC_SRC" || return 1

    if ! run mkdir -p "$MANAGED_DIR"; then
        err "could not create $MANAGED_DIR"
        return 1
    fi
    copy_if_changed "$BASHRC_SRC" "$MANAGED_DIR/bashrc" || {
        err "could not install $MANAGED_DIR/bashrc"
        return 1
    }

    # Version 2.0 of this script pasted the whole of bashrc into ~/.bashrc
    # inside a block named "dotfiles". Leaving it there would mean the old
    # copy and the new file both being read, so it goes first.
    run rc_block_drop "$HOME/.bashrc" dotfiles \
        || warn "could not remove the old inline bashrc block from $HOME/.bashrc"

    if ! run rc_block "$HOME/.bashrc" bashrc "$(source_line "$MANAGED_DIR/bashrc")"; then
        err "could not update $HOME/.bashrc"
        return 1
    fi
    ok "bash configuration installed"
    hint "your own additions belong in ~/.bashrc.local - it is sourced last"
    hint "and is never written to by this script"
    hint "run 'source ~/.bashrc' or open a new terminal to pick it up"
    completed
}

# 3. The bash LOGIN shell. ~/.bashrc alone is not enough: a console login,
#    `ssh host` and `su -` read ~/.bash_profile (or ~/.bash_login, or
#    ~/.profile - the first that exists) and never look at ~/.bashrc.
install_bash_profile() {
    local target="$HOME/.bash_profile"
    log "Bash login shell"
    step "installs bash_profile as $(tilde "$MANAGED_DIR")/bash_profile"
    step "and adds one guarded source line to $(tilde "$target")"
    hint "without it an ssh session gets none of the configuration above"
    confirm "Install the bash login-shell configuration?" y || { skipped; return 0; }
    need_file "$BASH_PROFILE_SRC" || return 1

    if ! run mkdir -p "$MANAGED_DIR"; then
        err "could not create $MANAGED_DIR"
        return 1
    fi
    copy_if_changed "$BASH_PROFILE_SRC" "$MANAGED_DIR/bash_profile" || {
        err "could not install $MANAGED_DIR/bash_profile"
        return 1
    }

    # An existing ~/.bash_profile is somebody's work and is never replaced:
    # our three lines are appended to it, so everything it did still happens.
    if [ -f "$target" ] && ! grep -q "^# >>> $BLOCK_TAG: " "$target"; then
        warn "$target exists and was not written by this script"
        hint "it is kept as it is; the source line is appended at the end"
        hint "a pristine copy is saved as $target.orig.$BLOCK_TAG"
        # The managed file reads ~/.bash_login or ~/.profile as the fallback
        # bash would have used - which, with a hand-written ~/.bash_profile in
        # place, bash was NOT using. Worth saying out loud once.
        if [ -f "$HOME/.profile" ] || [ -f "$HOME/.bash_login" ]; then
            warn "~/.profile (or ~/.bash_login) will now be read as well"
            hint "it was shadowed by your ~/.bash_profile until now"
        fi
    fi

    if ! run rc_block "$target" bash_profile "$(source_line "$MANAGED_DIR/bash_profile")"; then
        err "could not update $target"
        return 1
    fi
    ok "bash login-shell configuration installed"
    # zsh needs no counterpart: it reads ~/.zshrc for every interactive shell,
    # login or not, so the zsh step below covers both cases on its own.
    completed
}

# 4. yay, built from the AUR - but only when it is not already there.
install_yay() {
    log "AUR helper"
    if have yay; then
        # Not `yay --version`: yay creates ~/.config/yay and ~/.cache/yay the
        # first time it is started for any reason, and a --dry-run that
        # creates two directories is a --dry-run nobody can trust. The package
        # database has the version and answering from it writes nothing.
        local yv
        yv="$(pacman -Qo "$(command -v yay)" 2>/dev/null | awk 'NF>=2 {print $(NF-1), $NF}' || true)"
        ok "yay is already installed${yv:+ ($yv)}"
        skipped
        return 0
    fi
    confirm "Build and install yay from the AUR?" y || { skipped; return 0; }
    ensure_sudo || return 1

    local -a nc=()
    mapfile -t nc < <(noconfirm_args)
    if ! run sudo pacman -S --needed "${nc[@]}" -- git base-devel; then
        err "could not install the build dependencies for yay"
        return 1
    fi

    step "clone https://aur.archlinux.org/yay-bin.git into a temporary directory and makepkg -si"
    if ! run yay_bootstrap; then
        err "building yay failed"
        return 1
    fi
    ok "yay installed"
    completed
}

# The whole yay build, so that --dry-run can skip it as a single unit and no
# temporary directory is created during a rehearsal.
#
# The previous version cloned into the *current* directory, leaving an
# untracked yay-bin/ inside the repository, then `cd yay-bin` unchecked - so a
# failed clone ran makepkg in the checkout and `cd -` moved every later step to
# an unrelated directory. A temp dir plus a subshell removes both hazards.
# Subshell body for the same reason as rc_block: the EXIT trap has to die
# with the function that set it.
yay_bootstrap() (
    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/setup-dotfiles-yay.XXXXXX")" || return 1
    trap 'rm -rf "$tmpdir"' EXIT

    local -a mk=(-si)
    if [ "$ASSUME_YES" = "1" ]; then
        mk+=(--noconfirm)
    fi

    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin" || return 1
    ( cd "$tmpdir/yay-bin" && makepkg "${mk[@]}" ) || return 1
    yay -Y --gendb || true
    yay -Y --devel --save || true
    return 0
)

# 5. The package list.
install_yay_packages() {
    log "Packages from yay-apps.txt"
    if ! have yay; then
        warn "yay is not installed - skipping the package list"
        hint "answer yes to the yay step, or install it yourself, then re-run"
        skipped
        return 0
    fi

    local -a pkgs=()
    mapfile -t pkgs < <(read_pkg_list "$PKG_LIST") || true
    if [ "${#pkgs[@]}" -eq 0 ]; then
        warn "no packages listed in $PKG_LIST"
        skipped
        return 0
    fi

    # Printing all seventy names here used to scroll the question itself off
    # a short terminal; the full list is one --verbose away.
    step "${#pkgs[@]} packages listed in $PKG_LIST"
    dbg "${pkgs[*]}"
    confirm "Install those ${#pkgs[@]} packages?" y || { skipped; return 0; }
    ensure_sudo || return 1

    local -a yflags=(-S --needed)
    if [ "$ASSUME_YES" = "1" ]; then
        yflags+=(--noconfirm --answerdiff None --answerclean All)
    fi

    if run yay "${yflags[@]}" -- "${pkgs[@]}"; then
        ok "packages installed"
        completed
        return 0
    fi

    # A single unknown name makes yay abort the entire transaction, which is
    # how two typos in the list used to prevent every package from installing.
    # Fall back to one transaction per package so the run still installs what
    # it can and can name the ones it could not.
    warn "the bulk install failed - retrying one package at a time"
    local p
    local -a bad=()
    for p in "${pkgs[@]}"; do
        run yay "${yflags[@]}" -- "$p" || bad+=("$p")
    done
    if [ "${#bad[@]}" -eq 0 ]; then
        ok "packages installed on the second pass"
        completed
        return 0
    fi
    err "${#bad[@]} package(s) could not be installed: ${bad[*]}"
    hint "check the names against the repositories and the AUR, then edit $PKG_LIST"
    return 1
}

# 6. zsh: the configuration, Oh My Zsh, the three custom plugins, the mtsh
#    theme, and - only if asked - the login shell.
#
#    podman_base clones exactly these repositories at build time
#    (Containerfile step 5) and then deletes Oh My Zsh's .git, because an
#    air-gapped image can never update it anyway. Here the same URLs are
#    cloned at install time and KEPT as git checkouts, so the
#    `zstyle ':omz:update' mode auto` in zshrc has something to update.
install_zsh() {
    log "Zsh configuration"
    step "installs zshrc as $(tilde "$MANAGED_DIR")/zshrc, sourced from ~/.zshrc"
    step "installs Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting,"
    step "fzf-tab and the mtsh theme into $(tilde "$OMZ_DIR")"
    confirm "Install the zsh configuration?" y || { skipped; return 0; }
    need_file "$ZSHRC_SRC" || return 1

    if ! have zsh; then
        warn "zsh is not installed - installing the configuration anyway"
        hint "zsh comes from $PKG_LIST; it will be used the moment zsh is there"
    fi

    # --- the configuration file itself ---------------------------------------
    if ! run mkdir -p "$MANAGED_DIR"; then
        err "could not create $MANAGED_DIR"
        return 1
    fi
    copy_if_changed "$ZSHRC_SRC" "$MANAGED_DIR/zshrc" || {
        err "could not install $MANAGED_DIR/zshrc"
        return 1
    }

    # ZDOTDIR, when set, is where zsh looks for .zshrc; writing to ~/.zshrc
    # would then configure a file zsh never reads.
    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
    if [ -f "$zshrc" ] && ! grep -q "^# >>> $BLOCK_TAG: " "$zshrc" \
       && grep -q 'oh-my-zsh' "$zshrc"; then
        warn "$zshrc already loads Oh My Zsh, and the managed file loads it too"
        hint "a pristine copy is kept as $zshrc.orig.$BLOCK_TAG"
        hint "trim yours if the prompt or the plugins come out doubled"
    fi
    if ! run rc_block "$zshrc" zshrc "$(source_line "$MANAGED_DIR/zshrc")"; then
        err "could not update $zshrc"
        return 1
    fi
    ok "zsh configuration installed"
    hint "your own additions belong in ~/.zshrc.local - it is sourced last"
    hint "and is never written to by this script"

    # --- Oh My Zsh and its plugins -------------------------------------------
    if ! have git; then
        warn "git is not installed - skipping Oh My Zsh, the plugins and the theme"
        hint "zshrc falls back to the stock theme and drops the missing plugins"
        completed
        return 0
    fi

    local failed=0
    if [ -d "$OMZ_DIR" ]; then
        # Oh My Zsh updates itself (zshrc sets `zstyle ':omz:update' mode
        # auto`), so pulling here would only duplicate that.
        ok "Oh My Zsh is already installed at $(tilde "$OMZ_DIR")"
    else
        step "cloning Oh My Zsh into $(tilde "$OMZ_DIR")"
        run git clone --depth 1 "$OMZ_REPO" "$OMZ_DIR" \
            || { err "could not clone Oh My Zsh"; failed=1; }
    fi

    # The stock installer is deliberately not used: it writes its own
    # ~/.zshrc from a template - overwriting the block installed above - and
    # runs chsh on its own. A plain clone is exactly what the Containerfile
    # does, and it changes nothing else.
    if [ "$failed" = "0" ]; then
        run mkdir -p "$OMZ_DIR/custom/plugins" || failed=1
    fi

    local entry name url dest
    for entry in "${OMZ_PLUGIN_REPOS[@]}"; do
        [ "$failed" = "0" ] || break
        name="${entry%% *}"
        url="${entry#* }"
        dest="$OMZ_DIR/custom/plugins/$name"
        if [ -d "$dest" ]; then
            ok "$name is already installed"
            continue
        fi
        step "cloning $name"
        run git clone --depth 1 "$url" "$dest" \
            || { err "could not clone $name"; failed=1; }
    done

    # Oh My Zsh loads a theme from a single .zsh-theme file in custom/themes,
    # and mtsh is distributed as a git repository - hence the clone into a
    # temporary directory and the copy of the one file out of it, which is
    # exactly what the Containerfile does.
    local theme="$OMZ_DIR/custom/themes/mtsh.zsh-theme"
    if [ "$failed" = "0" ]; then
        if [ -f "$theme" ]; then
            ok "the mtsh theme is already installed"
        else
            step "installing the mtsh theme from $MTSH_REPO"
            run mkdir -p "$OMZ_DIR/custom/themes" || failed=1
            if [ "$failed" = "0" ]; then
                run mtsh_bootstrap "$theme" || { err "could not install the mtsh theme"; failed=1; }
            fi
        fi
    fi

    if [ "$failed" != "0" ]; then
        err "the zsh environment is incomplete"
        hint "check the network and re-run this step; the login shell is left alone"
        return 1
    fi
    ok "Oh My Zsh, the three plugins and the mtsh theme are in place"
    hint "the mtsh theme needs a powerline font selected in your terminal emulator"

    # --- the login shell, which is the one thing that can lock somebody out --
    install_login_shell
    completed
}

# Clone the theme repository into a temporary directory and copy the single
# file Oh My Zsh wants out of it. A subshell for the same reason as
# yay_bootstrap: the EXIT trap has to die with the function that set it.
mtsh_bootstrap() (
    local dest="$1" tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/setup-dotfiles-mtsh.XXXXXX")" || return 1
    trap 'rm -rf "$tmpdir"' EXIT
    git clone --depth 1 "$MTSH_REPO" "$tmpdir/mtsh" || return 1
    cp "$tmpdir/mtsh/mtsh.zsh-theme" "$dest" || return 1
    return 0
)

# chsh, kept apart from everything else on purpose.
#
# Every other step in this script can be undone by deleting a file. This one
# decides which program greets you at the next login, and a zsh that fails to
# start - a syntax error in a plugin, a half-finished Oh My Zsh - is how a
# working terminal turns into a login loop. So it is never implied by --yes:
# an unattended run prints the command and moves on unless --chsh was given.
# It never fails the zsh step either; the configuration is already installed
# and works under `zsh` typed by hand.
install_login_shell() {
    local zsh_path cur_shell
    zsh_path="$(command -v zsh || true)"
    if [ -z "$zsh_path" ]; then
        dbg "zsh is not installed - not offering to change the login shell"
        return 0
    fi

    cur_shell="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f7 || true)"
    if [ "$cur_shell" = "$zsh_path" ]; then
        ok "zsh is already your login shell"
        return 0
    fi

    if [ "$CHSH_MODE" = "no" ]; then
        dbg "--no-chsh: leaving the login shell as $cur_shell"
        return 0
    fi

    log "Login shell"
    step "current login shell: ${cur_shell:-unknown}"
    step "candidate: $zsh_path"
    warn "this decides which shell every future login starts"
    hint "if zsh ever fails to start, log in and run: chsh -s ${cur_shell:-/bin/bash}"
    hint "or ask another user with sudo to run: sudo chsh -s ${cur_shell:-/bin/bash} $USER_NAME"

    # chsh refuses any shell that is not listed in /etc/shells, and its error
    # message does not say how to fix that.
    if [ -r /etc/shells ] && ! grep -qxF "$zsh_path" /etc/shells; then
        warn "$zsh_path is not listed in /etc/shells - chsh will refuse it"
        hint "add it with: echo $zsh_path | sudo tee -a /etc/shells"
        return 0
    fi

    if [ "$CHSH_MODE" != "yes" ] && [ "$ASSUME_YES" = "1" ]; then
        # confirm() would answer yes here, and "yes to everything" must not
        # quietly include "and change my login shell".
        warn "--yes does not change the login shell on its own"
        hint "re-run with --chsh to allow it, or do it yourself:"
        hint "  chsh -s $zsh_path"
        return 0
    fi
    if [ "$CHSH_MODE" != "yes" ]; then
        confirm "Make zsh your login shell?" n || {
            ok "login shell left as ${cur_shell:-unknown}"
            hint "start zsh by hand any time with: zsh"
            return 0
        }
    else
        warn "--chsh given: changing the login shell to $zsh_path"
    fi

    # Interactively chsh asks for the account password itself, which is what
    # should happen. Under --yes there is nobody to answer it, so the change
    # goes through sudo - whose credentials this script has already primed.
    if [ "$ASSUME_YES" = "1" ]; then
        ensure_sudo || { warn "no sudo credentials - login shell not changed"; return 0; }
        run sudo chsh -s "$zsh_path" "$USER_NAME" \
            || { warn "chsh failed - login shell not changed"; return 0; }
    else
        if ! run chsh -s "$zsh_path"; then
            warn "chsh failed - retrying through sudo"
            ensure_sudo || { warn "no sudo credentials - login shell not changed"; return 0; }
            run sudo chsh -s "$zsh_path" "$USER_NAME" \
                || { warn "chsh failed - login shell not changed"; return 0; }
        fi
    fi
    ok "login shell changed to $zsh_path"
    hint "it applies at your next login, not in this terminal"
    return 0
}

# 7. An SSH key - generated only when there is not one already.
install_sshkey() {
    local key="$HOME/.ssh/id_ed25519"
    log "SSH key"

    # Overwriting this file destroys access to every host and account the key
    # authenticates to, and ssh-keygen's own "Overwrite (y/n)?" arrives after
    # a run full of Y/n questions, exactly when a reflex "y" is most likely.
    # So the existence check happens here, and ssh-keygen is given an explicit
    # -f so it can never prompt for a path.
    if [ -f "$key" ]; then
        ok "an SSH key already exists at $key - leaving it alone"
        if [ -f "$key.pub" ]; then
            hint "public key: $(cat "$key.pub")"
        fi
        skipped
        return 0
    fi

    confirm "Generate an ed25519 SSH key?" y || { skipped; return 0; }

    local comment="${GIT_EMAIL:-$GIT_EMAIL_DEFAULT}"
    local -a args=(-t ed25519 -C "$comment" -f "$key")
    if [ "$ASSUME_YES" = "1" ]; then
        # ssh-keygen asks for a passphrase twice; an unattended run would hang
        # there forever. An empty passphrase is the price of --yes.
        args+=(-N "")
        warn "--yes: generating the key without a passphrase"
    fi

    run mkdir -p "$HOME/.ssh" || return 1
    run chmod 700 "$HOME/.ssh" || return 1
    if ! run ssh-keygen "${args[@]}"; then
        err "ssh-keygen failed"
        return 1
    fi
    ok "SSH key generated at $key"
    # These hints used to be hidden from --yes users, who are precisely the
    # ones with no chance of having read them during the run.
    hint "add the public key to GitHub: https://github.com/settings/keys"
    hint "load it into the agent with: ssh-add $key"
    if [ -f "$key.pub" ]; then
        hint "public key: $(cat "$key.pub")"
    fi
    completed
}

# 8. Docker group membership and the service.
install_docker_configuration() {
    log "Docker configuration"
    if ! have docker; then
        warn "docker is not installed - nothing to configure"
        hint "docker comes from $PKG_LIST; run the package step first"
        skipped
        return 0
    fi

    warn "membership of the docker group is equivalent to passwordless root"
    hint "anyone in it can mount / into a container and edit anything"
    confirm "Add $USER_NAME to the docker group and enable the service?" y \
        || { skipped; return 0; }
    ensure_sudo || return 1

    # groupadd returns 9 when the group exists, which under `set -e` would end
    # the run; the group is usually created by the docker package anyway.
    if getent group docker >/dev/null 2>&1; then
        dbg "group docker already exists"
    else
        run sudo groupadd docker || { err "groupadd docker failed"; return 1; }
    fi

    if id -nG "$USER_NAME" 2>/dev/null | grep -qw docker; then
        ok "$USER_NAME is already in the docker group"
    else
        run sudo usermod -aG docker "$USER_NAME" \
            || { err "could not add $USER_NAME to the docker group"; return 1; }
        warn "group membership only applies to new logins"
        hint "run 'newgrp docker' or log out and back in"
    fi

    if in_container || ! have_systemd; then
        warn "no systemd here - not enabling docker.service"
    else
        # docker.service pulls in containerd itself on Arch, so enabling
        # containerd separately is redundant.
        run sudo systemctl enable --now docker.service \
            || { err "could not enable docker.service"; return 1; }
        ok "docker.service enabled and started"
    fi
    completed
}

# 9. libvirt / KVM: group membership, the socket, and the default network.
#
# Replaces the VirtualBox step. The two are not configured the same way and the
# difference is worth stating: VirtualBox needed an out-of-tree module built by
# DKMS against every installed kernel, so its step was mostly about getting
# vboxdrv to exist. KVM is part of the kernel, so nothing is compiled and there
# is no module to chase - what has to be arranged instead is permission,
# a listening socket, and a network for the guests to sit on.
install_libvirt_configuration() {
    log "Virtualisation (libvirt / KVM)"

    if ! have virsh && ! getent group libvirt >/dev/null 2>&1; then
        warn "libvirt is not installed - nothing to configure"
        hint "libvirt, qemu-full and virt-manager come from $PKG_LIST"
        skipped
        return 0
    fi

    confirm "Configure libvirt for $USER_NAME?" y || { skipped; return 0; }
    ensure_sudo || return 1

    # --- 1. hardware -------------------------------------------------------
    # Without VT-x/AMD-V libvirt still runs, but every guest silently falls
    # back to TCG emulation and is perhaps twenty times slower. People report
    # that as "the VM is broken" rather than "virtualisation is off in the
    # firmware", so say it plainly here.
    if in_container; then
        hint "inside a container - not checking /dev/kvm or the kvm module"
    elif ! grep -Eq '\b(vmx|svm)\b' /proc/cpuinfo 2>/dev/null; then
        warn "no vmx/svm flag on this CPU - hardware virtualisation is off"
        hint "enable Intel VT-x or AMD-V in the firmware; without it guests"
        hint "fall back to slow software emulation"
    elif [ ! -c /dev/kvm ]; then
        warn "/dev/kvm is missing although the CPU supports virtualisation"
        hint "the kvm_intel or kvm_amd module is not loaded"
    else
        ok "hardware virtualisation available (/dev/kvm present)"
    fi

    # --- 2. permission -----------------------------------------------------
    # This is the whole of the access control, and it is worth knowing why:
    # /usr/share/polkit-1/rules.d/50-libvirt.rules, shipped by the libvirt
    # package, grants org.libvirt.unix.manage to members of the "libvirt"
    # group and to nobody else. No sudo, no editing libvirtd.conf, no
    # unix_sock_group - just the group.
    if ! getent group libvirt >/dev/null 2>&1; then
        err "group libvirt does not exist - is libvirt really installed?"
        return 1
    fi
    if id -nG "$USER_NAME" 2>/dev/null | grep -qw libvirt; then
        ok "$USER_NAME is already in the libvirt group"
    else
        run sudo usermod -aG libvirt "$USER_NAME" \
            || { err "could not add $USER_NAME to libvirt"; return 1; }
        warn "group membership only applies to new logins"
        hint "for this terminal only: newgrp libvirt"
    fi

    # --- 3. the daemon -----------------------------------------------------
    # Socket activation, not the service. libvirtd.socket starts libvirtd on
    # the first connection and stops caring afterwards; enabling the service
    # as well is the usual mistake, and it makes a daemon that would otherwise
    # be idle run from boot. The modular daemons (virtqemud, virtnetworkd and
    # friends) are the other supported layout - if you have deliberately
    # switched to those, this step will see libvirtd.socket disabled and say
    # so rather than fighting you for it.
    if in_container; then
        warn "inside a container - no systemd, skipping the libvirt socket"
    elif ! have systemctl; then
        warn "no systemctl - start libvirtd.socket however this system does it"
    elif systemctl is-active --quiet virtqemud.socket 2>/dev/null; then
        ok "the modular daemons are in use (virtqemud.socket is active)"
        hint "leaving libvirtd.socket alone"
    elif systemctl is-active --quiet libvirtd.socket 2>/dev/null; then
        ok "libvirtd.socket is already active"
    else
        run sudo systemctl enable --now libvirtd.socket \
            || { err "could not enable libvirtd.socket"; return 1; }
        ok "libvirtd.socket enabled and started"
    fi

    # --- 4. the default network --------------------------------------------
    # Shipped as inactive with autostart off. A guest created before this is
    # done comes up with no network at all, which reads as a guest fault. It
    # needs dnsmasq on the host; that is why dnsmasq is on the package list.
    if in_container || ! have virsh; then
        hint "skipping the default network"
    elif [ "$DRY_RUN" = "1" ]; then
        run virsh -c qemu:///system net-autostart default
        run virsh -c qemu:///system net-start default
    elif ! virsh -c qemu:///system net-info default >/dev/null 2>&1; then
        warn "libvirt has no network called 'default'"
        hint "it is defined on the daemon's first start; re-run this step,"
        hint "or define it from /usr/share/libvirt/networks/default.xml"
    else
        if [ "$(virsh -c qemu:///system net-info default 2>/dev/null \
                | awk '/^Autostart/ {print $2}')" = "yes" ]; then
            ok "the default network already autostarts"
        else
            run virsh -c qemu:///system net-autostart default \
                || warn "could not set the default network to autostart"
        fi
        if [ "$(virsh -c qemu:///system net-info default 2>/dev/null \
                | awk '/^Active/ {print $2}')" = "yes" ]; then
            ok "the default network is up (bridge virbr0)"
        else
            run virsh -c qemu:///system net-start default \
                || warn "could not start the default network - is dnsmasq installed?"
        fi
    fi

    ok "libvirt configuration applied"
    hint "virt-manager connects to qemu:///system; UEFI guests need edk2-ovmf"
    hint "and Windows 11 needs swtpm, both on the package list"
    completed
}

# 10. fzf.
install_fzf() {
    log "fzf"
    confirm "Install fzf and its shell integration?" y || { skipped; return 0; }
    need_file "$FZF_SRC" || return 1

    if have fzf; then
        # fzf is a normal [extra] package; when the package list already
        # installed it there is nothing to clone.
        ok "fzf is already installed - only refreshing the shell integration"
    elif [ -d "$HOME/.fzf" ]; then
        # The old unconditional clone failed here on every second run.
        ok "$HOME/.fzf already exists - updating it instead of cloning"
        run git -C "$HOME/.fzf" pull --ff-only \
            || warn "could not update $HOME/.fzf (local changes?), using it as is"
        # --no-update-rc: this repository ships its own fzf.bash, and letting
        # the installer append to ~/.bashrc as well made that file grow on
        # every run.
        run "$HOME/.fzf/install" --key-bindings --completion --no-update-rc \
            || { err "the fzf installer failed"; return 1; }
    else
        run git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf" \
            || { err "could not clone fzf"; return 1; }
        run "$HOME/.fzf/install" --key-bindings --completion --no-update-rc \
            || { err "the fzf installer failed"; return 1; }
    fi

    install_file "$FZF_SRC" "$HOME/.fzf.bash" || return 1

    # Installing ~/.fzf.bash is pointless unless something sources it. The
    # bashrc in this repository does that itself now, so the block earlier
    # versions added to ~/.bashrc would only source the same file twice - it
    # is removed when the managed bashrc is in place, and still written when
    # it is not, so declining the bash step does not silently disable fzf.
    if [ -f "$MANAGED_DIR/bashrc" ]; then
        run rc_block_drop "$HOME/.bashrc" fzf \
            || warn "could not remove the old fzf block from $HOME/.bashrc"
        dbg "the managed bashrc sources ~/.fzf.bash - no separate block needed"
    else
        run rc_block "$HOME/.bashrc" fzf "$(source_line "$HOME/.fzf.bash")" \
            || { err "could not add the fzf hook to ~/.bashrc"; return 1; }
    fi
    # zsh does not read ~/.fzf.bash at all - it is bash syntax. The zshrc in
    # this repository sources fzf's own zsh integration instead.
    ok "fzf configuration installed"
    completed
}

# 11. The RAM disk symlink.
install_ram_disk() {
    log "RAM disk shortcut"
    step "$RAMDISC_LINK -> $RAMDISC_TARGET (tmpfs, cleared on reboot)"
    confirm "Create the RAM disk shortcut?" y || { skipped; return 0; }

    # `ln -s /dev/shm/ ~/RAMDISC` with the link already in place creates the
    # new link *inside* the target, i.e. /dev/shm/shm -> /dev/shm/ - a
    # self-referential loop in a world-writable tmpfs. -n stops ln following
    # the existing symlink, and the check below means it is normally not even
    # reached.
    if [ -L "$RAMDISC_LINK" ]; then
        local current
        current="$(readlink -f "$RAMDISC_LINK" 2>/dev/null || true)"
        if [ "$current" = "$RAMDISC_TARGET" ]; then
            ok "$RAMDISC_LINK already points at $RAMDISC_TARGET"
            skipped
            return 0
        fi
        warn "$RAMDISC_LINK points at $current - repointing it"
    elif [ -e "$RAMDISC_LINK" ]; then
        err "$RAMDISC_LINK exists and is not a symlink - refusing to replace it"
        return 1
    fi

    run ln -sfn "$RAMDISC_TARGET" "$RAMDISC_LINK" || { err "could not create $RAMDISC_LINK"; return 1; }
    ok "$RAMDISC_LINK -> $RAMDISC_TARGET"
    completed
}

# 12. tmux, and the tpm plugins ~/.tmux.conf expects to find.
install_tmux() {
    log "tmux configuration"
    step "installs $TMUX_SRC as ~/.tmux.conf (existing file is backed up)"
    confirm "Install the tmux configuration?" y || { skipped; return 0; }
    need_file "$TMUX_SRC" || return 1

    install_file "$TMUX_SRC" "$HOME/.tmux.conf" || { err "could not install ~/.tmux.conf"; return 1; }
    ok "tmux configuration installed"
    if ! have tmux; then
        warn "tmux itself is not installed yet - the config waits for it"
        hint "tmux comes from $PKG_LIST"
    fi

    # ~/.tmux.conf clones tpm itself on first start, but only the first time a
    # tmux server starts and only if the machine has a network right then.
    # Doing it here instead means the plugins are already on disk, and the
    # if-shell in the config becomes the fallback it was meant to be.
    if ! have git; then
        warn "git is not installed - tpm will be cloned by ~/.tmux.conf on first start"
        completed
        return 0
    fi
    if [ -d "$TPM_DIR" ]; then
        ok "tpm is already installed at $(tilde "$TPM_DIR")"
        run git -C "$TPM_DIR" pull --ff-only \
            || warn "could not update tpm (local changes?), using it as is"
    else
        step "cloning tpm into $(tilde "$TPM_DIR")"
        run mkdir -p "$(dirname "$TPM_DIR")" || { err "could not create $(dirname "$TPM_DIR")"; return 1; }
        run git clone --depth 1 "$TPM_REPO" "$TPM_DIR" || { err "could not clone tpm"; return 1; }
    fi

    if have tmux; then
        step "installing tmux-sensible, tmux-resurrect and tmux-continuum"
        run logged tpm_install \
            || warn "tpm could not install the plugins now - press prefix + I (C-Space then I) inside tmux"
    fi
    ok "tmux plugins in place"
    hint "prefix is C-Space; prefix + I installs plugins, prefix + r reloads the config"
    completed
}

# tpm's installer drives a running tmux server: it asks tmux which @plugin
# lines the configuration declares. Started with no server anywhere it can
# exit without installing anything, so a throwaway detached session is created
# for the duration when there is nothing else to talk to. Subshell for the
# trap, as elsewhere.
tpm_install() (
    local session="setup-dotfiles-tpm" rc=0 started=0
    if [ -z "${TMUX:-}" ] && ! tmux has-session 2>/dev/null; then
        tmux new-session -d -s "$session" 'sleep 600' 2>/dev/null && started=1
        trap '[ "$started" = "1" ] && tmux kill-session -t "$session" 2>/dev/null; true' EXIT
    fi
    "$TPM_DIR/bin/install_plugins" || rc=$?
    return "$rc"
)

# 13. Neovim: the configuration tree, then everything it needs from the
#     network - plugins, language servers, tree-sitter parsers.
#
#     This is the step where "the host has internet" stops being a footnote.
#     podman_base bakes all of it into the image at build time because the
#     container can never fetch anything; here the very same lists are
#     fetched on the machine, once, by the very same commands.
install_neovim() {
    log "Neovim configuration"
    step "copies nvim/ to $(tilde "$NVIM_DEST")/"
    step "then downloads the plugins, LSP servers and tree-sitter parsers"
    confirm "Install the Neovim configuration?" y || { skipped; return 0; }

    if [ ! -d "$NVIM_SRC" ]; then
        err "required directory not found: $NVIM_SRC"
        hint "run $SCRIPT_NAME from its own checkout"
        return 1
    fi

    if nvim_tree_matches; then
        ok "$(tilde "$NVIM_DEST") already carries this configuration"
    else
        # An existing configuration is copied aside, never overwritten in
        # place: somebody's editor setup is worth more than the seconds the
        # copy takes. The install itself is an overlay (cp of our files ON TO
        # the directory) rather than a wipe, so a lua/plugins/my-plugins.lua
        # that this repository knows nothing about survives a reinstall.
        if [ -e "$NVIM_DEST" ]; then
            local backup="$NVIM_DEST.bak.$(date +%Y%m%d-%H%M%S)"
            warn "$(tilde "$NVIM_DEST") exists and differs - copying it to $(tilde "$backup")"
            run cp -a "$NVIM_DEST" "$backup" || { err "could not back up $NVIM_DEST"; return 1; }
        fi
        run mkdir -p "$NVIM_DEST" || { err "could not create $NVIM_DEST"; return 1; }
        run cp -a "$NVIM_SRC/." "$NVIM_DEST/" || { err "could not copy the Neovim tree"; return 1; }
        ok "Neovim configuration installed in $(tilde "$NVIM_DEST")"
    fi

    if ! have nvim; then
        warn "neovim is not installed - nothing to bootstrap"
        hint "neovim comes from $PKG_LIST; the configuration is already in place"
        hint "and installs itself the first time you start the editor"
        completed
        return 0
    fi

    warn "the next part downloads every plugin, language server and parser"
    hint "it needs a working internet connection and usually takes minutes"
    hint "answering n leaves it to the first 'nvim' you start by hand"
    confirm "Download the Neovim plugins, LSP servers and parsers now?" y || {
        ok "configuration installed; the editor will fetch the rest on first start"
        completed
        return 0
    }

    # Three passes, the same as the Containerfile, and for the same reason:
    # lua/plugins/dotfiles-extras.lua asks which LazyVim extras the INSTALLED
    # LazyVim actually has, so what the spec resolves to can change once
    # LazyVim is on disk. Measured on this configuration the first pass
    # already brought everything in (52 plugins, unchanged by passes two and
    # three), but the extra passes cost seconds on an up-to-date tree and are
    # what makes an interrupted first pass - a dropped connection halfway
    # through a hundred clones - converge instead of leaving gaps.
    local pass
    for pass in 1 2 3; do
        step "lazy.nvim sync, pass $pass of 3"
        if ! run logged nvim --headless "+Lazy! sync" +qa; then
            err "lazy.nvim sync failed on pass $pass"
            hint "check the network, then re-run this step or run :Lazy sync in the editor"
            return 1
        fi
    done

    # And why a separate script rather than -c "MasonInstall ...": `+Lazy!
    # sync` fires the Mason downloads and then quits, Mason kills them on the
    # way out ("Neovim is exiting while packages are still installing"), and
    # the run looks successful while leaving you with no language servers.
    # bootstrap.lua issues the same installs and BLOCKS until they finish. It
    # is run with -c luafile, not `nvim -l`, because -l skips init.lua and so
    # never loads lazy.nvim at all.
    # Tested on the source, not on the destination: under --dry-run the copy
    # above did not happen, and a check against $NVIM_DEST would report a
    # missing bootstrap.lua that is in fact sitting in the checkout.
    if [ -f "$NVIM_SRC/bootstrap.lua" ]; then
        step "Mason packages and tree-sitter parsers (this is the slow part)"
        run logged nvim --headless -c "luafile $NVIM_DEST/bootstrap.lua" \
            || warn "the Neovim bootstrap reported a problem - see :Mason and :checkhealth"
    else
        warn "nvim/bootstrap.lua is missing - the servers will install on first start instead"
    fi

    ok "Neovim is ready"
    hint "check it with: nvim +checkhealth, :Lazy, :Mason"
    completed
}

# True when every file this repository ships is already byte-identical in
# $NVIM_DEST. That is the idempotency test for the step: without it every run
# would take another timestamped backup of a configuration that never changed.
# Files the user added themselves are not consulted - they are none of our
# business, and they are exactly what the overlay copy is designed to keep.
nvim_tree_matches() {
    local f rel
    [ -d "$NVIM_DEST" ] || return 1
    while IFS= read -r f; do
        rel="${f#"$NVIM_SRC"/}"
        cmp -s "$f" "$NVIM_DEST/$rel" || return 1
    done < <(find "$NVIM_SRC" -type f)
    return 0
}

# 14. Global git configuration.
install_git_rules() {
    log "Global git configuration"
    if ! have git; then
        warn "git is not installed - skipping the git configuration"
        skipped
        return 0
    fi

    # git config --global --list exits 128 when there is no ~/.gitconfig at
    # all, which under `set -e` would end the run right here.
    local cur_name cur_email
    cur_name="$(git config --global user.name 2>/dev/null || true)"
    cur_email="$(git config --global user.email 2>/dev/null || true)"

    # flags/environment > what is already configured > the built-in default.
    local want_name="${GIT_AUTHOR:-${cur_name:-$GIT_AUTHOR_DEFAULT}}"
    local want_email="${GIT_EMAIL:-${cur_email:-$GIT_EMAIL_DEFAULT}}"

    step "user.name ....... $want_name"
    step "user.email ...... $want_email"
    step "core.fileMode ... false (global, for every repository on this machine)"

    if [ -n "$cur_name" ] && [ "$cur_name" != "$want_name" ]; then
        warn "this replaces the configured identity: $cur_name <$cur_email>"
        hint "pass --git-name/--git-email, or answer n to keep what you have"
    fi
    confirm "Apply this global git configuration?" y || { skipped; return 0; }

    local failed=0
    run git config --global core.fileMode false || failed=1
    run git config --global user.name "$want_name" || failed=1
    run git config --global user.email "$want_email" || failed=1
    if [ "$failed" = "1" ]; then
        err "at least one git config call failed"
        return 1
    fi
    ok "global git configuration applied"
    if [ "$VERBOSE" = "1" ]; then
        git config --global --list 2>/dev/null | sed 's/^/     /' >&2 || true
    fi
    completed
}

# 15. Tailscale.
install_tailscale() {
    log "Tailscale"
    # The upstream one-liner piped a remote script into a root shell and then
    # shelled out to pacman anyway; tailscale is a normal [extra] package, so
    # install it the same way as everything else on this branch.
    step "installs the tailscale package and enables tailscaled"
    confirm "Install Tailscale?" y || { skipped; return 0; }
    ensure_sudo || return 1

    local -a nc=()
    mapfile -t nc < <(noconfirm_args)
    if have tailscale; then
        ok "tailscale is already installed"
    elif ! run sudo pacman -S --needed "${nc[@]}" -- tailscale; then
        err "could not install tailscale"
        return 1
    fi

    if in_container || ! have_systemd; then
        warn "no systemd here - not enabling tailscaled"
    else
        run sudo systemctl enable --now tailscaled \
            || { err "could not enable tailscaled"; return 1; }
        ok "tailscaled enabled and started"
    fi
    # Installing tailscale does not connect it, and the old version never said so.
    hint "connect the machine with: sudo tailscale up"
    completed
}

# 16. Final upgrade and cache trim.
post_installation() {
    log "Post-installation"
    confirm "Run a final upgrade and trim the package cache?" y || { skipped; return 0; }
    ensure_sudo || return 1

    local -a nc=()
    mapfile -t nc < <(noconfirm_args)

    # yay -Syu already performs the full pacman upgrade, so only one of the
    # two runs; the old code did both and prompted twice.
    if have yay; then
        run yay -Syu "${nc[@]}" || { err "yay -Syu failed"; return 1; }
    else
        run sudo pacman -Syu "${nc[@]}" || { err "pacman -Syu failed"; return 1; }
    fi

    # Real cleanup, rather than a message claiming cleanup happened. Orphan
    # removal is deliberately left to the user: it is the one operation here
    # that can uninstall something wanted.
    if have paccache; then
        run sudo paccache -rk2 || warn "paccache failed (cache not trimmed)"
    else
        run sudo pacman -Sc --noconfirm || warn "could not trim the package cache"
    fi

    ok "post-installation finished"
    hint "review orphans with: pacman -Qtdq"
    hint "restart your terminal, or run 'source ~/.bashrc', to apply the changes"
    completed
}

# ===========================================================================
#  Summary
# ===========================================================================
summary() {
    printf '\n' >&2
    printf '%sSummary%s\n' "$C_BOLD" "$C_RESET" >&2
    printf '  completed ....... %s\n' "${STEPS_DONE[*]:-none}" >&2
    printf '  skipped ......... %s\n' "${STEPS_SKIPPED[*]:-none}" >&2
    printf '  failed .......... %s\n' "${STEPS_FAILED[*]:-none}" >&2
    if [ "$DRY_RUN" = "1" ]; then
        printf '\n' >&2
        warn "dry run - nothing on this machine was changed"
    fi
    if [ "${#STEPS_FAILED[@]}" -eq 0 ]; then
        ok "finished"
        return 0
    fi
    # The old script always exited 0, which made a broken run indistinguishable
    # from a good one in the container test environment.
    err "${#STEPS_FAILED[@]} step(s) failed"
    return 1
}

# ===========================================================================
#  main
# ===========================================================================
main() {
    parse_arguments "$@"

    # Ctrl-C during makepkg or a package transaction should say so, and use
    # the conventional 128+SIGINT exit status.
    trap 'printf "\n" >&2; err "interrupted"; exit 130' INT
    trap 'err "terminated"; exit 143' TERM

    welcome
    log "Preflight"
    preflight || die "refusing to continue"

    # The order is not decorative. The toolchain comes first because
    # everything after it needs git; the package list comes before zsh,
    # tmux and neovim because it is what installs zsh, tmux and neovim; and
    # the neovim step sits at the end because it is the one that downloads
    # for minutes - by then every quick change is already made.
    do_step "system update" install_update_and_upgrade
    do_step "bashrc"        install_bashrc
    do_step "bash profile"  install_bash_profile
    do_step "yay"           install_yay
    do_step "packages"      install_yay_packages
    do_step "zsh"           install_zsh
    do_step "ssh key"       install_sshkey
    do_step "docker"        install_docker_configuration
    do_step "libvirt"       install_libvirt_configuration
    do_step "fzf"           install_fzf
    do_step "ram disk"      install_ram_disk
    do_step "tmux"          install_tmux
    do_step "neovim"        install_neovim
    do_step "git rules"     install_git_rules
    do_step "tailscale"     install_tailscale
    do_step "post-install"  post_installation

    summary
}

main "$@"
