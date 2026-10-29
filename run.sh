#!/usr/bin/env bash
# ===========================================================================
#  run.sh - build and enter the setup-DotFiles test environment
#  Author: Mateusz Okulanis
#  License: Unlicense
#
#  An Arch container with a passwordless-sudo user and this repository
#  mounted at /app, so setup-dotFiles.sh can be exercised without touching
#  the machine you are sitting at:
#
#      ./run.sh                              # build, then drop into a shell
#      ./run.sh --rebuild                    # forget every cached layer
#      ./run.sh -- ./setup-dotFiles.sh -y    # run it, exit with its status
#
#  Runs on podman only: rootless by default, so a container that goes wrong
#  cannot hurt the host, and nothing has to be enabled or joined first.
#
#  Run `./run.sh --help` for the full option reference.
# ===========================================================================

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"

# --- identity of the machine we are running on RIGHT NOW --------------------
# Re-evaluated on every invocation: the image bakes in whoever built it, and
# that is not necessarily whoever runs it next.
HOST_USER="${USER:-$(id -un)}"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# --- naming -----------------------------------------------------------------
# The caller's uid is baked into the image (see build_image), so two users on
# one machine must not share a tag - the second build would silently hand the
# first one a container that writes files owned by somebody else.
IMAGE_SLUG="$(printf '%s' "$HOST_USER" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_.-')"
IMAGE_NAME="setup-dotfiles-test-${IMAGE_SLUG:-user}"
# Appended only when the reference does not carry a tag of its own - see
# image_ref(). "--tag myimage:v2" used to become "myimage:v2:latest", which
# podman rejects as an invalid reference.
IMAGE_TAG_DEFAULT="latest"
CONTAINER_HOSTNAME="dotfiles-test"
MOUNT_POINT="/app"

# --- defaults ---------------------------------------------------------------
ENGINE="podman"      # the only engine this script drives
BASE_IMAGE=""        # empty means "whatever the Containerfile defaults to"
REBUILD=0
NO_BUILD=0
BUILD_ONLY=0
DRY_RUN=0

# ===========================================================================
#  Output helpers
# ===========================================================================
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'; C_BLUE=$'\033[0;34m'; C_CYAN=$'\033[0;36m'
    C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
else
    C_RESET=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=; C_BOLD=; C_DIM=
fi

log()   { printf '%s==>%s %s\n' "$C_BLUE"   "$C_RESET" "$*" >&2; }
step()  { printf '%s ->%s %s\n' "$C_CYAN"   "$C_RESET" "$*" >&2; }
ok()    { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
warn()  { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%serr %s %s\n' "$C_RED"   "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }
hint()  { printf '%s     %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

# Show a command the way the user could retype it, one token per quote.
show_cmd() {
    local out="" tok
    for tok in "$@"; do
        case "$tok" in
            *[![:alnum:]_.:/=@-]*) out+=" '$tok'" ;;
            *)                     out+=" $tok" ;;
        esac
    done
    printf '%s\n' "${out# }"
}

# The image reference to build and to run.
#
# ":latest" is appended only when the caller's reference does not already
# carry a tag - "--tag myimage:v2" used to be turned into "myimage:v2:latest",
# which both engines reject as an invalid reference. A digest ("name@sha256:")
# is left alone as well. The check looks at the part after the last "/" so a
# registry port, as in "localhost:5000/img", is not mistaken for a tag.
image_ref() {
    local ref="$IMAGE_NAME" last="${IMAGE_NAME##*/}"
    case "$last" in
        *@*|*:*) printf '%s\n' "$ref" ;;
        *)       printf '%s:%s\n' "$ref" "$IMAGE_TAG_DEFAULT" ;;
    esac
}

# A build stamp that is stable as long as the repository is.
#
# It ends up in a LABEL, and any ARG the Containerfile references takes part in
# the cache key of every instruction after it. A wall-clock timestamp therefore
# invalidates the entire build on every run. The commit date of HEAD changes
# only when the sources do; outside a git checkout the file mtimes are the next
# best stable thing, and "unknown" is the last resort.
build_stamp() {
    local stamp
    if stamp="$(git -C "$SCRIPT_DIR" log -1 --format=%cI 2>/dev/null)" && [ -n "$stamp" ]; then
        printf '%s\n' "$stamp"
        return
    fi
    if stamp="$(find "$SCRIPT_DIR" -maxdepth 1 -type f -printf '%T@\n' 2>/dev/null \
                | sort -rn | head -1)" && [ -n "$stamp" ]; then
        printf 'mtime-%s\n' "${stamp%%.*}"
        return
    fi
    printf 'unknown\n'
}

# ===========================================================================
#  Help
# ===========================================================================
usage() {
    cat >&2 <<EOF
${C_BOLD}$SCRIPT_NAME${C_RESET} [options] [-- COMMAND...]   - test setup-dotFiles.sh in a container

  --podman            accepted for old command lines; podman is the only engine
  --rebuild           build with --no-cache --pull, ignoring every cached layer
  --no-build          do not build, run the image that is already tagged
  --build-only        build the image and stop
  --shell             interactive shell in the container (this is the default)
  --base IMAGE        override the base image passed to the Containerfile
  --tag REF           image to build and run (default: $(image_ref))
  --dry-run           print the engine commands instead of running them
  -h, --help          this text
  --version           version and licence

Everything after ${C_BOLD}--${C_RESET} is executed inside the container instead of a shell, and its
exit status becomes this script's exit status - which is what makes the test
environment usable from CI:

      ./$SCRIPT_NAME -- ./setup-dotFiles.sh --dry-run
      ./$SCRIPT_NAME -- bash -c './setup-dotFiles.sh -y && ./setup-dotFiles.sh -y'

This repository is mounted read-write at $MOUNT_POINT, so anything the script writes
into its own directory lands in your checkout. That is deliberate - it is how
you inspect the damage afterwards - but it is also why nothing here should be
pointed at a tree you care about.

Tip: the container exports DOTFILES_IN_CONTAINER=1. There is no systemd and no
kernel to speak of in there, so steps that call systemctl are expected to fail.
EOF
}

version() {
    cat <<EOF
$SCRIPT_NAME $SCRIPT_VERSION

This is free and unencumbered software released into the public domain.
See the LICENSE file, or <https://unlicense.org>.

Written by Mateusz Okulanis.
EOF
}

# ===========================================================================
#  Engine selection
# ===========================================================================
# podman only. It is rootless by default, so a container that goes wrong
# cannot take the host with it, and unlike a docker daemon there is no
# service to enable and no group to join before the first run.
select_engine() {
    if ! have podman; then
        err "podman is not installed"
        hint "arch: sudo pacman -S podman   (rootless, nothing to enable)"
        exit 1
    fi
    step "engine ...... podman"
}

# Is this engine running rootless? The answer decides the whole uid story
# below, so an engine that refuses to say is treated as rootful - the case
# where we add no mapping flags and can therefore break nothing.
engine_is_rootless() {
    local answer
    answer="$($ENGINE info --format '{{.Host.Security.Rootless}}' 2>/dev/null || true)"
    [ "$answer" = "true" ]
}

# SELinux relabels a bind mount out of the container's reach unless it is
# asked not to. `z` is the shared label: the mount stays usable by the host.
selinux_suffix() {
    if have selinuxenabled && selinuxenabled 2>/dev/null; then printf ',z'; fi
}

# ===========================================================================
#  Identity
# ===========================================================================
# Files the container writes into /app must come out owned by the caller,
# otherwise the first test run leaves a checkout the caller cannot edit.
#
#   rootless podman (the normal case)
#       The container lives in a user namespace where container uid 0 is the
#       caller and every other container uid comes out of /etc/subuid - so
#       the image user, uid 1000, writes files owned by host uid 100999 or
#       similar, which is not a user at all. --userns=keep-id maps the
#       caller's host uid to the SAME uid inside the container, and because
#       we built the image with DOT_UID=$(id -u) that uid is exactly the
#       image user. Plain keep-id is therefore enough here; the
#       keep-id:uid=,gid= form (podman 4.3+) is only needed when the image
#       user's uid differs from the host's, which by construction it cannot.
#
#   rootful podman (sudo podman)
#       There is no user namespace and keep-id is rejected outright. Container
#       uid is host uid, so baking the caller's uid into the image with
#       --build-arg DOT_UID is the whole fix.
resolve_identity() {
    IMG_UID="$HOST_UID"
    IMG_GID="$HOST_GID"

    # uid 0 cannot be handed to useradd in the image - it is already taken by
    # root - and a root-owned checkout is what we are trying to avoid anyway.
    if [ "$HOST_UID" = "0" ]; then
        IMG_UID="1000"
        IMG_GID="1000"
        warn "you are root on the host - building the container user as 1000:1000 instead"
        hint "files created in $MOUNT_POINT will be owned by root either way; run this as yourself"
    fi

    step "identity .... $HOST_USER  host=$HOST_UID:$HOST_GID  image=$IMG_UID:$IMG_GID"
}

# The run-time half of the comment block above. It fills the global
# USERNS_ARGS rather than printing, because "no mapping needed" has to come
# back as an empty array and not as a blank line the caller must filter out.
USERNS_ARGS=()
resolve_userns() {
    USERNS_ARGS=()
    if engine_is_rootless; then
        USERNS_ARGS+=(--userns "keep-id")
        step "mapping ..... --userns=keep-id (rootless podman)"
    else
        # Rootful: container uid is host uid already, and podman rejects
        # keep-id in this mode, so the correct mapping is no mapping.
        step "mapping ..... none needed (rootful podman)"
    fi
}

# ===========================================================================
#  Build
# ===========================================================================
containerfile_path() {
    # Named explicitly with --file, so the build never depends on the
    # current directory.
    if [ -f "$SCRIPT_DIR/Containerfile" ]; then
        printf '%s\n' "$SCRIPT_DIR/Containerfile"
    else
        die "no Containerfile in $SCRIPT_DIR"
    fi
}

# An undeclared --build-arg is only a warning, never an error, in podman. That is the dangerous case: rename DOT_UID in the Containerfile and
# every build would keep succeeding while quietly falling back to uid 1000,
# handing the caller a checkout owned by somebody else. So it is checked.
assert_build_arg() {
    local name="$1" containerfile="$2"
    grep -qE "^[[:space:]]*ARG[[:space:]]+$name([[:space:]]|=|$)" "$containerfile" && return 0
    warn "$(basename "$containerfile") does not declare ARG $name - it will be ignored"
    hint "the container user's identity is set from it; files in $MOUNT_POINT may come out mis-owned"
}

build_image() {
    local containerfile
    containerfile="$(containerfile_path)"

    log "Building ${C_BOLD}$(image_ref)${C_RESET} with $ENGINE"
    step "context ..... $SCRIPT_DIR"
    step "recipe ...... $containerfile"
    [ -n "$BASE_IMAGE" ] && step "base ........ $BASE_IMAGE"

    assert_build_arg DOT_UID "$containerfile"
    assert_build_arg DOT_GID "$containerfile"

    local -a args=(
        build
        --file "$containerfile"
        --tag "$(image_ref)"
        --build-arg "DOT_UID=$IMG_UID"
        --build-arg "DOT_GID=$IMG_GID"
        # DELIBERATELY a commit date and not "now". An ARG referenced in the
        # Containerfile takes part in the cache key of every instruction after
        # it, so a wall-clock timestamp invalidates the whole chain on every
        # single build: measured, a no-op rebuild went from 1.9 s to 18.2 s
        # and re-downloaded ~17 MB of packages plus a fresh yay clone. The
        # commit date changes only when the repository does, which is exactly
        # when a rebuild is warranted.
        --build-arg "DOT_BUILD_DATE=$(build_stamp)"
    )

    if [ "$REBUILD" = "1" ]; then
        args+=(--no-cache --pull)
    fi

    if [ -n "$BASE_IMAGE" ]; then
        assert_build_arg DOT_BASE_IMAGE "$containerfile"
        args+=(--build-arg "DOT_BASE_IMAGE=$BASE_IMAGE")
    fi

    args+=("$SCRIPT_DIR")

    if [ "$DRY_RUN" = "1" ]; then
        log "would run: $(show_cmd "$ENGINE" "${args[@]}")"
        return 0
    fi

    "$ENGINE" "${args[@]}" || die "$ENGINE build failed"
    ok "built $(image_ref)"
}

image_exists() {
    "$ENGINE" image inspect "$(image_ref)" >/dev/null 2>&1
}

# ===========================================================================
#  Run
# ===========================================================================
run_container() {
    local -a command=("$@")
    local sel
    sel="$(selinux_suffix)"

    if [ "${#command[@]}" -gt 0 ]; then
        log "Running ${C_BOLD}$(show_cmd "${command[@]}")${C_RESET} in $(image_ref)"
    else
        log "Entering ${C_BOLD}$(image_ref)${C_RESET}"
    fi
    step "mount ....... $SCRIPT_DIR -> $MOUNT_POINT (read-write)"

    local -a args=(
        run --rm
        --hostname "$CONTAINER_HOSTNAME"
        --workdir "$MOUNT_POINT"
        --volume "$SCRIPT_DIR:$MOUNT_POINT:rw$sel"
        # There is no init, no systemd and no loadable kernel modules in
        # there. The setup script is meant to read this and skip those steps
        # rather than fail them one at a time.
        --env "DOTFILES_IN_CONTAINER=1"
    )

    # TERM is forwarded only when it is worth forwarding. Bash sets TERM=dumb
    # whenever the variable is unset in the environment, so "${TERM:-...}"
    # never reaches its fallback inside a script: the container would be handed
    # "dumb" in every cron, CI and pipe context - precisely what the
    # Containerfile's ENV TERM exists to avoid. Passing nothing lets the
    # image's own value stand.
    if [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]; then
        args+=(--env "TERM=$TERM")
    fi

    resolve_userns
    if [ "${#USERNS_ARGS[@]}" -gt 0 ]; then
        args+=("${USERNS_ARGS[@]}")
    fi

    # A pty is allocated only when both ends really are terminals. With
    # `--tty` the runtime rewrites every \n as \r\n - so
    # `./run.sh -- cmd > file` would quietly produce a CRLF file.
    args+=(--interactive)
    if [ -t 0 ] && [ -t 1 ]; then
        args+=(--tty)
    else
        step "tty ......... none (stdin or stdout is not a terminal)"
    fi

    args+=("$(image_ref)")
    if [ "${#command[@]}" -gt 0 ]; then
        args+=("${command[@]}")
    fi

    if [ "$DRY_RUN" = "1" ]; then
        log "would run: $(show_cmd "$ENGINE" "${args[@]}")"
        return 0
    fi

    [ "${#command[@]}" -gt 0 ] || hint "the repository is at $MOUNT_POINT - 'exit' or ctrl-d to leave"

    # exec, so that the container's exit status becomes this script's exit
    # status and CI can tell a passing run from a failing one.
    exec "$ENGINE" "${args[@]}"
}

# ===========================================================================
#  main
# ===========================================================================
main() {
    local -a command=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --podman)     shift ;;
            --docker|--engine)
                          die "$1 is gone - this test environment runs on podman only" ;;
            --rebuild)    REBUILD=1; shift ;;
            --no-build)   NO_BUILD=1; shift ;;
            --build-only) BUILD_ONLY=1; shift ;;
            --shell)      shift ;;
            --base)       BASE_IMAGE="${2:?--base needs an image reference}"; shift 2 ;;
            --tag)        IMAGE_NAME="${2:?--tag needs an image reference}"; shift 2 ;;
            --dry-run)    DRY_RUN=1; shift ;;
            -h|--help)    usage; exit 0 ;;
            --version)    version; exit 0 ;;
            --)           shift; command=("$@"); break ;;
            *)            die "unknown option '$1' (try --help)" ;;
        esac
    done

    if [ "$NO_BUILD" = "1" ] && [ "$BUILD_ONLY" = "1" ]; then
        die "--no-build and --build-only ask for opposite things"
    fi

    log "setup-DotFiles test environment v$SCRIPT_VERSION"
    select_engine
    resolve_identity

    if [ "$NO_BUILD" = "1" ]; then
        if [ "$DRY_RUN" != "1" ] && ! image_exists; then
            err "no image $(image_ref) to run"
            hint "drop --no-build, or build it once with '$SCRIPT_NAME --build-only'"
            exit 1
        fi
        step "build ....... skipped (--no-build)"
    else
        build_image
    fi

    if [ "$BUILD_ONLY" = "1" ]; then
        ok "build only - not starting a container"
        hint "next: $SCRIPT_NAME --no-build     or   $SCRIPT_NAME --no-build -- ./setup-dotFiles.sh --dry-run"
        return 0
    fi

    # Not `run_container "${command[@]-}"`: bash treats an EMPTY LOCAL array
    # as unset, so the `-` fallback fires and passes one empty string, which
    # the engine would then try to exec as the container command.
    if [ "${#command[@]}" -gt 0 ]; then
        run_container "${command[@]}"
    else
        run_container
    fi
}

main "$@"
