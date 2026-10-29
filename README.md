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

`setup-dotFiles.sh` walks through twenty-one steps in a fixed order and asks a Y/n question before
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

The script finds its data files (`bashrc`, `zshrc`, `shell/`, `audio/`, `yay-apps.txt` and the
rest, see section 11) next to itself, not in the current directory, so
`~/src/setup-DotFiles/setup-dotFiles.sh` works from anywhere. It needs the whole checkout: there
are too many files now to fetch them one by one, so clone.

## 5 Invoking setup-dotFiles.sh

```
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

The steps run in this order, each behind its own Y/n question. `./setup-dotFiles.sh --help` prints
the same list.

**1. system update.** `pacman -Syu`, then `base-devel` and `git` in a transaction of their own, so
that a missing cosmetic package cannot take the toolchain down with it.

**2. bashrc.** Installs `bashrc` as `~/.config/setup-dotfiles/bashrc` and adds one guarded
`source` line to `~/.bashrc` between `# >>> setup-dotFiles: bashrc >>>` markers. It also
installs the files bash and zsh share (`shell/*.sh` into `~/.config/shell/`), `blerc` as `~/.blerc`
and `inputrc` as `~/.inputrc`. The first time it touches `~/.bashrc` it keeps one pristine copy at
`~/.bashrc.orig.setup-dotFiles`. Blocks left by older versions (`dotfiles`, `fzf`) are removed.

**3. bash profile.** The same for `~/.bash_profile`, so that a login shell (`ssh host`, a console
login) reads `~/.bashrc` as well.

**4. makepkg.** Installs `makepkg-native.conf` as `/etc/makepkg.conf.d/zz-native.conf`. makepkg
reads that directory after `/etc/makepkg.conf`, so the stock file is never edited and a pacman
upgrade never leaves a `.pacnew` behind. The drop-in edits the stock values instead of restating
them:

| Setting | Value | Why |
|---|---|---|
| `CFLAGS`, `CXXFLAGS` | `-march=x86-64 -mtune=generic` becomes `-march=native` | code for this CPU; `-O2` stays |
| `RUSTFLAGS` | `+ -C target-cpu=native -C opt-level=3` | the same for Rust |
| `MAKEFLAGS` | `-j$(nproc)` | every core; the stock value is `-j1` |
| `BUILDDIR` | `/tmp/makepkg` | builds on tmpfs, no SSD writes |
| `BUILDENV` | `ccache` | a rebuild reuses unchanged objects (20 GB cache) |
| `OPTIONS` | `!debug` | no `-debug` split packages; `lto` stays |
| `COMPRESSZST` | `zstd -c -T0 -1 -` | fast package compression on all cores |

Packages built after this run only on this CPU generation. The step warns when SMT is switched
off in the firmware, which halves the number of build jobs.

**5. yay.** Skipped when `yay` is already on `$PATH`. Otherwise it clones `yay-bin` from the AUR
into a temporary directory, builds it with `makepkg -si`, and removes the directory afterwards.

**6. packages.** Reads `yay-apps.txt` and installs it as one `yay -S --needed` transaction. If that
aborts, it retries one package at a time so the run still installs what it can, and names the ones
that did not resolve.

**7. cachyos kernel.** Builds `linux-cachyos` and `linux-cachyos-headers` from the AUR with
`_processor_opt=native` (the PKGBUILD's own switch for `X86_NATIVE_CPU`; the kernel ignores
makepkg's CFLAGS), in `~/.cache/makepkg-build` because a kernel does not fit in the tmpfs. Then it
sets `GRUB_TOP_LEVEL` so that GRUB boots it by default, and runs `grub-mkconfig`. The stock `linux`
stays installed as the fallback entry. Interactively yay asks before importing the packagers' PGP
keys; read that question once. Expect 20 minutes to an hour.

**8. thermalright lcd.** Thermalright LCD coolers (Frozen Warframe, Trofeo Vision, Assassin Spirit
and Elite Vision, and others) show nothing until a program feeds the screen. This step installs
[TRCC Linux](https://github.com/Lexonight1/thermalright-trcc-linux) (`thermalright-trcc` from the
AUR) with NVIDIA, Wayland and HID support, reloads its udev rules, and starts it at login. It
defaults to yes when one of the USB ids TRCC supports is plugged in (`0416:5302`, `0416:5406`,
`0402:3922`, …) and to no otherwise. Under `--yes` it is skipped when there is no such device.

**9. rgb.** [OpenRGB](https://openrgb.org) for the motherboard's RGB and ARGB headers, which on
Gigabyte boards hang off an ITE "RGB Fusion 2" controller on USB (`048d:5702`). It loads `i2c-dev`
at boot for RGB memory and starts OpenRGB at login with the profile named `default`. Save that
profile once from the GUI; until then OpenRGB starts and changes nothing. Same detection rule as
step 8.

**10. audio.** A PipeWire/WirePlumber profile for USB DACs, the `autoeq` switcher with Denon
AH-D5200/D7200/D9200 impulses, and `m20-dropwatch`. [docs/AUDIO.md](docs/AUDIO.md) explains it.

**11. zsh.** `zshrc` as `~/.config/setup-dotfiles/zshrc`, sourced from `~/.zshrc`; Oh My Zsh,
`fzf-tab`, `zsh-autosuggestions`, `fast-syntax-highlighting`, `zsh-history-substring-search` and
the `mtsh` theme. It offers to make zsh the login shell, but never under `--yes` alone: pass
`--chsh` for that.

**12. ssh key.** An ed25519 key at `~/.ssh/id_ed25519`. An existing key is reported and left
untouched.

**13. libvirt.** Membership of the `libvirt` group, `libvirtd.socket`, and the default guest
network. The group is the whole of the access control: `50-libvirt.rules`, shipped by the libvirt
package, grants `org.libvirt.unix.manage` to that group and to nothing else. The `default` network
ships inactive with autostart off, so the step turns it on, warns when `dnsmasq` is missing, and
reports whether `/dev/kvm` is there.

**14. prompt.** `starship.toml`, the fastfetch greeting (`fastfetch/config.jsonc`), ble.sh (the
nightly tarball, into `~/.local/share/blesh`), and `pkgfile --update` for zsh's command-not-found
plugin.

**15. konsole.** A Konsole profile, `Mok`, with JetBrainsMono Nerd Font Mono and the Catppuccin
Mocha colours, set as the default. Skipped when Konsole is not installed.

**16. ram disk.** `~/RAMDISC` as a symlink to `/dev/shm`.

**17. tmux.** Installs `tmux.conf` as `~/.tmux.conf`, keeping a timestamped backup if the existing
file differs, and installs tpm and its plugins.

**18. neovim.** Copies `nvim/` to `~/.config/nvim/`, then downloads the plugins, language servers
and tree-sitter parsers.

**19. git rules.** `core.fileMode false`, `user.name` and `user.email`, globally. See section 14
before you accept this one.

**20. tailscale.** Installs the `tailscale` package and enables `tailscaled`. Run
`sudo tailscale up` afterwards.

**21. post-install.** A final `yay -Syu` and a trim of the package cache with `paccache -rk2`.

## 7 The shell configuration

bash and zsh share four files in `~/.config/shell/`, written in syntax both shells accept:

| File | What it holds |
|---|---|
| `env.sh` | `PATH` (`~/.local/bin` first), `EDITOR` (nvim, else vim), `LESS`, `BAT_THEME` |
| `aliases.sh` | `l ll la lt tree t2` (eza), `b bp` (bat), `docker`/`docker-compose` → podman, `lg`, `lzp`, `du1`, `ports`, `path`, `serial`, `gs gd gl` |
| `functions.sh` | `mkcd`, `up [N]`, `hlp <cmd>`, `x <archive>` |
| `fzf.sh` | fzf options and colours, `fcd fo fgr fbr fkill flog` |

The classic commands keep their meaning: `ls`, `cat` and `grep` are not aliased to eza, bat or
ripgrep, because `ls -lt` and scripts have to keep working. The new tools get new names.

There is no docker on this setup, only podman: rootless, daemonless, no group that amounts to root.
`docker` and `docker-compose` are aliases for `podman` and `podman-compose`, so typed commands and
old notes keep working.

**bash** (`bashrc`): ble.sh (autosuggestions, syntax highlighting; disable for one session with
`NO_BLE=1 bash`), starship, fzf key bindings (Ctrl-R, Ctrl-T, Alt-C), zoxide (`z`, `zi`),
unlimited timestamped history written after every command, and `cp` as `rsync -avh --progress`
(plain `cp` is `\cp`).

**zsh** (`zshrc`): Oh My Zsh with `git sudo extract colored-man-pages command-not-found copypath
copybuffer` and the four plugins above. Tab opens fzf-tab with previews, up and down arrows search
history by the typed prefix, Ctrl-Space accepts a suggestion, and Esc Esc prepends sudo. The
prompt is the `mtsh` theme or starship: `prompt-use starship` or `prompt-use mtsh` switches and
remembers the choice.

Both show a fastfetch greeting, except in tmux, VS Code, Claude Code and nested shells.
`DOTFILES_NO_FETCH=1` silences it.

**Local settings** go to `~/.config/shell/local.sh` (both shells; created from
`shell/local.sh.example` and never overwritten) or to `~/.bashrc.local` and `~/.zshrc.local`. All
of them are sourced last.

**`bash_profile`** makes a *login* shell read `~/.bashrc`, and prints nothing, so it is safe for
`scp` and `rsync`.

**`tmux.conf`**: `C-Space` as the prefix, mouse on, vi-style copy mode, splits that keep the
current directory, and tpm with sensible, resurrect and continuum.

**`nvim/`**: a LazyVim configuration; see `nvim/README.md`.

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
the NVIDIA driver, the KVM stack, a browser, desktop applications, audio. The second is the set the dotfiles in
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
bashrc, zshrc           the shell configuration, sourced from ~/.bashrc and ~/.zshrc
bash_profile            makes a login shell read ~/.bashrc
shell/                  env.sh aliases.sh functions.sh fzf.sh local.sh.example
blerc, inputrc          ble.sh and readline settings
starship.toml           the prompt
fastfetch/config.jsonc  the greeting
konsole/                Mok.profile and CatppuccinMocha.colorscheme
makepkg-native.conf     the makepkg drop-in
audio/                  PipeWire and WirePlumber profile, AutoEq impulses, autoeq, m20-dropwatch
docs/AUDIO.md           why the audio profile looks the way it does
tmux.conf               installed as ~/.tmux.conf
nvim/                   LazyVim configuration; see nvim/README.md
img/logo.jpeg           the logo above
LICENSE                 GPLv3
```

What a full run leaves on the machine:

```
~/.bashrc, ~/.zshrc, ~/.bash_profile   one guarded source line each
~/.config/setup-dotfiles/              bashrc, zshrc, bash_profile
~/.config/shell/                       env.sh aliases.sh functions.sh fzf.sh, local.sh (yours)
~/.blerc, ~/.inputrc                   ble.sh and readline
~/.config/starship.toml                the prompt
~/.config/fastfetch/config.jsonc       the greeting
~/.local/share/blesh/                  ble.sh
~/.local/share/konsole/                Mok.profile, CatppuccinMocha.colorscheme
~/.config/pipewire/pipewire.conf.d/99-audiophile.conf
~/.config/wireplumber/wireplumber.conf.d/99-audiophile.conf
~/.local/share/autoeq/denon/           AutoEq impulses
~/.local/bin/autoeq, m20-dropwatch
~/.config/autostart/                   trcc-linux.desktop, openrgb.desktop
~/.oh-my-zsh/                          with custom/plugins and custom/themes/mtsh.zsh-theme
~/.tmux.conf, ~/.tmux/plugins/tpm
~/.config/nvim/
~/.ssh/id_ed25519                      and .pub
~/RAMDISC                              symlink to /dev/shm
~/.gitconfig                           user.name, user.email, core.fileMode false
/etc/makepkg.conf.d/zz-native.conf     the makepkg drop-in
/etc/modules-load.d/i2c-dev.conf       i2c-dev at boot, for OpenRGB
/etc/default/grub                      GRUB_TOP_LEVEL = linux-cachyos (backup next to it)
*.bak.YYYYmmdd-HHMMSS                  a backup, whenever an existing file differed
```

## 12 Environment

```
ASSUME_YES=1             same as --yes
GIT_AUTHOR               global git user.name   (same as --git-name)
GIT_EMAIL                global git user.email  (same as --git-email)
NO_COLOR                 suppress coloured output; both scripts honour it
TMPDIR                   where the yay build and the ~/.bashrc rewrite happen
DOTFILES_NO_FETCH=1      silence the fastfetch greeting in bash and zsh
NO_BLE=1                 start bash without ble.sh
AUTOEQ_SINK              the output autoeq puts the EQ in front of
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
- `makepkg-native.conf` makes every AUR build specific to this CPU generation. Do not copy the
  built packages to another machine.
- The CachyOS kernel step and the TRCC, OpenRGB and NVIDIA packages are tied to the maintainer's
  hardware (Ryzen 7800X3D, RTX 50, Gigabyte B650M, a Thermalright LCD cooler). The hardware steps
  detect their devices, but the package list does not; trim it for other machines.
- `--yes` generates the SSH key without a passphrase. That is the price of not hanging on
  `ssh-keygen`'s prompt.
- `yay-apps.txt` carries the maintainer's own machine as well as the dotfiles' dependencies: the
  NVIDIA driver, the KVM/libvirt stack, a browser. It is meant to be edited.
- The container cannot exercise systemd, kernel modules, udev, USB devices or `/dev/kvm`. A green
  run in there does not prove the kernel, libvirt, TRCC or OpenRGB steps work on metal.
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
