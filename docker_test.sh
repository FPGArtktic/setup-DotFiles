#!/usr/bin/env bash
# ===========================================================================
#  docker_test.sh - compatibility shim, kept so old notes and bookmarks work
#  Author: Mateusz Okulanis
#  License: Unlicense
#
#  This script used to build and run the test container itself. That job now
#  belongs to run.sh, which drives podman as well as docker, preserves file
#  ownership on the mounted checkout and returns the container's exit status.
#  All this does is forward to it with the engine pinned to docker:
#
#      ./docker_test.sh                        ->  ./run.sh --docker
#      ./docker_test.sh -- ./setup-dotFiles.sh ->  ./run.sh --docker -- ...
#
#  Use run.sh directly. Run `./run.sh --help` for the options.
# ===========================================================================

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

[ -x "$SCRIPT_DIR/run.sh" ] || {
    printf 'err  %s/run.sh is missing or not executable\n' "$SCRIPT_DIR" >&2
    exit 1
}

# shellcheck disable=SC2016  # the backticks are literal text, not a subshell
printf 'note docker_test.sh is kept for compatibility - it now runs `./run.sh --docker`\n' >&2

# exec, so the container's exit status survives the extra hop.
exec "$SCRIPT_DIR/run.sh" --docker "$@"
