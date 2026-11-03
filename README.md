# setup-dotFiles

    setup-dotFiles.sh - set up a fresh Debian 13 (trixie) workstation, one question at a time

Author: Mateusz Okulanis.  GNU GPLv3 or later.  See `LICENSE`.

<p align="center">
  <img src="img/logo.jpeg" alt="setup-dotFiles" width="500"/>
</p>

This is the **`trixie`** branch: everything here installs with `apt-get`, on Debian 13. The
repository supports exactly two targets:

| Branch | Target |
|---|---|
| `master` | Arch Linux (`pacman` and `yay`) |
| `trixie` | Debian 13 (`apt-get`) - this one |

No other system or release is supported. Both branches carry the same dotfiles, the same steps and the
same helpers; only the package layer differs, and nothing on this branch will run on Arch.

---

## 1 Introduction

A new machine, and the same evening spent again: install the packages, paste the same `.bashrc`,
generate an SSH key, join the `libvirt` group, remember what else there was. This repository is that
evening written down once.

`setup-dotFiles.sh` walks through sixteen steps in a fixed order and asks a Y/n question before
each one, so a run can be steered a single answer at a time. Every step is idempotent by design:
running it twice leaves the machine exactly as running it once did. The block it adds to
`~/.bashrc` is delimited and replaced rather than appended; an SSH key that already exists is never
regenerated; a config file that already matches is left alone, and one that differs is backed up
before it is replaced.

Nothing has to be taken on trust, either. `--dry-run` prints every command the script would run and
executes none of them, and `run.sh` builds a throwaway Debian trixie container in which the whole
thing can be run for real - `apt-get`, `ssh-keygen`, the upstream Neovim download and all - without
going anywhere near the machine you are sitting at.

## 2 Synopsis

```
setup-dotFiles.sh [OPTION]...
run.sh [OPTION]... [-- COMMAND...]
```

Both take `--help`.

## 3 Requirements

Debian 13 (trixie) with `apt-get` and `sudo`, bash 4.4 or newer, internet access, and a normal
user account that may use sudo. The script refuses to run as root: as root `$HOME` is `/root`, so
the dotfiles, the SSH key, the Oh My Zsh checkout and the RAM disk shortcut would all be installed
for the wrong user. `preflight` checks each of these and stops before anything is changed. Another
Debian release is a warning, not a refusal - most package names carry over - but the package list
and the upstream tool versions were checked against trixie only.

A Debian installed **with a root password** leaves the first user outside the `sudo` group.
`preflight` says so; fix it as root and log in again:

```sh
su - -c 'usermod -aG sudo YOUR_USER'
```

A `sudoers.d` rule works as well, which is why this is a warning and not a refusal.

The test environment needs podman instead. Nothing else.

## 4 Installation

There is no installation. Clone the repository and run the script from it:

```sh
git clone -b trixie https://github.com/FPGArtktic/setup-DotFiles.git
cd setup-DotFiles
./setup-dotFiles.sh
```

`-b trixie` is not optional. `master` is the Arch Linux branch. A raw URL for a single file - to
read the package list before cloning, say - uses `/trixie` in the same way:
`https://raw.githubusercontent.com/FPGArtktic/setup-DotFiles/trixie/apt-apps.txt`.

The script finds its data files (`bashrc`, `zshrc`, `shell/`, `audio/`, `apt-apps.txt` and the
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
dry  would run: sudo apt-get install build-essential git curl ca-certificates jq xz-utils
```

and touches nothing - not `~/.bashrc`, not your git identity, not `~/.ssh`, not `/opt`. It still
reads the machine, so it reports honestly which steps would be skipped because the work is already
done.

### 5.2 -y, --yes

`--yes` means *do not ask*. It never means *do not act*. It is passed down to the tools underneath
as well, because a run that stops at somebody else's prompt is not unattended. Every `apt-get` call
gets `-y`, runs with `DEBIAN_FRONTEND=noninteractive` so no debconf dialog can open, and gets
`-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold`: when a package ships a
new version of a configuration file you have changed, yours is kept - the answer that cannot break a
running service. Without `--yes` all of that is left to the person at the keyboard.

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

**1. system update.** `apt-get update` and `apt-get full-upgrade`, then `build-essential`, `git`,
`curl`, `ca-certificates`, `jq` and `xz-utils` in a transaction of their own, so that a missing
cosmetic package cannot take the toolchain down with it. These are what the later steps call
directly: git for every clone, curl and jq for the verified upstream downloads, xz for the Nerd
Font tarball. `fastfetch` follows on its own; if it fails, that is a warning.

**2. bashrc.** Installs `bashrc` as `~/.config/setup-dotfiles/bashrc` and adds one guarded
`source` line to `~/.bashrc` between `# >>> setup-dotFiles: bashrc >>>` markers. It also
installs the files bash and zsh share (`shell/*.sh` into `~/.config/shell/`), `blerc` as `~/.blerc`
and `inputrc` as `~/.inputrc`. The first time it touches `~/.bashrc` it keeps one pristine copy at
`~/.bashrc.orig.setup-dotFiles`. Blocks left by older versions (`dotfiles`, `fzf`) are removed.

**3. bash profile.** The same for `~/.bash_profile`, so that a login shell (`ssh host`, a console
login) reads `~/.bashrc` as well.

**4. packages.** Reads `apt-apps.txt`, runs `apt-get update` (the index may be stale when step 1
was declined), and installs the whole list as one `apt-get install` transaction. apt-get refuses the
entire transaction when a single name does not resolve, so if it fails the step retries one package
at a time, installs what it can, and names the ones that did not resolve.

**5. audio.** A PipeWire/WirePlumber profile for USB DACs, the `autoeq` switcher with Denon
AH-D5200/D7200/D9200 impulses, and `m20-dropwatch`. [docs/AUDIO.md](docs/AUDIO.md) explains it.
PipeWire and WirePlumber are trixie's defaults.

**6. zsh.** `zshrc` as `~/.config/setup-dotfiles/zshrc`, sourced from `~/.zshrc`; Oh My Zsh,
`fzf-tab`, `zsh-autosuggestions`, `fast-syntax-highlighting`, `zsh-history-substring-search` and
the `mtsh` theme. It offers to make zsh the login shell, but never under `--yes` alone: pass
`--chsh` for that.

**7. ssh key.** An ed25519 key at `~/.ssh/id_ed25519`. An existing key is reported and left
untouched.

**8. libvirt.** Membership of the `libvirt` group, `libvirtd.socket`, and the default guest
network. The group is the whole of the access control: Debian's `libvirtd.conf` sets
`unix_sock_group = "libvirt"`, so members of that group may open the read-write socket and nobody
else may. The socket is left alone when the modular daemons (`virtqemud.socket`) are already in
use. Debian usually marks the `default` network to autostart but not always active, so the step
sets both, asks whether `dnsmasq-base` is installed when the network will not start, and reports
whether `/dev/kvm` is there. Skipped when libvirt is not installed.

**9. prompt.** `starship.toml`, the fastfetch greeting (`fastfetch/config.jsonc`), ble.sh (the
nightly tarball, into `~/.local/share/blesh`), and three things Debian does differently:

- the **JetBrainsMono Nerd Font**, which Debian does not package: the latest
  `JetBrainsMono.tar.xz` release from `ryanoasis/nerd-fonts`, checksum-verified (see step 13),
  of which only the `JetBrainsMonoNerdFontMono-*.ttf` files are unpacked into
  `~/.local/share/fonts/JetBrainsMonoNerd`, followed by `fc-cache`. Skipped when a `.ttf` is
  already there.
- **`~/.local/bin/bat` -> `batcat` and `~/.local/bin/fd` -> `fdfind`**. Debian installs both
  tools under other names; a link, not an alias, because the fzf previews, fzf-tab and
  `functions.sh` call them from inside other programs' command lines, where no alias reaches. A
  link is only made when `batcat`/`fdfind` is installed, and an existing `~/.local/bin` entry that
  is not the script's own link is left alone.
- **`command-not-found`** in place of Arch's `pkgfile`, for zsh's command-not-found plugin. The
  step runs `update-command-not-found` once; after that the database refreshes itself on every
  `apt-get update`.

**10. konsole.** A Konsole profile, `Mok`, with JetBrainsMono Nerd Font Mono and the Catppuccin
Mocha colours, set as the default. Skipped when Konsole is not installed - and it is not on
`apt-apps.txt` (section 10).

**11. ram disk.** `~/RAMDISC` as a symlink to `/dev/shm`.

**12. tmux.** Installs `tmux.conf` as `~/.tmux.conf`, keeping a timestamped backup if the existing
file differs, and installs tpm and its plugins.

**13. neovim.** Trixie ships Neovim 0.10.4 and tree-sitter 0.22.6. LazyVim needs Neovim 0.11.2,
and the nvim-treesitter main branch cannot build its parsers with that tree-sitter, so neither
Debian package is on the list and the step installs both from upstream:

| Tool | Minimum | Release asset | Installed as |
|---|---|---|---|
| Neovim | 0.11.2 | `nvim-linux-x86_64.tar.gz` | `/opt/nvim-linux-x86_64`, linked as `/usr/local/bin/nvim` |
| tree-sitter CLI | 0.25.0 | `tree-sitter-linux-x64.gz` | `/usr/local/bin/tree-sitter` |

Each is left alone when the version already on `$PATH` meets the minimum. Neovim is unpacked into
`/opt/nvim-linux-x86_64.new` and swapped in with one `mv`, so an interrupted download never leaves a
half-written editor. Every download is checked against the sha256 digest GitHub publishes for that
release asset, read from the releases API with `jq`: a mismatch deletes the file, and without `jq`
the download is refused outright - nothing from the network goes into `/opt` or `/usr/local`
unchecked. A missing tree-sitter is a warning (parsers will not compile), a missing Neovim a
failure.

Then it copies `nvim/` to `~/.config/nvim/` - an existing configuration that differs is first
copied aside to `~/.config/nvim.bak.YYYYmmdd-HHMMSS` - and, after one more question, downloads the
plugins, language servers and tree-sitter parsers.

**14. git rules.** `core.fileMode false`, `user.name` and `user.email`, globally. See section 14
before you accept this one.

**15. tailscale.** Debian does not package Tailscale, and the step does not pipe Tailscale's
`install.sh` into a root shell. It does by hand the two things that script does on Debian: it
fetches the signing key into `/usr/share/keyrings/tailscale-archive-keyring.gpg` and the apt source
into `/etc/apt/sources.list.d/tailscale.list`, both over HTTPS from
`pkgs.tailscale.com/stable/debian/<codename>`, then runs `apt-get update`, installs the
`tailscale` package and enables `tailscaled`. From then on tailscale updates with the rest of the
system. Run `sudo tailscale up` afterwards; installing it does not connect it.

**16. post-install.** A final `apt-get update` and `apt-get full-upgrade`, and a trim of the
package cache with `apt-get autoclean`. `apt-get autoremove` is deliberately left to you, since it
is the one operation that can uninstall something wanted; review it with
`apt-get autoremove --dry-run`.

## 7 The shell configuration

bash and zsh share four files in `~/.config/shell/`, written in syntax both shells accept:

| File | What it holds |
|---|---|
| `env.sh` | `PATH` (`~/.local/bin` first), `EDITOR` (nvim, else vim), `LESS`, `BAT_THEME` |
| `aliases.sh` | `l ll la lt tree t2` (eza), `b bp` (bat), `docker`/`docker-compose` → podman, `lg`, `lzp`, `du1`, `ports`, `path`, `serial`, `gs gd gl` |
| `functions.sh` | `mkcd`, `up [N]`, `hlp <cmd>`, `x <archive>` |
| `fzf.sh` | fzf options and colours, `fcd fo fgr fbr fkill flog` |

These files call `bat` and `fd` by their upstream names. On Debian that works because of the links
the prompt step makes in `~/.local/bin` (step 9), which `env.sh` puts first on `PATH`.

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

`run.sh` builds a Debian 13 image (`debian:trixie`) from `Containerfile` and drops you into it with
this repository bind-mounted at `/app`. Inside there is a user called `user`, password `user`, in
the `sudo` group and with passwordless sudo, and only the cheap prerequisites the script reaches
for before it installs anything (`sudo`, `git`, `openssh-client`, `curl`, `jq`, `xz-utils` and a
few more). `apt-apps.txt` itself is never baked in, so a run has to attempt the package install and
is judged on what happens - and `setup-dotFiles.sh` can be run for real, twice in a row if you want
to prove it is idempotent, on a machine that gets thrown away afterwards.

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

The image is tagged `setup-dotfiles-trixie-test-$USER:latest` - the uid is baked in, so two users
on one machine must not share a tag.

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

There is no systemd in there - PID 1 is bash - so `systemctl` steps (libvirt, tailscale) are
skipped, not failed; `setup-dotFiles.sh` notices the container from the marker file podman leaves
(`/run/.containerenv`). Kernel modules, `/dev/kvm` and anything wanting a real `/sys` are out of
scope by construction.

The mount is **read-write**, which is deliberate - it is how you inspect the damage afterwards -
but it is also why you should not point this at a tree you care about.

## 9 Examples

The first five minutes on a new machine:

```sh
git clone -b trixie https://github.com/FPGArtktic/setup-DotFiles.git
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

`apt-apps.txt` is one package name per line. Blank lines and `#`-comments are dropped, duplicates
are dropped, and the surviving names are passed as separate arguments - never as an unquoted
`$(cat ...)` the shell could glob-expand. Annotating the file is free, and the file itself explains
its own rules.

Check a name before you add it:

```sh
apt-cache policy lazygit
```

That is not pedantry. `apt-get` refuses the *whole* transaction on one unresolvable name. The step
then falls back to one package at a time, but a typo still costs a slow second pass and a failed
step. Debian also names a good many packages differently from Arch (`build-essential`, `fd-find`,
`keepass2`, `gvfs-backends`, ...); the comments in the file say where.

The list is well over a hundred packages, in two halves. The first is the maintainer's own machine:
the KVM stack, desktop applications, audio, both CPU microcode packages. The second is the set the
dotfiles in this repository actually invoke - `eza`, `bat`, `fd-find`, `fzf`, `ripgrep`, the
Neovim toolchain, the clipboard bridges - and trimming that half is what makes the aliases and the
editor quietly stop working. Trim the first half to taste; read the comments before trimming the
second.

Some packages are left out on purpose, each with a comment in the file:

- **`neovim`** and **`tree-sitter-cli`**: too old in trixie; step 13 installs upstream releases.
- **`konsole`**: on a GNOME machine it pulls in a large part of KDE. Add it if you use it; the
  konsole step configures it whenever it is installed.
- **`iwd`**: Debian enables `iwd.service` on install, and with NetworkManager still configured for
  `wpa_supplicant` the two fight over the Wi-Fi card.
- **`usbguard`**: Debian starts its daemon on install with a policy of the devices plugged in at
  that moment, so the next keyboard or stick you plug in is blocked.
- **`dnsmasq`**: `dnsmasq-base` is listed instead. libvirt only needs the binary; the full package
  enables a system-wide `dnsmasq.service` that grabs port 53.
- **`telegram-desktop`**: dropped from trixie; Flathub has it.
- **the NVIDIA driver**: it needs `contrib` and `non-free` enabled and is a decision per machine,
  not a dotfiles default.

`tailscale` is absent as well: it has its own opt-in step, so that the machine is not put on a
private network as a side effect of installing a package list.

## 11 Files

In the repository:

```
setup-dotFiles.sh       the installer
run.sh                  builds and enters the test container (podman)
Containerfile           the test image; ARG DOT_BASE_IMAGE/DOT_USER/DOT_UID/DOT_GID/DOT_TZ
.containerignore        the build context is empty by design
apt-apps.txt            the package list
bashrc, zshrc           the shell configuration, sourced from ~/.bashrc and ~/.zshrc
bash_profile            makes a login shell read ~/.bashrc
shell/                  env.sh aliases.sh functions.sh fzf.sh local.sh.example
blerc, inputrc          ble.sh and readline settings
starship.toml           the prompt
fastfetch/config.jsonc  the greeting
konsole/                Mok.profile and CatppuccinMocha.colorscheme
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
~/.local/share/fonts/JetBrainsMonoNerd/  JetBrainsMono Nerd Font Mono
~/.local/bin/bat, ~/.local/bin/fd      links to batcat and fdfind
~/.local/share/konsole/                Mok.profile, CatppuccinMocha.colorscheme
~/.config/pipewire/pipewire.conf.d/99-audiophile.conf
~/.config/wireplumber/wireplumber.conf.d/99-audiophile.conf
~/.local/share/autoeq/denon/           AutoEq impulses
~/.local/bin/autoeq, m20-dropwatch
~/.oh-my-zsh/                          with custom/plugins and custom/themes/mtsh.zsh-theme
~/.tmux.conf, ~/.tmux/plugins/tpm
~/.config/nvim/
~/.ssh/id_ed25519                      and .pub
~/RAMDISC                              symlink to /dev/shm
~/.gitconfig                           user.name, user.email, core.fileMode false
/opt/nvim-linux-x86_64/                Neovim, upstream release
/usr/local/bin/nvim                    link to /opt/nvim-linux-x86_64/bin/nvim
/usr/local/bin/tree-sitter             the tree-sitter CLI, upstream release
/usr/share/keyrings/tailscale-archive-keyring.gpg   Tailscale's signing key
/etc/apt/sources.list.d/tailscale.list              Tailscale's apt repository
*.bak.YYYYmmdd-HHMMSS                  a backup, whenever an existing file differed
```

## 12 Environment

```
ASSUME_YES=1             same as --yes
GIT_AUTHOR               global git user.name   (same as --git-name)
GIT_EMAIL                global git user.email  (same as --git-email)
NO_COLOR                 suppress coloured output; both scripts honour it
TMPDIR                   where the downloads are unpacked and the ~/.bashrc rewrite happens
DOTFILES_NO_FETCH=1      silence the fastfetch greeting in bash and zsh
NO_BLE=1                 start bash without ble.sh
AUTOEQ_SINK              the output autoeq puts the EQ in front of
DOTFILES_IN_CONTAINER=1  set by run.sh inside the container, for anything you run in there
```

Precedence is flags, then environment, then what is already configured on the machine, then the
built-in default.

## 13 Problems

**`apt-get not found - this branch targets Debian 13 (trixie) only`.** You are not on Debian. For
Arch Linux use `master`.

**`... is not Debian 13 (trixie)`.** A warning, not a refusal: another Debian or a derivative.
The run continues, but some names in `apt-apps.txt` may not resolve.

**`do not run this script as root`.** Run it as yourself. As root every dotfile would be installed
into `/root`.

**`<user> is not in the sudo group`.** The usual state after a Debian install with a root
password. Unless a `sudoers.d` rule already allows you, add yourself as root and log in again:
`su - -c 'usermod -aG sudo <user>'`.

**`sudo not found - the package steps cannot run`.** Install it as root first:
`su - -c 'apt-get install sudo'`, then add yourself to the `sudo` group as above.

**`stdin is not a terminal - re-run with --yes`.** Something is feeding the script a pipe or a
closed stdin - a `curl ... | bash`, cron, a CI job. This is refused on purpose. Pass `--yes` if you
really do want every step.

**A package could not be installed.** The name does not resolve. Check it with
`apt-cache policy <name>` and fix `apt-apps.txt`; the bulk transaction already fell back to one
package at a time, so everything else did get installed.

**`jq is not installed - cannot verify ...`.** The Neovim, tree-sitter and Nerd Font downloads are
refused without `jq`, because the checksum cannot be read. Step 1 installs it; so does
`sudo apt-get install jq`.

**`checksum mismatch for ...` or `no sha256 digest published for ...`.** The download was truncated
or does not match what GitHub publishes for that release; the file has already been deleted. Re-run
the step.

**An SSH session looks nothing like the terminal on the desktop.** A login shell does not read
`~/.bashrc`. Install `bash_profile` as `~/.bash_profile` (section 7).

**Tailscale is installed but the machine is not on the network.** Installing it does not connect
it: `sudo tailscale up`.

**`podman is not installed`.** `sudo apt-get install podman` - rootless, with nothing to enable.

## 14 Bugs and limitations

Known, deliberate, or not worth fixing yet:

- The built-in git identity fallback is **the maintainer's name and address**. It is only used when
  the machine has no global identity at all and you gave neither `--git-name`/`--git-email` nor
  `GIT_AUTHOR`/`GIT_EMAIL` - an identity that is already configured is never overwritten without
  the script saying so first - but a fresh machine plus a reflex `y` will stamp somebody else's
  name on your commits. Pass the flags.
- Neovim and the tree-sitter CLI live outside apt. A later `apt-get upgrade` does not touch them,
  and re-running step 13 only replaces them when the installed version is below the minimum. Both
  downloads are x86_64 builds.
- `--yes` generates the SSH key without a passphrase. That is the price of not hanging on
  `ssh-keygen`'s prompt.
- `--yes` keeps your version of any configuration file a package upgrade would replace
  (`--force-confold`). Look for `*.dpkg-dist` files afterwards if you want the new defaults.
- `apt-apps.txt` carries the maintainer's own machine as well as the dotfiles' dependencies: the
  KVM/libvirt stack, desktop applications, microcode for both CPU vendors. It is meant to be edited.
- The container cannot exercise systemd, kernel modules, udev, USB devices or `/dev/kvm`. A green
  run in there does not prove the libvirt or tailscale steps work on metal.
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
