# ===========================================================================
#  setup-dotFiles :: Arch Linux test environment
#  Author: Mateusz Okulanis
#  License: Unlicense
#
#  A disposable Arch Linux box in which setup-dotFiles.sh can be run for real
#  - pacman, yay, makepkg, ssh-keygen and all - without letting it anywhere
#  near the machine you are sitting at.
#
#  The image this one replaces was ubuntu:24.04. On this branch that could not
#  test a single package step: every one of them is pacman or yay, so every
#  one of them failed on line one and the "test" proved nothing.
#
#  Nothing from the working tree is baked in. The repository is bind-mounted
#  at /app when the container runs, so editing a dotfile needs no rebuild and
#  the image stays valid for as long as the package set does.
#
#  Build it through the runner, not by hand:
#      ./run.sh
# ===========================================================================

# Parameterised so the runner can pin, or swap, the base: the rolling
# `archlinux:base-devel` tag moves under you, and reproducing a failure
# sometimes means going back to the image that produced it.
ARG DOT_BASE_IMAGE=docker.io/library/archlinux:base-devel
FROM ${DOT_BASE_IMAGE}

# user/user is the credential pair the README has always documented for this
# image, and it is kept so that documentation stays true. It guards nothing and
# is meant to guard nothing: this is a throwaway test box whose whole point is
# that the account already has passwordless sudo. Never reuse the pattern for
# an image that outlives a test run.
ARG DOT_USER=user
ARG DOT_PASSWORD=user

# The checkout is bind-mounted read-write, so ownership is not cosmetic. Under
# rootless podman the container UID is mapped back to a host UID; a container
# user numbered differently from you produces files in your own git checkout
# that you cannot then edit. Override both when your account is not 1000:
#
#     podman build --build-arg DOT_UID="$(id -u)" \
#                  --build-arg DOT_GID="$(id -g)" -f Containerfile .
ARG DOT_UID=1000
ARG DOT_GID=1000

ARG DOT_TZ=UTC
ARG DOT_BUILD_DATE=unknown

# A sane TERM is not decoration here: the shipped bashrc draws a colour prompt
# and fzf is a full-screen curses program. `dumb` makes both misbehave in ways
# that look like bugs in the dotfiles rather than in the test harness.
ENV TERM=xterm-256color

# pipefail matters because the package steps below pipe into `grep`/`tr`: a
# failure on the left of a pipe would otherwise be swallowed and the build
# would happily carry on with half a package list.
# (Podman warns that SHELL is not persisted in OCI images - harmless, CMD is
# set explicitly at the end.)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------------------------------------------------------------------------
#  1. Keyring first
#     archlinux-keyring before anything else: base images go stale and
#     signature checks then fail on an otherwise perfectly good mirror. The
#     failure reads like a compromised mirror rather than an old image, which
#     is why this is a step of its own instead of a flag on the line below.
# ---------------------------------------------------------------------------
RUN pacman -Sy --noconfirm --needed archlinux-keyring \
 && pacman -Su --noconfirm

# ---------------------------------------------------------------------------
#  2. What setup-dotFiles.sh reaches for before it installs anything
#
#     Only the cheap prerequisites, never yay-apps.txt itself. That list holds
#     four kernels, VirtualBox and a browser; installing it at build time would
#     cost gigabytes to prove something a container cannot prove anyway, and it
#     would hide the very failures the test exists to catch - a run has to be
#     free to attempt the install and be judged on what happens.
#
#     git       install_yay, install_fzf, and every `git config` step
#     openssh   ssh-keygen in install_sshkey
#     curl      the tailscale installer is piped straight from the network
#     rsync     the shipped bashrc aliases `cp` to it, so every new shell needs
#               it present or the alias is a landmine
#     tmux      so the installed tmux.conf can actually be loaded and checked
#     fastfetch the bashrc greeting; neofetch was archived upstream in 2024 and
#               dropped from the official repositories, and this is what the
#               bashrc falls back to
#     ripgrep / fd / bat
#               optional accelerators that fzf.bash probes for. Without them
#               the file silently takes its fallback branches and a smoke test
#               never exercises the paths people actually run.
#
#     sudo and base-devel are already in the base image; they are named anyway
#     so that a slimmer --build-arg base still produces a working box.
# ---------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        base-devel sudo git openssh curl rsync tmux less \
        fastfetch ripgrep fd bat ca-certificates

# ---------------------------------------------------------------------------
#  3. Locale and timezone
#     LANG is exported only once the locale exists - setting it any earlier
#     makes every later command complain "cannot change locale", and that noise
#     lands in the middle of the setup script's own output where it reads as a
#     defect in the script.
# ---------------------------------------------------------------------------
RUN sed -i -e 's/^#\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
 && locale-gen \
 && echo 'LANG=en_US.UTF-8' > /etc/locale.conf \
 && ln -snf "/usr/share/zoneinfo/${DOT_TZ}" /etc/localtime \
 && echo "${DOT_TZ}" > /etc/timezone

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
#  4. Unprivileged user with passwordless sudo
#
#     Unprivileged is not politeness, it is a requirement: makepkg refuses to
#     run as root, so a root-only image cannot build yay and cannot execute
#     install_yay at all. Running as root would also silently redirect the
#     whole test - $HOME becomes /root, and bashrc, tmux.conf, the SSH key and
#     RAMDISC would all be installed for a user who is not the one under test.
#
#     The sudo rule is a validated drop-in rather than an append to
#     /etc/sudoers: a malformed line appended to that file locks sudo out of
#     the image completely, and `visudo -c` is the only thing standing between
#     a typo here and an unusable build.
#
#     -s /bin/bash is explicit because useradd otherwise takes the shell from
#     /etc/default/useradd, which is /bin/sh - and this repository is entirely
#     bash dotfiles, so `su - user` would land somewhere they do not apply.
# ---------------------------------------------------------------------------
RUN groupadd -g "${DOT_GID}" "${DOT_USER}" \
 && useradd -m -u "${DOT_UID}" -g "${DOT_GID}" -G wheel -s /bin/bash "${DOT_USER}" \
 && printf '%s:%s\n' "${DOT_USER}" "${DOT_PASSWORD}" | chpasswd \
 && printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${DOT_USER}" > /etc/sudoers.d/99-dotfiles \
 && chmod 0440 /etc/sudoers.d/99-dotfiles \
 && visudo -c -f /etc/sudoers.d/99-dotfiles \
 && mkdir -p /app \
 && chown "${DOT_UID}:${DOT_GID}" /app

# ---------------------------------------------------------------------------
#  5. Trusting the bind-mounted checkout
#     git refuses to operate inside a directory owned by somebody else, and
#     under docker - or rootless podman without --userns=keep-id - /app is
#     exactly that. The refusal surfaces as "detected dubious ownership",
#     which reads like a repository problem and stops the git steps dead. A
#     blanket exemption is acceptable in a throwaway test box and nowhere
#     else, so it is set here rather than in any dotfile the script installs.
# ---------------------------------------------------------------------------
RUN git config --system --add safe.directory '*'

# ---------------------------------------------------------------------------
#  6. yay
#     Built here, as the unprivileged user, so that a test run exercises the
#     yay path instead of stopping at install_yay. Pre-installing it does not
#     hide a bug: install_yay is expected to detect an existing yay and skip,
#     and this image is what proves it does.
#
#     yay-bin rather than yay is deliberate and matches what the setup script
#     itself clones - it ships a prebuilt binary, so the build costs seconds
#     instead of compiling the Go toolchain's worth of dependencies.
# ---------------------------------------------------------------------------
USER ${DOT_USER}
WORKDIR /home/${DOT_USER}

RUN git clone --depth 1 https://aur.archlinux.org/yay-bin.git /tmp/yay-bin \
 && cd /tmp/yay-bin \
 && makepkg -si --noconfirm \
 && cd / \
 && rm -rf /tmp/yay-bin

# ---------------------------------------------------------------------------
#  7. Trim
#     The package cache only. The pacman sync databases stay: the whole point
#     of the box is that setup-dotFiles.sh can run `pacman -S` inside it, and
#     dropping the databases would force a full refresh on every single run.
# ---------------------------------------------------------------------------
USER root
RUN rm -rf /var/cache/pacman/pkg/* \
           "/home/${DOT_USER}/.cache/yay" \
           /tmp/* /var/tmp/* \
 && rm -rf /usr/share/doc/*

# ---------------------------------------------------------------------------
#  8. What this box deliberately cannot test
#
#     There is no systemd here - PID 1 is bash, not an init - so every
#     `systemctl` call in install_docker_configuration and the tailscale step
#     will fail, and that is not a defect in the image. A run inside a
#     container should notice where it is and skip them; both engines leave a
#     marker for exactly this purpose:
#
#         podman   /run/.containerenv
#         docker   /.dockerenv
#
#     Kernel packages, VirtualBox modules and anything that wants a real
#     /sys are in the same category: out of scope by construction, not
#     temporarily broken.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
#  9. Final image metadata
#     The dotfiles.* labels are here so a runner can read the identity back out
#     of the image rather than assuming it - which is what makes overriding
#     DOT_UID/DOT_GID useful instead of merely possible.
# ---------------------------------------------------------------------------
USER ${DOT_USER}
WORKDIR /app

LABEL org.opencontainers.image.title="setup-dotfiles-test" \
      org.opencontainers.image.description="Arch Linux test environment for setup-dotFiles.sh" \
      org.opencontainers.image.authors="Mateusz Okulanis" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.created="${DOT_BUILD_DATE}" \
      dotfiles.user="${DOT_USER}" \
      dotfiles.uid="${DOT_UID}" \
      dotfiles.gid="${DOT_GID}"

CMD ["bash"]
