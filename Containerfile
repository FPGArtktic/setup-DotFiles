# ===========================================================================
#  setup-dotFiles :: Debian 13 (trixie) test environment
#  Author: Mateusz Okulanis
#  License: Unlicense
#
#  A disposable Debian trixie box in which setup-dotFiles.sh can be run for
#  real - apt-get, ssh-keygen, the upstream Neovim download and all - without
#  letting it anywhere near the machine you are sitting at.
#
#  Nothing from the working tree is baked in. The repository is bind-mounted
#  at /app when the container runs, so editing a dotfile needs no rebuild and
#  the image stays valid for as long as the package set does.
#
#  Build it through the runner, not by hand:
#      ./run.sh
# ===========================================================================

# Parameterised so the runner can pin, or swap, the base.
ARG DOT_BASE_IMAGE=docker.io/library/debian:trixie
FROM ${DOT_BASE_IMAGE}

# user/user is the credential pair the README documents for this image. It
# guards nothing and is meant to guard nothing: this is a throwaway test box
# whose whole point is that the account already has passwordless sudo.
ARG DOT_USER=user
ARG DOT_PASSWORD=user

# The checkout is bind-mounted read-write; a container user numbered
# differently from you produces files in your own git checkout that you
# cannot then edit. Override both when your account is not 1000.
ARG DOT_UID=1000
ARG DOT_GID=1000

ARG DOT_TZ=UTC
ARG DOT_BUILD_DATE=unknown

ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------------------------------------------------------------------------
#  1. What setup-dotFiles.sh reaches for before it installs anything
#
#     Only the cheap prerequisites, never apt-apps.txt itself: that list
#     holds libvirt, QEMU and desktop applications, and a run has to be free
#     to attempt the install and be judged on what happens.
# ---------------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        sudo git openssh-client curl ca-certificates jq xz-utils rsync tmux \
        less locales fastfetch ripgrep fd-find bat \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
#  2. Locale and timezone
# ---------------------------------------------------------------------------
RUN sed -i -e 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
 && locale-gen \
 && ln -snf "/usr/share/zoneinfo/${DOT_TZ}" /etc/localtime \
 && echo "${DOT_TZ}" > /etc/timezone

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
#  3. Unprivileged user with passwordless sudo
#     The script refuses to run as root, and as root $HOME would be /root.
#     The sudo rule is a validated drop-in, and the user is in the sudo
#     group too, so the preflight's group check stays quiet.
# ---------------------------------------------------------------------------
RUN groupadd -g "${DOT_GID}" "${DOT_USER}" \
 && useradd -m -u "${DOT_UID}" -g "${DOT_GID}" -G sudo -s /bin/bash "${DOT_USER}" \
 && printf '%s:%s\n' "${DOT_USER}" "${DOT_PASSWORD}" | chpasswd \
 && printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${DOT_USER}" > /etc/sudoers.d/99-dotfiles \
 && chmod 0440 /etc/sudoers.d/99-dotfiles \
 && visudo -c -f /etc/sudoers.d/99-dotfiles \
 && mkdir -p /app \
 && chown "${DOT_UID}:${DOT_GID}" /app

# ---------------------------------------------------------------------------
#  4. Trusting the bind-mounted checkout (throwaway box only)
# ---------------------------------------------------------------------------
RUN git config --system --add safe.directory '*'

# ---------------------------------------------------------------------------
#  5. What this box deliberately cannot test
#
#     There is no systemd here - PID 1 is bash - so the libvirt and tailscale
#     steps skip their systemctl calls; the script detects the container
#     through /run/.containerenv. The apt lists were dropped above, so the
#     first package step starts with apt-get update, as on a real machine.
# ---------------------------------------------------------------------------
USER ${DOT_USER}
WORKDIR /app

LABEL org.opencontainers.image.title="setup-dotfiles-trixie-test" \
      org.opencontainers.image.description="Debian 13 (trixie) test environment for setup-dotFiles.sh" \
      org.opencontainers.image.authors="Mateusz Okulanis" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.created="${DOT_BUILD_DATE}" \
      dotfiles.user="${DOT_USER}" \
      dotfiles.uid="${DOT_UID}" \
      dotfiles.gid="${DOT_GID}"

CMD ["bash"]
