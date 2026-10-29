# setup-dotFiles

    setup-dotFiles.sh - set up a fresh Arch Linux workstation, one question at a time

Author: Mateusz Okulanis.  GNU GPLv3 or later.  See `LICENSE`.

<p align="center">
  <img src="img/logo.jpeg" alt="setup-dotFiles" width="500"/>
</p>

This is the **`arch`** branch: everything here installs with `pacman` and `yay`. The Debian and
Ubuntu versions live on `master`, `bookworm`, `bullseye`, `ubuntu2004`, `ubuntu2204` and
`ubuntu2404`; there is no `apt` code path on this branch and nothing here will run on those systems.

---

## 1 Introduction

A new machine, and the same evening spent again: install the packages, paste the same `.bashrc`,
generate an SSH key, join the `libvirt` group, remember what else there was. This repository is that
evening written down once.

`setup-dotFiles.sh` walks through thirteen steps in a fixed order and asks a Y/n question before
each one, so a run can be steered a single answer at a time. Every step is idempotent by design:
running it twice leaves the machine exactly as running it once did. The block it adds to
`~/.bashrc` is delimited and replaced rather than appended; an SSH key that already exists is never
regenerated; a config file that already matches is left alone, and one that differs is backed up
before it is replaced.

Nothing has to be taken on trust, either. `--dry-run` prints every command the script would run and
executes none of them, and `run.sh` builds a throwaway Arch container in which the whole thing can
be run for real - `pacman`, `yay`, `makepkg`, `ssh-keygen` and all - without going anywhere near
the machine you are sitting at.

## 2 Synopsis

```
setup-dotFiles.sh [OPTION]...
run.sh [OPTION]... [-- COMMAND...]
```

Both take `--help`.

## 3 Requirements

An Arch Linux family system with `pacman` and `sudo`, bash 4.4 or newer, internet access, and a
normal user account. The script refuses to run as root: `makepkg` will not build `yay` for root at
all, and as root `$HOME` is `/root`, so the dotfiles, the SSH key and the RAM disk shortcut would
all be installed for the wrong user. `preflight` checks each of these and stops before anything is
changed.

The test environment needs podman instead. Nothing else.

## 4 Installation

There is no installation. Clone the repository and run the script from it:

```sh
git clone -b arch https://github.com/FPGArtktic/setup-DotFiles.git
cd setup-DotFiles
./setup-dotFiles.sh
```

`-b arch` is not optional. The default branch is the apt one.

The script finds `bashrc`, `fzf.bash`, `tmux.conf` and `yay-apps.txt` next to itself, not in the
current directory, so `~/src/setup-DotFiles/setup-dotFiles.sh` works from anywhere. If you would
rather not clone, those four files and the script are all it needs, and they can be fetched
directly - note `raw.githubusercontent.com`, not `github.com`, which serves an HTML page rather
than the file:

```sh
mkdir setup-dotFiles && cd setup-dotFiles
base=https://raw.githubusercontent.com/FPGArtktic/setup-DotFiles/arch
for f in setup-dotFiles.sh bashrc fzf.bash tmux.conf yay-apps.txt; do
    curl -fsSLO "$base/$f"
done
chmod +x setup-dotFiles.sh
```

The `chmod` matters: downloaded files are not executable. This gets you the installer and nothing
else - `zshrc`, `bash_profile` and the Neovim configuration are not in that list, so clone if you
want them (section 7).

## 5 Invoking setup-dotFiles.sh

```
  --dry-run           print what would be done, change nothing
  -v, --verbose       show each command and each skipped step
  -y, --yes           answer yes to every question (implies non-interactive)
  --git-name NAME     global git user.name to configure
  --git-email ADDR    global git user.email to configure
  -V, --version       print the version and exit
  -h, --help          print this help and exit
  --                  end of options
```

### 5.1 --dry-run

Every command that changes the machine goes through one `run` helper, and `--dry-run` is checked
there. That is what makes the flag worth having: there is no second path a mutation could take, so
a dry run prints lines like

```
dry  would run: sudo pacman -S --needed -- base-devel git
```

and touches nothing - not `~/.bashrc`, not your git identity, not `~/.ssh`. It still reads the
machine, so it reports honestly which steps would be skipped because the work is already done.

### 5.2 -y, --yes

`--yes` means *do not ask*. It never means *do not act*. It is passed down to the tools underneath
as well - `pacman`, `yay` and `makepkg` all get `--noconfirm` - because a run that stops at
somebody else's prompt is not unattended.

Two consequences worth knowing before you use it. The SSH key is generated with an **empty
passphrase**, since `ssh-keygen` would otherwise ask for one twice and hang forever; the script
warns when it does this. And without `--yes` the script refuses to run at all when stdin is not a
terminal, rather than treating end-of-input as consent - so `curl ... | bash` fails loudly instead
of quietly installing everything.

`--dry-run --yes` together is a full unattended rehearsal, which is the useful thing to run first.

### 5.3 Exit status

`0` when every step that ran succeeded, `1` when at least one failed or preflight refused to
continue, `130` on ctrl-C, `143` on SIGTERM. A failing step does not abort the run: it is recorded,
the remaining steps still get their turn, and the summary at the end lists what completed, what was
skipped and what failed.

## 6 What the script does

In this order. Each is a question you can answer `n` to.

**1. system update.** `pacman -Syu`, then `base-devel` and `git` in a transaction of their own -
they are what `makepkg` needs later, and a cosmetic extra that no longer exists in the repositories
must not be able to take the toolchain down with it. `fastfetch` is attempted last and is not
fatal.

**2. bashrc.** Writes `bashrc` into `~/.bashrc` between `# >>> setup-dotFiles: dotfiles >>>` and
its closing marker, removing any earlier block of the same name first. The first time it touches
the file it keeps one pristine copy at `~/.bashrc.orig.setup-dotFiles`.

**3. yay.** Skipped when `yay` is already on `$PATH`. Otherwise it clones `yay-bin` from the AUR
into a temporary directory, builds it with `makepkg -si`, and removes the directory afterwards -
nothing is left in your checkout.

**4. packages.** Reads `yay-apps.txt` and installs it as one `yay -S --needed` transaction. If that
aborts, it retries one package at a time so the run still installs what it can, and names the ones
that did not resolve. This is the long step; see section 10 before you accept it.

**5. ssh key.** An ed25519 key at `~/.ssh/id_ed25519`. An existing key is reported and left
untouched - never overwritten, never prompted about. A new key is followed by the URL for adding it
to GitHub and the public key itself.

**7. libvirt.** Membership of the `libvirt` group, `libvirtd.socket`, and the default guest
network. The group is the whole of the access control: `50-libvirt.rules`, shipped by the libvirt
package, grants `org.libvirt.unix.manage` to that group and to nothing else - no `sudo`, no
editing `libvirtd.conf`. The socket is enabled rather than the service, so `libvirtd` starts on
the first connection instead of at boot; if the modular daemons (`virtqemud` and friends) are
already active the step says so and leaves them alone. The `default` network ships inactive with
autostart off, and a guest created before it is up has no network at all, which reads as a guest
fault - so the step turns it on and warns when `dnsmasq` is missing. It also reports whether
`/dev/kvm` is there, because without VT-x/AMD-V every guest silently falls back to software
emulation and merely feels broken.

VirtualBox was replaced by this. It needed an out-of-tree module rebuilt by DKMS against every
installed kernel - and this list keeps four of them - while KVM is part of the kernel itself.

**8. fzf.** Installs `fzf.bash` as `~/.fzf.bash` and adds a second managed block to `~/.bashrc`
that sources it. `fzf` itself comes from `yay-apps.txt`; the step only falls back to cloning
`junegunn/fzf` into `~/.fzf` when the package is not installed, and the upstream installer is run
with `--no-update-rc` so it cannot append to `~/.bashrc` behind the block's back.

**9. ram disk.** `~/RAMDISC` as a symlink to `/dev/shm` - tmpfs, so it is fast and cleared on
reboot. A link that already points there is left alone; a real file or directory in the way is
refused rather than replaced.

**10. tmux.** Installs `tmux.conf` as `~/.tmux.conf`, keeping a timestamped backup if the existing
file differs. The config clones tpm and installs its plugins the first time tmux starts.

**11. git rules.** `core.fileMode false`, `user.name` and `user.email`, globally. See section 14
before you accept this one.

**12. tailscale.** Installs the `tailscale` package and enables `tailscaled`. Installing Tailscale
does not connect the machine; run `sudo tailscale up` afterwards.

**13. post-install.** A final `yay -Syu` (or `pacman -Syu` when yay is absent) and a trim of the
package cache with `paccache -rk2`. Orphan removal is deliberately left to you - it is the one
operation here that can uninstall something you wanted.

## 7 The shell and editor configuration

`bashrc`, `fzf.bash` and `tmux.conf` are what the steps above install. The rest of the
configuration ships with the repository but is not wired into the script yet, and has to be copied
by hand:

```sh
cp zshrc        ~/.zshrc
cp bash_profile ~/.bash_profile
mkdir -p ~/.config && cp -a nvim ~/.config/
```

What each file is:

**`bashrc`** - unlimited, timestamped history shared between terminals; a two-line prompt ending in
the current git branch; aliases that are only defined when the tool behind them is installed (`eza`,
`bat`, `btop`, `lazygit`, `podman-tui`); and a `fastfetch` greeting you can silence
with `DOTFILES_NO_FETCH=1`. Your own additions belong in `~/.bashrc.local`, which is sourced last
and is never touched by a reinstall.

**`zshrc`** - the same configuration for zsh: Oh My Zsh, the same history behaviour, the same
aliases, the same fzf options. It uses the `mtsh` theme when that theme is present in
`$ZSH/custom/themes` and falls back to `robbyrussell` when it is not. `~/.zshrc.local` is the local
override.

**`bash_profile`** - one job: make a *login* shell - `ssh host`, a text console login, `su -` -
read `~/.bashrc`, which by definition it otherwise does not. It sources whichever of
`~/.bash_login` or `~/.profile` bash would have read first, so creating it shadows nothing, and it
prints nothing, so it is safe for `scp` and `rsync` sessions.

**`tmux.conf`** - `C-Space` as the prefix, mouse on, vi-style copy mode, splits that keep the
current directory, `M-arrow` pane navigation, and a status line showing the branch of whichever
pane is active. tpm plus sensible/resurrect/continuum are cloned and installed the first time tmux
starts.

**`fzf.bash`** - fzf defaults: ripgrep or fd as the file source, `bat` previews, and the `fcd`,
`fo`, `fgr`, `fbr` and `fkill` helpers.

**`nvim/`** - a LazyVim configuration, ported from the `podman_base` work container so the editor
behaves the same on both. It has its own documentation in `nvim/README.md`, including the two
headless `Lazy! sync` runs needed on first install.

## 8 The test environment

`run.sh` builds an Arch Linux image from `Containerfile` and drops you into it with this repository
bind-mounted at `/app`. Inside there is a user called `user`, password `user`, with passwordless
sudo, and `yay` already built - so `setup-dotFiles.sh` can be run for real, twice in a row if you
want to prove it is idempotent, on a machine that gets thrown away afterwards.

```
  --podman            accepted for old command lines; podman is the only engine
  --rebuild           build with --no-cache --pull, ignoring every cached layer
  --no-build          do not build, run the image that is already tagged
  --build-only        build the image and stop
  --shell             interactive shell in the container (this is the default)
  --base IMAGE        override the base image passed to the Containerfile
  --tag REF           image to build and run
  --dry-run           print the engine commands instead of running them
  -h, --help          this text
  --version           version and licence
```

### 8.1 podman only

The test environment runs on podman and nothing else: it is rootless and daemonless, so there is
no service to enable and no group to join before the first run. `--file` is always passed
explicitly, so the build does not depend on the current directory.

Ownership of the mounted checkout is handled for both podman modes. Under rootless podman the
container lives in a user namespace, so `--userns=keep-id` is added to map you onto the image user.
Under rootful podman a container uid *is* that host uid, so your uid is baked into the image at
build time with `--build-arg DOT_UID` and no run-time flag is needed.

The image is tagged `setup-dotfiles-test-$USER:latest` - the uid is baked in, so two users on one
machine must not share a tag.

### 8.2 Running one command

Everything after `--` is executed in the container instead of a shell, and **its exit status
becomes the script's exit status**, which is what makes this usable from CI:

```sh
./run.sh -- ./setup-dotFiles.sh --dry-run
./run.sh -- bash -c './setup-dotFiles.sh -y && ./setup-dotFiles.sh -y'
```

The second line is the idempotency test: two identical unattended runs, and a non-zero exit if the
second one is not a no-op.

### 8.3 What it cannot test

There is no systemd in there - PID 1 is bash - so `systemctl` steps are skipped, not failed;
`setup-dotFiles.sh` notices the container from the marker file podman leaves
(`/run/.containerenv`). Kernel modules, `/dev/kvm` and
anything wanting a real `/sys` are out of scope by construction.

The mount is **read-write**, which is deliberate - it is how you inspect the damage afterwards -
but it is also why you should not point this at a tree you care about.

## 9 Examples

The first five minutes on a new machine:

```sh
git clone -b arch https://github.com/FPGArtktic/setup-DotFiles.git
cd setup-DotFiles
./setup-dotFiles.sh --dry-run --yes      # rehearse the whole thing, change nothing
./setup-dotFiles.sh --git-name 'Your Name' --git-email you@example.com
```

Try it in a container before trusting it with your own `$HOME`:

```sh
./run.sh                                 # build, then drop into a shell at /app
./run.sh --rebuild                       # forget every cached layer first
./run.sh -- ./setup-dotFiles.sh -y
```

See what it would do, in detail, without doing any of it:

```sh
./setup-dotFiles.sh --dry-run --yes -v   # -v also prints each package name
```

Reinstall the dotfiles after editing them, and nothing else - answer `n` to every other question:

```sh
./setup-dotFiles.sh
```

## 10 Adding your own packages

`yay-apps.txt` is one package name per line. Blank lines and `#`-comments are dropped, duplicates
are dropped, and the surviving names are passed as separate arguments - never as an unquoted
`$(cat ...)` the shell could glob-expand. Annotating the file is free, and the file itself explains
its own rules.

Check a name before you add it:

```sh
yay -Si lazygit
```

That is not pedantry. `yay` aborts the *whole* transaction on one unresolvable name, so a single
typo costs you every other package in the file - which is exactly how this list once failed.

The list is well over a hundred packages, in two halves. The first is the maintainer's own machine:
four kernels, the KVM stack, a browser, desktop applications. The second is the set the dotfiles in
this repository actually invoke - `eza`, `bat`, `fzf`, `ripgrep`, the Neovim toolchain, the
clipboard bridges - and trimming that half is what makes the aliases and the editor quietly stop
working. Trim the first half to taste; read the comments before trimming the second.

`tailscale` is deliberately absent: it has its own opt-in step, so that the machine is not put on a
private network as a side effect of installing a package list.

## 11 Files

In the repository:

```
setup-dotFiles.sh       the installer
run.sh                  builds and enters the test container (podman)
Containerfile           the test image; ARG DOT_BASE_IMAGE/DOT_USER/DOT_UID/DOT_GID/DOT_TZ
.containerignore        the build context is empty by design
yay-apps.txt            the package list
bashrc                  installed as a managed block inside ~/.bashrc
fzf.bash                installed as ~/.fzf.bash, sourced from that block
tmux.conf               installed as ~/.tmux.conf
zshrc                   zsh counterpart of bashrc; copy it yourself (section 7)
bash_profile            makes a login shell read ~/.bashrc; copy it yourself
nvim/                   LazyVim configuration; see nvim/README.md
img/logo.jpeg           the logo above
LICENSE                 GPLv3
```

What a full run leaves on the machine:

```
~/.bashrc                        two delimited blocks: `dotfiles` and `fzf`
~/.bashrc.orig.setup-dotFiles    one pristine copy, taken before the first block
~/.bashrc.local                  yours; sourced last, never touched by a reinstall
~/.fzf.bash                      from fzf.bash
~/.fzf/                          only when fzf was not installed as a package
~/.tmux.conf                     from tmux.conf
~/.tmux.conf.bak.YYYYmmdd-HHMMSS a backup, whenever an existing file differed
~/.ssh/id_ed25519                and .pub
~/RAMDISC                        symlink to /dev/shm
~/.gitconfig                     user.name, user.email, core.fileMode false
```

## 12 Environment

```
ASSUME_YES=1             same as --yes
GIT_AUTHOR               global git user.name   (same as --git-name)
GIT_EMAIL                global git user.email  (same as --git-email)
NO_COLOR                 suppress coloured output; both scripts honour it
TMPDIR                   where the yay build and the ~/.bashrc rewrite happen
DOTFILES_NO_FETCH=1      silence the fastfetch greeting in the installed bashrc
DOTFILES_IN_CONTAINER=1  set by run.sh inside the container, for anything you run in there
```

Precedence is flags, then environment, then what is already configured on the machine, then the
built-in default.

## 13 Problems

**`pacman not found - this branch targets Arch Linux only`.** You are on a Debian or Ubuntu system.
Use `master`, `bookworm`, `bullseye`, `ubuntu2004`, `ubuntu2204` or `ubuntu2404`.

**`do not run this script as root`.** Run it as yourself. `makepkg` refuses root outright, and as
root every dotfile would be installed into `/root`.

**`stdin is not a terminal - re-run with --yes`.** Something is feeding the script a pipe or a
closed stdin - a `curl ... | bash`, cron, a CI job. This is refused on purpose. Pass `--yes` if you
really do want every step.

**A package could not be installed.** The name does not resolve. Check it with `yay -Si <name>` and
fix `yay-apps.txt`; the bulk transaction already fell back to one package at a time, so everything
else did get installed.

**An SSH session looks nothing like the terminal on the desktop.** A login shell does not read
`~/.bashrc`. Install `bash_profile` as `~/.bash_profile` (section 7).

**Tailscale is installed but the machine is not on the network.** Installing it does not connect
it: `sudo tailscale up`.

**`podman is not installed`.** `sudo pacman -S podman` - rootless, with nothing to enable.

**The image build fails on `archlinux-keyring` or a signature.** The base image is stale relative
to the mirrors. `./run.sh --rebuild` pulls a fresh base and redoes the keyring refresh.

## 14 Bugs and limitations

Known, deliberate, or not worth fixing yet:

- The built-in git identity fallback is **the maintainer's name and address**. It is only used when
  the machine has no global identity at all and you gave neither `--git-name`/`--git-email` nor
  `GIT_AUTHOR`/`GIT_EMAIL` - an identity that is already configured is never overwritten without
  the script saying so first - but a fresh machine plus a reflex `y` will stamp somebody else's
  name on your commits. Pass the flags.
- `zshrc`, `bash_profile` and `nvim/` ship with the repository, and their own headers describe
  themselves as installed by `setup-dotFiles.sh`, but no step installs them yet. Section 7 has the
  three commands that do it by hand.
- `--yes` generates the SSH key without a passphrase. That is the price of not hanging on
  `ssh-keygen`'s prompt.
- `yay-apps.txt` carries the maintainer's own machine as well as the dotfiles' dependencies: four
  kernels, the KVM/libvirt stack, a browser. It is meant to be edited.
- The container cannot exercise systemd, kernel modules or `/dev/kvm`. A green run in there does
  not prove the libvirt step works on metal.
- There are no automated assertions after a test run. The regression test is running
  `setup-dotFiles.sh -y` twice and checking that the second run changes nothing.
- `run.sh` mounts the checkout read-write, so a container run can write into your working tree.
- podman warns that `SHELL` is not persisted in OCI images on nearly every build step. It is noise;
  `CMD` is set explicitly at the end of the `Containerfile`.

## 15 Author

Written by Mateusz Okulanis.
Email: FPGArtktic@outlook.com

## 16 Copying

This project is licensed under the GNU General Public License v3.0. See `LICENSE` for the full
text.

Copyright (C) 2025 Mateusz Okulanis

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
