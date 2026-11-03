#!/usr/bin/env bash
# ===========================================================================
#  setup-dotFiles - post-install setup for a fresh Debian 13 (trixie) machine
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

SCRIPT_VERSION="3.0.0+trixie"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"

# --- identity of the machine we are running on RIGHT NOW ---------------------
# $USER is not set under cron, `su`, `env -i` or some container shells, and an
# empty expansion would silently turn `usermod -aG libvirt $USER` into a
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
# The old version used ./bashrc and apt-apps.txt, so running the script from
# anywhere but the checkout quietly did nothing useful.
BASHRC_SRC="$SCRIPT_DIR/bashrc"
ZSHRC_SRC="$SCRIPT_DIR/zshrc"
BASH_PROFILE_SRC="$SCRIPT_DIR/bash_profile"
TMUX_SRC="$SCRIPT_DIR/tmux.conf"
SHELL_SRC="$SCRIPT_DIR/shell"
BLERC_SRC="$SCRIPT_DIR/blerc"
INPUTRC_SRC="$SCRIPT_DIR/inputrc"
STARSHIP_SRC="$SCRIPT_DIR/starship.toml"
FASTFETCH_SRC="$SCRIPT_DIR/fastfetch/config.jsonc"
KONSOLE_SRC="$SCRIPT_DIR/konsole"
AUDIO_SRC="$SCRIPT_DIR/audio"
NVIM_SRC="$SCRIPT_DIR/nvim"
PKG_LIST="$SCRIPT_DIR/apt-apps.txt"

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

# env.sh, aliases.sh, functions.sh and fzf.sh, shared by bash and zsh. Both
# rc files read them from here; local.sh next to them is the user's own and
# is never overwritten.
SHELL_DEST="$XDG_CONFIG_DIR/shell"

# ble.sh, the readline replacement bashrc loads. Unpacked from the upstream
# nightly tarball: Debian has no package for it.
BLESH_DIR="$HOME/.local/share/blesh"
BLESH_URL="https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz"

# Programs Debian 13 ships too old for this configuration, taken from their
# upstream releases instead. LazyVim refuses to start on anything older than
# Neovim 0.11.2 (trixie has 0.10.4), and the nvim-treesitter main branch it
# uses compiles parsers with tree-sitter CLI 0.25 or newer (trixie has
# 0.22.6). Neovim goes to /opt with a link in /usr/local/bin - upstream's own
# recommendation - so root and sudoedit get the same editor as the user.
NVIM_MIN="0.11.2"
NVIM_REPO="neovim/neovim"
NVIM_ASSET="nvim-linux-x86_64.tar.gz"
NVIM_PREFIX="/opt/nvim-linux-x86_64"
TREESITTER_MIN="0.25.0"
TREESITTER_REPO="tree-sitter/tree-sitter"
TREESITTER_ASSET="tree-sitter-linux-x64.gz"
LOCAL_BIN_SYS="/usr/local/bin"

# The Nerd Font the Konsole profile, starship and eza --icons expect. Arch
# packages it (ttf-jetbrains-mono-nerd); Debian does not, so it is unpacked
# from the upstream release into the user's font directory.
NERDFONT_REPO="ryanoasis/nerd-fonts"
NERDFONT_ASSET="JetBrainsMono.tar.xz"
NERDFONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd"

# Debian renames two of the tools the shell files call: bat is installed as
# batcat and fd as fdfind, because both names were taken by older packages.
# A link in ~/.local/bin under the upstream name keeps bashrc, zshrc and
# shell/*.sh identical on both branches.
declare -a DEBIAN_SHIMS=("bat batcat" "fd fdfind")

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

# The zsh plugins that are not part of Oh My Zsh itself, in the order zshrc
# loads them. "name url" per entry, split on the first space. zshrc skips any
# that is missing, so a failed clone costs one feature, not the shell.
# zsh-completions is not here: Debian's zsh-common already ships them.
declare -a OMZ_PLUGIN_REPOS=(
    "fzf-tab https://github.com/Aloxaf/fzf-tab.git"
    "zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git"
    "fast-syntax-highlighting https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
    "zsh-history-substring-search https://github.com/zsh-users/zsh-history-substring-search.git"
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
# opt_value - the value of an option that takes one, or a hard stop.
#
# "${2:?...}" only fires when $2 is unset or empty, and the following option is
# neither. That made `--git-email --dry-run` set the address to "--dry-run" and
# then perform a LIVE run, with the mode line reading "live" in the middle of a
# rehearsal nobody wanted to be real. Anything starting with "-" is therefore
# rejected here; a value that genuinely starts with a dash can still be passed
# as `--git-name=-weird` style input, which this script does not accept anyway.
opt_value() {
    local flag="$1" value="${2-}"
    case "$value" in
        ''|-*)
            err "$flag needs a value (got '${value:-nothing}')"
            hint "did you mean:  $flag VALUE $value"
            return 1
            ;;
    esac
    printf '%s' "$value"
}

# ok_did - report a mutation that actually happened.
#
# Plain `ok` after a `run` is a lie during a rehearsal: --dry-run printed
# "would run: systemctl enable --now tailscaled" and then "ok
# tailscaled enabled and started", so the one thing the user came to check
# - what WOULD change - was reported as already done. Under --dry-run this
# says "would" instead, and the wording is the only difference.
ok_did() {
    if [ "$DRY_RUN" = "1" ]; then
        printf '%s dry%s would: %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
    else
        ok "$*"
    fi
}

quoted() {
    local a out=""
    for a in "$@"; do
        case "$a" in
            # An empty argument matches none of the "contains something
            # unusual" patterns below, so without this arm it would be
            # appended as nothing at all and the printed command line would
            # have one argument fewer than the real one. That matters most for
            # `ssh-keygen -N "" ...`, where a pasted line would make -f the
            # passphrase.
            '')                       out+=" ''" ;;
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

# apt_get - every apt-get call, through run() and sudo.
#
# apt-get keeps asking its own questions even when this script has stopped
# asking, so --yes has to be passed down or an unattended run simply hangs at
# the first "Do you want to continue?". -y alone is not enough: a debconf
# dialog or a "configuration file modified, keep yours?" prompt still stops
# it, hence the noninteractive frontend and --force-confold, which keeps the
# administrator's version of a changed configuration file - the answer that
# cannot break a running service. Interactively all of that is left to the
# person at the keyboard.
apt_get() {
    local -a cmd=(sudo)
    if [ "$ASSUME_YES" = "1" ]; then
        cmd+=(env DEBIAN_FRONTEND=noninteractive apt-get -y
              -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    else
        cmd+=(apt-get)
    fi
    run "${cmd[@]}" "$@"
}

# version_ge A B - is version A at least B? sort -V understands 0.11.2 vs
# 0.10.4 correctly, which a string comparison does not.
version_ge() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# The version a program reports, reduced to the first dotted number in it:
# "NVIM v0.12.6" -> 0.12.6, "tree-sitter 0.26.9 (abc)" -> 0.26.9.
tool_version() {
    "$@" 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true
}

# gh_fetch REPO ASSET DEST - download an asset of a project's latest GitHub
# release and check it against the sha256 digest GitHub publishes for it.
#
# The digest comes from the releases API over HTTPS, the file from the
# download URL; a mismatch means a truncated download or a tampered mirror,
# and either way the file is deleted rather than installed. Without jq the
# digest cannot be read and the download is refused - nothing from the
# network goes into /opt or /usr/local unchecked.
gh_fetch() {
    local repo="$1" asset="$2" dest="$3" want got
    have curl || { err "curl is not installed"; return 1; }
    have jq   || { err "jq is not installed - cannot verify $asset"; return 1; }
    want="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
            | jq -r --arg a "$asset" '.assets[] | select(.name == $a) | .digest // empty' \
            | sed 's/^sha256://')" || true
    if [ -z "$want" ]; then
        err "no sha256 digest published for $repo $asset"
        return 1
    fi
    curl -fL --retry 3 -o "$dest" \
        "https://github.com/$repo/releases/latest/download/$asset" || return 1
    got="$(sha256sum "$dest" | awk '{print $1}')"
    if [ "$got" != "$want" ]; then
        err "checksum mismatch for $asset (expected $want, got $got)"
        rm -f "$dest"
        return 1
    fi
    return 0
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

    # A symlinked destination is somebody's own dotfiles repository driving
    # this path. Plain `cp` follows the link and overwrites the file at the
    # far end - a tracked file in another repository, with the backup landing
    # next to the link rather than next to what was actually clobbered. Say
    # what is going on and replace the link instead, so the damage is confined
    # to this file and the original stays where its owner put it.
    if [ -L "$dst" ]; then
        local target
        target="$(readlink -f "$dst" 2>/dev/null || readlink "$dst")"
        warn "$dst is a symlink to $target"
        hint "replacing the link itself; $target is left untouched"
        hint "if that link is your own dotfiles repository, answer n next time"
        run rm -f "$dst" || return 1
        run cp "$src" "$dst"
        return
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

        # A begin marker with no matching end marker is the dangerous case:
        # the filter below would drop everything from the marker to the end of
        # the file, and the pristine-copy guard above does NOT fire, because a
        # managed marker IS present. Somebody who deleted the closing line by
        # hand would lose the rest of their rc file with no way back. Refuse
        # instead, and say exactly which line to look at.
        if grep -qxF "$begin" "$target" && ! grep -qxF "$end" "$target"; then
            err "$target has the opening marker of the '$name' block but not its end"
            hint "opening line: $begin"
            hint "expected end: $end"
            hint "restore the end line, or delete the opening one, then run again"
            return 1
        fi

        # Refuse a truncated file for the same reason: an end marker with no
        # begin cannot be matched up either.
        if grep -qxF "$end" "$target" && ! grep -qxF "$begin" "$target"; then
            err "$target has the end marker of the '$name' block but not its start"
            hint "delete the stray line: $end"
            return 1
        fi

        # Both markers present or neither: the filter is safe now. skip is
        # reset by the end marker, which the check above proved is there.
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

# usb_has - is a USB device with one of these vendor:product ids plugged in?
#
#   usb_has 0416:5302 0402:3922
#
# Read from sysfs rather than lsusb, which is in usbutils and not installed
# on a fresh system. Prints the first id that matched.
usb_has() {
    local d id want
    for d in /sys/bus/usb/devices/*; do
        [ -r "$d/idVendor" ] && [ -r "$d/idProduct" ] || continue
        id="$(cat "$d/idVendor"):$(cat "$d/idProduct")"
        for want in "$@"; do
            if [ "${id,,}" = "${want,,}" ]; then
                printf '%s\n' "$id"
                return 0
            fi
        done
    done
    return 1
}

# autostart_entry - an XDG autostart entry, written only when there is none,
# so an entry the user has edited (or disabled with Hidden=true) survives a
# reinstall.
autostart_entry() {
    local name="$1" exec_line="$2" comment="$3"
    local file="$XDG_CONFIG_DIR/autostart/$name.desktop"
    if [ -e "$file" ]; then
        ok "autostart entry $(tilde "$file") already exists - left alone"
        return 0
    fi
    run mkdir -p "$XDG_CONFIG_DIR/autostart" || return 1
    run write_file "$file" "[Desktop Entry]
Type=Application
Name=$name
Comment=$comment
Exec=$exec_line
Terminal=false
X-GNOME-Autostart-enabled=true
" || return 1
}

# write_file - put a string into a file. A function of its own so that it can
# go through run() and be shown, not done, under --dry-run.
write_file() {
    printf '%s' "$2" > "$1"
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
${C_BOLD}$SCRIPT_NAME${C_RESET} v$SCRIPT_VERSION - post-install setup for Debian 13 (trixie)

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
  system update   apt-get update + full-upgrade, plus build-essential, git,
                  curl and jq
  bashrc          bashrc, sourced from ~/.bashrc; shell/*.sh -> ~/.config/shell/,
                  blerc -> ~/.blerc, inputrc -> ~/.inputrc
  bash profile    bash_profile, sourced from ~/.bash_profile
  packages        everything listed in apt-apps.txt
  audio           PipeWire/WirePlumber profile, autoeq, m20-dropwatch
  zsh             zshrc, sourced from ~/.zshrc, plus Oh My Zsh, fzf-tab,
                  zsh-autosuggestions, fast-syntax-highlighting,
                  zsh-history-substring-search and the mtsh theme;
                  offers to change the login shell
  ssh key         an ed25519 key, only when there is none
  libvirt         libvirt group membership, libvirtd.socket and the
                  default guest network
  prompt          starship.toml, fastfetch config, ble.sh, the JetBrainsMono
                  Nerd Font, bat/fd links for batcat/fdfind, and the
                  command-not-found database
  konsole         Konsole profile (Nerd Font, Catppuccin Mocha) as default
  ram disk        ~/RAMDISC -> /dev/shm
  tmux            tmux.conf -> ~/.tmux.conf, plus tpm and its plugins
  neovim          Neovim >= $NVIM_MIN and tree-sitter >= $TREESITTER_MIN from upstream
                  (trixie ships older ones), nvim/ -> $(tilde "$NVIM_DEST"),
                  then lazy.nvim, Mason, tree-sitter parsers
  git rules       global user.name, user.email, core.fileMode
  tailscale       Tailscale's own apt repository, the package and tailscaled
  post-install    final upgrade and apt-get autoclean

${C_BOLD}how the shell files are installed${C_RESET}
bashrc, zshrc and bash_profile are copied to
  $(tilde "$MANAGED_DIR")/
and hooked into ~/.bashrc, ~/.zshrc and ~/.bash_profile with ONE guarded
source line each, between "# >>> $BLOCK_TAG: ... >>>" markers. A second run
rewrites the copy, not your rc file, so nothing is ever appended twice, and
the first version of your rc file is kept as <file>.orig.$BLOCK_TAG.
~/.config/shell/local.sh (both shells), ~/.bashrc.local and ~/.zshrc.local
are sourced last by those files and are never written to - put your own
settings there.

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
  bashrc, zshrc, bash_profile, shell/, blerc, inputrc, starship.toml,
  fastfetch/, konsole/, audio/, tmux.conf, apt-apps.txt, nvim/
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
    printf '%s%s v%s%s - post-install setup for Debian 13 (trixie)\n' \
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
            --git-name)   GIT_AUTHOR="$(opt_value "$1" "${2-}")" || exit 1; shift 2 ;;
            --git-email)  GIT_EMAIL="$(opt_value "$1" "${2-}")" || exit 1; shift 2 ;;
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
    # "unbound variable" error under `set -u` before it.
    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] ||
       { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 4 ]; }; then
        err "bash 4.4 or newer is required (found ${BASH_VERSION:-unknown})"
        problems=$((problems + 1))
    fi

    if [ "$(id -u)" -eq 0 ]; then
        err "do not run this script as root"
        hint "as root \$HOME is /root, so the dotfiles, the SSH key and the"
        hint "Oh My Zsh checkout would all land in the wrong home - run it as your user"
        problems=$((problems + 1))
    fi

    # Debian 13 is what the package list and the upstream-tool versions were
    # checked against. Another Debian release is a warning, not a refusal -
    # most names carry over - but anything without apt is not this branch.
    local os_id="" os_ver="" os_name=""
    if [ -r /etc/os-release ]; then
        os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
        os_ver="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
        os_name="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-}")"
    fi
    if ! have apt-get; then
        err "apt-get not found - this branch targets Debian 13 (trixie) only"
        hint "the Arch Linux version lives on the master branch"
        problems=$((problems + 1))
    elif [ "$os_id" = "debian" ] && [ "$os_ver" = "13" ]; then
        ok "$os_name"
    else
        warn "${os_name:-unknown system} is not Debian 13 (trixie)"
        hint "this branch is tested on trixie only; some package names may not resolve"
    fi

    # sudo exists on a fresh Debian, but an account created by the installer
    # while a root password was set is NOT in the sudo group - and finding
    # that out at the first package step, after the password prompt, helps
    # nobody. Membership is not the only way in (a sudoers.d rule works too),
    # so this is only a hint.
    if have sudo && ! id -nG "$USER_NAME" 2>/dev/null | grep -qw sudo; then
        warn "$USER_NAME is not in the sudo group"
        hint "unless a sudoers.d rule allows it, add yourself as root:"
        hint "  su - -c 'usermod -aG sudo $USER_NAME'   (then log in again)"
    fi

    if have sudo; then
        ok "sudo found"
    else
        err "sudo not found - the package steps cannot run"
        problems=$((problems + 1))
    fi

    # git and ssh-keygen are called directly by later steps. Without this
    # check the run gets as far as the question, the user answers Y, and bash
    # reports "line 197: ssh-keygen: command not found" - a diagnostic that
    # points at the runner helper rather than at the missing package.
    local tool pkg missing=0
    for tool in git:git ssh-keygen:openssh-client; do
        pkg="${tool#*:}"; tool="${tool%%:*}"
        if have "$tool"; then
            dbg "$tool found"
        else
            warn "$tool is missing - the steps that need it will be skipped"
            hint "it comes from the '$pkg' package, which is on $PKG_LIST"
            missing=$((missing + 1))
        fi
    done
    [ "$missing" -eq 0 ] || hint "the package step installs them; re-run afterwards"

    local f missing=0 total=0
    for f in "$BASHRC_SRC" "$ZSHRC_SRC" "$BASH_PROFILE_SRC" "$TMUX_SRC" \
             "$PKG_LIST" "$SHELL_SRC/env.sh" "$BLERC_SRC" "$INPUTRC_SRC" \
             "$STARSHIP_SRC" "$FASTFETCH_SRC"; do
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

    if ! apt_get update; then
        err "apt-get update failed"
        return 1
    fi
    if ! apt_get full-upgrade; then
        err "apt-get full-upgrade failed"
        return 1
    fi
    # What the later steps call directly - git for every clone, curl and jq
    # for the verified upstream downloads, xz for the Nerd Font tarball - in a
    # transaction of their own: a cosmetic extra that no longer exists in the
    # archive must not be able to take the toolchain down with it.
    if ! apt_get install build-essential git curl ca-certificates jq xz-utils; then
        err "could not install the base toolchain"
        return 1
    fi
    # neofetch is gone from trixie; fastfetch is the greeting and not fatal.
    apt_get install fastfetch \
        || warn "fastfetch not installed (cosmetic only, continuing)"

    ok_did "system updated"
    completed
}

# 2. The bash configuration: one file of our own, one line in ~/.bashrc.
install_bashrc() {
    log "Bash configuration"
    step "installs bashrc as $(tilde "$MANAGED_DIR")/bashrc"
    step "and adds one guarded source line to $(tilde "$HOME/.bashrc")"
    step "plus shell/*.sh -> $(tilde "$SHELL_DEST")/, blerc -> ~/.blerc, inputrc -> ~/.inputrc"
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
    # And the fzf block of the versions that installed ~/.fzf.bash: the fzf
    # setup lives in ~/.config/shell/fzf.sh now.
    run rc_block_drop "$HOME/.bashrc" fzf \
        || warn "could not remove the old fzf block from $HOME/.bashrc"

    install_shell_common || return 1
    install_file "$BLERC_SRC" "$HOME/.blerc" || { err "could not install ~/.blerc"; return 1; }
    install_file "$INPUTRC_SRC" "$HOME/.inputrc" || { err "could not install ~/.inputrc"; return 1; }

    if ! run rc_block "$HOME/.bashrc" bashrc "$(source_line "$MANAGED_DIR/bashrc")"; then
        err "could not update $HOME/.bashrc"
        return 1
    fi
    ok_did "bash configuration installed"
    hint "your own additions belong in ~/.config/shell/local.sh (both shells)"
    hint "or ~/.bashrc.local (bash only) - sourced last, never written to"
    hint "ble.sh, starship and fastfetch come with the prompt step"
    hint "run 'exec bash' or open a new terminal to pick it up"
    completed
}

# The files bash and zsh share. Called by both shell steps, so declining one
# of them still leaves the other complete; the second call finds everything
# up to date and copies nothing.
#
# They are copies of this repository, so they go in without backups, like
# the managed rc files. local.sh is the exception in the other direction: it
# is the user's, and the example is copied only when there is none yet.
install_shell_common() {
    local f name
    need_file "$SHELL_SRC/env.sh" || return 1
    run mkdir -p "$SHELL_DEST" || { err "could not create $SHELL_DEST"; return 1; }
    for f in "$SHELL_SRC"/*.sh; do
        name="$(basename "$f")"
        copy_if_changed "$f" "$SHELL_DEST/$name" || {
            err "could not install $SHELL_DEST/$name"
            return 1
        }
    done
    if [ ! -e "$SHELL_DEST/local.sh" ] && [ -f "$SHELL_SRC/local.sh.example" ]; then
        run cp "$SHELL_SRC/local.sh.example" "$SHELL_DEST/local.sh" \
            || warn "could not create $SHELL_DEST/local.sh"
    fi
    return 0
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
            # shellcheck disable=SC2088  # a message about the path, not the path
            warn "~/.profile (or ~/.bash_login) will now be read as well"
            hint "it was shadowed by your ~/.bash_profile until now"
        fi
    fi

    if ! run rc_block "$target" bash_profile "$(source_line "$MANAGED_DIR/bash_profile")"; then
        err "could not update $target"
        return 1
    fi
    ok_did "bash login-shell configuration installed"
    # zsh needs no counterpart: it reads ~/.zshrc for every interactive shell,
    # login or not, so the zsh step below covers both cases on its own.
    completed
}

# 4. The package list.
#
# One apt-get transaction for the whole list, the same as the single yay
# transaction on the Arch branch, and with the same weakness: apt-get refuses
# the entire transaction when one name does not resolve. The fallback below
# is what keeps a single stale name from costing every other package.
install_packages() {
    log "Packages from $(basename "$PKG_LIST")"

    local -a pkgs=()
    mapfile -t pkgs < <(read_pkg_list "$PKG_LIST") || true
    if [ "${#pkgs[@]}" -eq 0 ]; then
        warn "no packages listed in $PKG_LIST"
        skipped
        return 0
    fi

    # Printing all the names here used to scroll the question itself off a
    # short terminal; the full list is one --verbose away.
    step "${#pkgs[@]} packages listed in $PKG_LIST"
    dbg "${pkgs[*]}"
    confirm "Install those ${#pkgs[@]} packages?" y || { skipped; return 0; }
    ensure_sudo || return 1

    # The index may be a week old when the system-update step was declined,
    # and a stale index is the usual reason a perfectly good name is
    # "not found".
    apt_get update || warn "apt-get update failed - trying with the old index"

    if apt_get install "${pkgs[@]}"; then
        ok_did "packages installed"
        completed
        return 0
    fi

    warn "the bulk install failed - retrying one package at a time"
    local p
    local -a bad=()
    for p in "${pkgs[@]}"; do
        apt_get install "$p" || bad+=("$p")
    done
    if [ "${#bad[@]}" -eq 0 ]; then
        ok "packages installed on the second pass"
        completed
        return 0
    fi
    err "${#bad[@]} package(s) could not be installed: ${bad[*]}"
    hint "check the names with 'apt-cache policy NAME', then edit $PKG_LIST"
    return 1
}

# 5. The audio profile: PipeWire at the material's native rate, WirePlumber with
# a better resampler and no sink suspend, the AutoEq switcher with its
# impulses, and the M20 drop logger. docs/AUDIO.md has the why.
#
# Everything goes into $HOME and nothing is forced per card, so the profile
# is safe on any hardware: the rules match every alsa_output, and allowed-rates
# is trimmed by PipeWire to what each card can do.
install_audio_profile() {
    log "Audio profile (PipeWire, WirePlumber, AutoEq)"
    local pw="$XDG_CONFIG_DIR/pipewire/pipewire.conf.d"
    local wp="$XDG_CONFIG_DIR/wireplumber/wireplumber.conf.d"
    local eq="$HOME/.local/share/autoeq/denon"
    step "audio/pipewire/99-audiophile.conf    -> $(tilde "$pw")/"
    step "audio/wireplumber/99-audiophile.conf -> $(tilde "$wp")/"
    step "audio/autoeq/denon/ -> $(tilde "$eq")/, autoeq and m20-dropwatch -> ~/.local/bin/"
    confirm "Install the audio profile?" y || { skipped; return 0; }
    need_file "$AUDIO_SRC/pipewire/99-audiophile.conf" || return 1
    need_file "$AUDIO_SRC/wireplumber/99-audiophile.conf" || return 1

    run mkdir -p "$pw" "$wp" "$eq" "$HOME/.local/bin" || return 1
    install_file "$AUDIO_SRC/pipewire/99-audiophile.conf" "$pw/99-audiophile.conf" || return 1
    install_file "$AUDIO_SRC/wireplumber/99-audiophile.conf" "$wp/99-audiophile.conf" || return 1

    local f
    for f in "$AUDIO_SRC"/autoeq/denon/*; do
        copy_if_changed "$f" "$eq/$(basename "$f")" || return 1
    done
    for f in "$AUDIO_SRC"/bin/*; do
        install_file "$f" "$HOME/.local/bin/$(basename "$f")" || return 1
        run chmod 755 "$HOME/.local/bin/$(basename "$f")" || return 1
    done

    # The new files only apply to a restarted PipeWire. Nothing to restart
    # in a container, or before the user session exists.
    if ! in_container && systemctl --user is-active --quiet pipewire 2>/dev/null; then
        run systemctl --user restart pipewire pipewire-pulse wireplumber \
            || warn "could not restart PipeWire - log out and back in"
    fi
    ok_did "audio profile installed"
    hint "AutoEq is off; turn it on with: autoeq D5200  (autoeq sinks lists the outputs)"
    hint "check the clock with: pw-metadata -n settings | grep rate"
    completed
}

# 6. zsh: the configuration, Oh My Zsh, the custom plugins, the mtsh
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
    step "installs Oh My Zsh, fzf-tab, zsh-autosuggestions, fast-syntax-highlighting,"
    step "zsh-history-substring-search and the mtsh theme into $(tilde "$OMZ_DIR")"
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
    install_shell_common || return 1

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
    ok_did "zsh configuration installed"
    hint "your own additions belong in ~/.config/shell/local.sh (both shells)"
    hint "or ~/.zshrc.local (zsh only) - sourced last, never written to"
    hint "switch the prompt with: prompt-use starship | prompt-use mtsh"

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
    ok "Oh My Zsh, the ${#OMZ_PLUGIN_REPOS[@]} plugins and the mtsh theme are in place"
    hint "the mtsh theme needs a powerline font selected in your terminal emulator"

    # --- the login shell, which is the one thing that can lock somebody out --
    install_login_shell
    completed
}

# Clone the theme repository into a temporary directory and copy the single
# file Oh My Zsh wants out of it. A subshell for the same reason as
# rc_block: the EXIT trap has to die with the function that set it.
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

    # The comment is baked into the public key and travels with it to every
    # host it is pasted into, so it must not be the maintainer's address. Use
    # what git already knows about this machine, and fall back to
    # user@hostname rather than to a stranger's mailbox.
    local comment
    comment="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"
    comment="${comment:-$USER_NAME@$(uname -n 2>/dev/null || echo localhost)}"
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
    ok_did "SSH key generated at $key"
    # These hints used to be hidden from --yes users, who are precisely the
    # ones with no chance of having read them during the run.
    hint "add the public key to GitHub: https://github.com/settings/keys"
    hint "load it into the agent with: ssh-add $key"
    if [ -f "$key.pub" ]; then
        hint "public key: $(cat "$key.pub")"
    fi
    completed
}

# 8. libvirt / KVM: group membership, the socket, and the default network.
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
        hint "libvirt-daemon-system, qemu-system-x86 and virt-manager come from $PKG_LIST"
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
    # This is the whole of the access control: Debian's libvirtd.conf sets
    # unix_sock_group = "libvirt", so members of that group may open the
    # read-write socket and nobody else may. No sudo, no editing
    # libvirtd.conf - just the group.
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
        ok_did "libvirtd.socket enabled and started"
    fi

    # --- 4. the default network --------------------------------------------
    # Debian usually marks it autostart already, but not always active. A
    # guest created before it is up comes up with no network at all, which
    # reads as a guest fault. It needs the dnsmasq binary on the host; that is
    # why dnsmasq-base is on the package list.
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
                || warn "could not start the default network - is dnsmasq-base installed?"
        fi
    fi

    ok_did "libvirt configuration applied"
    hint "virt-manager connects to qemu:///system; UEFI guests need ovmf"
    hint "and Windows 11 needs swtpm, both on the package list"
    completed
}

# 9. The prompt and the tools around it: starship, fastfetch, ble.sh, the
# Nerd Font, Debian's bat/fd renames, and the database zsh's
# command-not-found plugin answers from.
#
# The programs themselves come from the package step (starship, fastfetch,
# fzf, zoxide, eza, bat, fd-find, git-delta, command-not-found); this step
# installs their configuration, plus what Debian does not package: ble.sh and
# the JetBrainsMono Nerd Font.
install_prompt_tools() {
    log "Prompt, greeting and line editor"
    step "starship.toml -> $(tilde "$XDG_CONFIG_DIR")/starship.toml"
    step "fastfetch/config.jsonc -> $(tilde "$XDG_CONFIG_DIR")/fastfetch/config.jsonc"
    step "ble.sh nightly -> $(tilde "$BLESH_DIR")"
    step "JetBrainsMono Nerd Font -> $(tilde "$NERDFONT_DIR")"
    # shellcheck disable=SC2088  # a message about the path, not the path
    step "~/.local/bin/bat -> batcat, ~/.local/bin/fd -> fdfind"
    confirm "Install the prompt, the greeting, the font and ble.sh?" y || { skipped; return 0; }
    need_file "$STARSHIP_SRC" || return 1
    need_file "$FASTFETCH_SRC" || return 1

    install_file "$STARSHIP_SRC" "$XDG_CONFIG_DIR/starship.toml" \
        || { err "could not install starship.toml"; return 1; }
    run mkdir -p "$XDG_CONFIG_DIR/fastfetch" || return 1
    install_file "$FASTFETCH_SRC" "$XDG_CONFIG_DIR/fastfetch/config.jsonc" \
        || { err "could not install the fastfetch configuration"; return 1; }

    install_debian_shims || return 1

    local t
    for t in starship fastfetch fzf zoxide eza bat fd delta; do
        have "$t" || warn "$t is not installed yet - it comes from $PKG_LIST"
    done

    if [ -n "$(find "$NERDFONT_DIR" -name '*.ttf' -print -quit 2>/dev/null)" ]; then
        ok "the Nerd Font is already installed"
    else
        step "downloading $NERDFONT_ASSET from $NERDFONT_REPO"
        run nerdfont_bootstrap || warn "could not install the Nerd Font - icons will show as boxes"
    fi

    # ble.sh is replaced wholesale rather than updated in place: ble-update
    # needs a git checkout, and the tarball is a few hundred kilobytes.
    if [ -r "$BLESH_DIR/ble.sh" ]; then
        ok "ble.sh is already installed - update it from bash with: ble-update"
    elif ! have curl || ! have tar; then
        warn "curl or tar is missing - skipping ble.sh; bash works without it"
    else
        step "downloading ble.sh into $(tilde "$BLESH_DIR")"
        run blesh_bootstrap || { err "could not install ble.sh"; return 1; }
    fi

    # The package fills its database from apt's Contents files on every
    # apt-get update; this only makes sure it exists before the first one.
    if have update-command-not-found; then
        ensure_sudo || return 1
        run sudo update-command-not-found \
            || warn "update-command-not-found failed - it runs again with the next apt-get update"
    fi
    ok_did "prompt tools configured"
    hint "zsh uses the mtsh theme by default; 'prompt-use starship' switches"
    completed
}

# Download and unpack the ble.sh tarball in a temporary directory, then move
# it into place. Subshell for the EXIT trap, as in rc_block.
blesh_bootstrap() (
    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/setup-dotfiles-blesh.XXXXXX")" || return 1
    trap 'rm -rf "$tmpdir"' EXIT
    curl -fsSL "$BLESH_URL" | tar -xJ -C "$tmpdir" || return 1
    [ -r "$tmpdir/ble-nightly/ble.sh" ] || return 1
    mkdir -p "$BLESH_DIR" || return 1
    cp -r "$tmpdir/ble-nightly/." "$BLESH_DIR/" || return 1
    return 0
)

# install_debian_shims - bat and fd under their upstream names.
#
# A link, not an alias: the fzf previews, fzf-tab and functions.sh call `bat`
# and `fd` from inside other programs' command lines, where no alias reaches.
# A ~/.local/bin entry that is not our link is somebody's own and is left
# alone.
install_debian_shims() {
    local entry name real target link
    run mkdir -p "$HOME/.local/bin" || return 1
    for entry in "${DEBIAN_SHIMS[@]}"; do
        name="${entry%% *}"
        real="${entry#* }"
        link="$HOME/.local/bin/$name"
        target="$(command -v "$real" 2>/dev/null || true)"
        if [ -z "$target" ]; then
            dbg "$real is not installed - no $name link"
            continue
        fi
        if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
            dbg "$link already points at $target"
        elif [ -e "$link" ] || [ -L "$link" ]; then
            warn "$(tilde "$link") exists and is not our link - left alone"
        else
            run ln -s "$target" "$link" || return 1
            ok_did "$(tilde "$link") -> $target"
        fi
    done
    return 0
}

# Fetch the JetBrainsMono Nerd Font (checksum-verified) and unpack the Mono
# variant only: the others draw icons wider than a terminal cell. Subshell
# for the EXIT trap.
nerdfont_bootstrap() (
    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/setup-dotfiles-font.XXXXXX")" || return 1
    trap 'rm -rf "$tmpdir"' EXIT
    gh_fetch "$NERDFONT_REPO" "$NERDFONT_ASSET" "$tmpdir/font.tar.xz" || return 1
    mkdir -p "$tmpdir/x" "$NERDFONT_DIR" || return 1
    tar -xJf "$tmpdir/font.tar.xz" -C "$tmpdir/x" || return 1
    find "$tmpdir/x" -name 'JetBrainsMonoNerdFontMono-*.ttf' -exec cp {} "$NERDFONT_DIR/" \; || return 1
    if have fc-cache; then fc-cache -f "$NERDFONT_DIR" >/dev/null 2>&1 || true; fi
    return 0
)

# 10. Konsole: a profile with the Nerd Font, the Catppuccin Mocha colours, and
# that profile as the default.
#
# The Font= line is in the Qt 6 format (16 fields, weight 400). Konsole on
# Qt 5 reads only 10 fields with weight on a 0-99 scale and renders a Qt 6
# line with the wrong weight and metrics; Konsole in trixie is Qt 6.
# "Nerd Font Mono", not "Nerd Font": the non-Mono icons are wider than one
# cell and push the columns out of line.
install_konsole() {
    log "Konsole profile"
    if ! have konsole; then
        ok "Konsole is not installed - nothing to configure"
        skipped
        return 0
    fi
    local dest="$HOME/.local/share/konsole"
    step "konsole/Mok.profile and CatppuccinMocha.colorscheme -> $(tilde "$dest")/"
    step "and Mok.profile as the default profile in konsolerc"
    confirm "Install the Konsole profile?" y || { skipped; return 0; }
    need_file "$KONSOLE_SRC/Mok.profile" || return 1
    need_file "$KONSOLE_SRC/CatppuccinMocha.colorscheme" || return 1

    run mkdir -p "$dest" || return 1
    install_file "$KONSOLE_SRC/Mok.profile" "$dest/Mok.profile" || return 1
    install_file "$KONSOLE_SRC/CatppuccinMocha.colorscheme" "$dest/CatppuccinMocha.colorscheme" || return 1

    local kw=""
    if have kwriteconfig6; then kw=kwriteconfig6; elif have kwriteconfig5; then kw=kwriteconfig5; fi
    if [ -n "$kw" ]; then
        run "$kw" --file konsolerc --group "Desktop Entry" --key DefaultProfile Mok.profile \
            || warn "could not set the default profile - pick Mok in Settings -> Manage Profiles"
    else
        warn "no kwriteconfig - pick Mok in Konsole: Settings -> Manage Profiles"
    fi
    ok_did "Konsole profile installed"
    hint "Konsole reads profiles at start - close every Konsole window first"
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
    ok_did "tmux configuration installed"
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
    step "Neovim >= $NVIM_MIN -> $NVIM_PREFIX, tree-sitter >= $TREESITTER_MIN -> $LOCAL_BIN_SYS"
    step "copies nvim/ to $(tilde "$NVIM_DEST")/"
    step "then downloads the plugins, LSP servers and tree-sitter parsers"
    confirm "Install Neovim and its configuration?" y || { skipped; return 0; }

    install_upstream_nvim || return 1
    install_upstream_treesitter || warn "no tree-sitter CLI - parsers will not compile"

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
            local backup
            backup="$NVIM_DEST.bak.$(date +%Y%m%d-%H%M%S)"
            warn "$(tilde "$NVIM_DEST") exists and differs - copying it to $(tilde "$backup")"
            run cp -a "$NVIM_DEST" "$backup" || { err "could not back up $NVIM_DEST"; return 1; }
        fi
        run mkdir -p "$NVIM_DEST" || { err "could not create $NVIM_DEST"; return 1; }
        run cp -a "$NVIM_SRC/." "$NVIM_DEST/" || { err "could not copy the Neovim tree"; return 1; }
        ok "Neovim configuration installed in $(tilde "$NVIM_DEST")"
    fi

    if ! have nvim; then
        warn "neovim is not installed - nothing to bootstrap"
        hint "the configuration is already in place and installs itself"
        hint "the first time you start the editor"
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

# install_upstream_nvim - Neovim from the upstream release, unless the nvim
# on PATH is already new enough.
#
# Debian's own neovim package is deliberately not on the package list: its
# /usr/bin/nvim would sit behind /usr/local/bin and only confuse `which`.
# The release tarball is unpacked next to the old tree and swapped in with
# one mv, so an interrupted download never leaves a half-written editor.
install_upstream_nvim() {
    local cur
    cur="$(tool_version nvim --version)"
    if [ -n "$cur" ] && version_ge "$cur" "$NVIM_MIN"; then
        ok "Neovim $cur is new enough"
        return 0
    fi
    if [ -n "$cur" ]; then
        warn "Neovim $cur is too old for LazyVim (needs $NVIM_MIN)"
    fi
    ensure_sudo || return 1
    step "installing the latest Neovim release into $NVIM_PREFIX"
    run nvim_bootstrap || { err "could not install Neovim"; return 1; }
    hash -r
    local v
    v="$(tool_version "$LOCAL_BIN_SYS/nvim" --version)"
    ok_did "Neovim ${v:+$v }installed"
    return 0
}

nvim_bootstrap() (
    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/setup-dotfiles-nvim.XXXXXX")" || return 1
    trap 'rm -rf "$tmpdir"' EXIT
    gh_fetch "$NVIM_REPO" "$NVIM_ASSET" "$tmpdir/nvim.tar.gz" || return 1
    tar -xzf "$tmpdir/nvim.tar.gz" -C "$tmpdir" || return 1
    [ -x "$tmpdir/nvim-linux-x86_64/bin/nvim" ] || return 1
    sudo rm -rf "$NVIM_PREFIX.new" || return 1
    sudo cp -a "$tmpdir/nvim-linux-x86_64" "$NVIM_PREFIX.new" || return 1
    sudo chown -R root:root "$NVIM_PREFIX.new" || return 1
    sudo rm -rf "$NVIM_PREFIX" || return 1
    sudo mv "$NVIM_PREFIX.new" "$NVIM_PREFIX" || return 1
    sudo ln -sfn "$NVIM_PREFIX/bin/nvim" "$LOCAL_BIN_SYS/nvim" || return 1
    return 0
)

# install_upstream_treesitter - the tree-sitter CLI the nvim-treesitter main
# branch compiles parsers with. A single static binary.
install_upstream_treesitter() {
    local cur
    cur="$(tool_version tree-sitter --version)"
    if [ -n "$cur" ] && version_ge "$cur" "$TREESITTER_MIN"; then
        ok "tree-sitter $cur is new enough"
        return 0
    fi
    ensure_sudo || return 1
    step "installing the latest tree-sitter CLI into $LOCAL_BIN_SYS"
    run treesitter_bootstrap || { err "could not install the tree-sitter CLI"; return 1; }
    hash -r
    local v
    v="$(tool_version "$LOCAL_BIN_SYS/tree-sitter" --version)"
    ok_did "tree-sitter ${v:+$v }installed"
    return 0
}

treesitter_bootstrap() (
    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/setup-dotfiles-ts.XXXXXX")" || return 1
    trap 'rm -rf "$tmpdir"' EXIT
    gh_fetch "$TREESITTER_REPO" "$TREESITTER_ASSET" "$tmpdir/ts.gz" || return 1
    gunzip "$tmpdir/ts.gz" || return 1
    "$tmpdir/ts" --version >/dev/null || return 1
    sudo install -m755 "$tmpdir/ts" "$LOCAL_BIN_SYS/tree-sitter" || return 1
    return 0
)

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

    # Flags and environment first, then whatever is already configured. The
    # built-in default comes last and is treated as a separate case, because
    # it is the MAINTAINER's identity in a public repository: falling back to
    # it silently makes a stranger commit as somebody else, and their mail and
    # their GitHub attribution go to that somebody else too.
    local want_name="${GIT_AUTHOR:-$cur_name}"
    local want_email="${GIT_EMAIL:-$cur_email}"
    local using_builtin=0
    if [ -z "$want_name" ] || [ -z "$want_email" ]; then
        using_builtin=1
        want_name="${want_name:-$GIT_AUTHOR_DEFAULT}"
        want_email="${want_email:-$GIT_EMAIL_DEFAULT}"
    fi

    step "user.name ....... $want_name"
    step "user.email ...... $want_email"
    step "core.fileMode ... false (global, for every repository on this machine)"

    if [ "$using_builtin" = "1" ]; then
        warn "that identity is this repository's built-in default, not yours"
        hint "it is the author's own name and address; every commit you make"
        hint "would carry them. Pass --git-name 'Your Name' and"
        hint "--git-email you@example.org, or set them with git config first."
        # An unattended run has nobody to read the warning, so it does the one
        # safe thing instead: configure core.fileMode and leave the identity
        # alone rather than stamping the maintainer's onto this machine.
        if [ "$ASSUME_YES" = "1" ]; then
            warn "--yes: leaving user.name and user.email alone"
            run git config --global core.fileMode false || {
                err "git config core.fileMode failed"; return 1; }
            ok_did "core.fileMode set; identity untouched"
            completed
            return 0
        fi
    fi

    # Warn when EITHER field changes, not just the name. A half-configured
    # machine - name set, address not - used to be "changed" without a word.
    if { [ -n "$cur_name" ] && [ "$cur_name" != "$want_name" ]; } ||
       { [ -n "$cur_email" ] && [ "$cur_email" != "$want_email" ]; }; then
        warn "this replaces the configured identity: ${cur_name:-(unset)} <${cur_email:-(unset)}>"
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
    ok_did "global git configuration applied"
    if [ "$VERBOSE" = "1" ]; then
        git config --global --list 2>/dev/null | sed 's/^/     /' >&2 || true
    fi
    completed
}

# 15. Tailscale.
install_tailscale() {
    log "Tailscale"
    # Debian does not package tailscale. Rather than piping the upstream
    # install.sh into a root shell, this does by hand the two things that
    # script does on Debian: add Tailscale's signing key and its apt source,
    # both fetched over HTTPS from pkgs.tailscale.com. After that tailscale
    # updates with the rest of the system.
    local codename keyring list
    codename="$(. /etc/os-release 2>/dev/null && printf '%s' "${VERSION_CODENAME:-trixie}")"
    keyring="/usr/share/keyrings/tailscale-archive-keyring.gpg"
    list="/etc/apt/sources.list.d/tailscale.list"
    step "adds pkgs.tailscale.com/stable/debian $codename as an apt source"
    step "installs the tailscale package and enables tailscaled"
    confirm "Install Tailscale?" y || { skipped; return 0; }
    ensure_sudo || return 1

    if have tailscale; then
        ok "tailscale is already installed"
    else
        if [ ! -s "$keyring" ]; then
            run sudo curl -fsSL -o "$keyring" \
                "https://pkgs.tailscale.com/stable/debian/$codename.noarmor.gpg" \
                || { err "could not fetch the Tailscale signing key"; return 1; }
        fi
        if [ ! -s "$list" ]; then
            run sudo curl -fsSL -o "$list" \
                "https://pkgs.tailscale.com/stable/debian/$codename.tailscale-keyring.list" \
                || { err "could not fetch the Tailscale apt source"; return 1; }
        fi
        apt_get update || { err "apt-get update failed"; return 1; }
        apt_get install tailscale || { err "could not install tailscale"; return 1; }
    fi

    if in_container || ! have_systemd; then
        warn "no systemd here - not enabling tailscaled"
    else
        run sudo systemctl enable --now tailscaled \
            || { err "could not enable tailscaled"; return 1; }
        ok_did "tailscaled enabled and started"
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

    apt_get update || { err "apt-get update failed"; return 1; }
    apt_get full-upgrade || { err "apt-get full-upgrade failed"; return 1; }

    # Real cleanup, rather than a message claiming cleanup happened.
    # autoremove is deliberately left to the user: it is the one operation
    # here that can uninstall something wanted.
    apt_get autoclean || warn "could not trim the package cache"

    ok_did "post-installation finished"
    hint "review what apt would remove with: apt-get autoremove --dry-run"
    hint "restart your terminal, or run 'source ~/.bashrc', to apply the changes"
    completed
}

# ===========================================================================
#  Summary
# ===========================================================================
summary() {
    printf '\n' >&2
    printf '%sSummary%s\n' "$C_BOLD" "$C_RESET" >&2
    # "completed" is a claim about the machine, and during a rehearsal nothing
    # was completed at all. The trailing warning said so, but by then the
    # reader has already taken the word at face value.
    if [ "$DRY_RUN" = "1" ]; then
        printf '  would run ....... %s\n' "${STEPS_DONE[*]:-none}" >&2
    else
        printf '  completed ....... %s\n' "${STEPS_DONE[*]:-none}" >&2
    fi
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

    # Ctrl-C during a package transaction should say so, and use
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
    do_step "packages"      install_packages
    do_step "audio"         install_audio_profile
    do_step "zsh"           install_zsh
    do_step "ssh key"       install_sshkey
    do_step "libvirt"       install_libvirt_configuration
    do_step "prompt"        install_prompt_tools
    do_step "konsole"       install_konsole
    do_step "ram disk"      install_ram_disk
    do_step "tmux"          install_tmux
    do_step "neovim"        install_neovim
    do_step "git rules"     install_git_rules
    do_step "tailscale"     install_tailscale
    do_step "post-install"  post_installation

    summary
}

main "$@"
