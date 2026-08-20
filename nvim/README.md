# Neovim configuration

A [LazyVim](https://www.lazyvim.org/) setup, ported one to one from the
`podman_base` work container so that the editor behaves identically on this
host and inside the container. The single difference is that the host has
internet: everything the container bakes in at build time is fetched here on
first start instead. Nothing was dropped, no list was shortened.

## Layout

| Path | What it is |
| --- | --- |
| `init.lua` | Entry point; the LazyVim starter's single `require("config.lazy")`. |
| `lua/config/lazy.lua` | lazy.nvim bootstrap and `require("lazy").setup()`. |
| `lua/config/options.lua` | Editor options, loaded by LazyVim before the plugins. |
| `lua/plugins/dotfiles-plugins.lua` | Plugins added on top of LazyVim: catppuccin, diffview, oil, lazygit keys, LSP/format/lint settings. |
| `lua/plugins/dotfiles-extras.lua` | The LazyVim "extras" we enable, imported only when the installed LazyVim really has them. |
| `lua/plugins/dotfiles-ensure.lua` | The Mason package list and the tree-sitter language list, kept active because we are online. |
| `bootstrap.lua` | Optional install-time helper. Neovim never loads it by itself; see below. |

`lua/config/autocmds.lua` and `lua/config/keymaps.lua` are optional - LazyVim
loads them only if they exist. Create them when you want them.

## Installation

`setup-dotFiles.sh` copies this tree to `~/.config/nvim`. To do it by hand:

```sh
mkdir -p ~/.config
cp -a nvim ~/.config/
nvim --headless "+Lazy! sync" +qa                          # installs LazyVim
nvim --headless "+Lazy! sync" +qa                          # picks up the extras
nvim --headless -c "luafile $HOME/.config/nvim/bootstrap.lua"   # servers + parsers
```

The sync runs twice on purpose: `dotfiles-extras.lua` can only see which
LazyVim extras exist once LazyVim itself is on disk. This is the same reason
`podman_base`'s Containerfile syncs repeatedly during the build.

The third line is optional but recommended. `+Lazy! sync` quits while Mason is
still downloading language servers, and Mason kills those downloads on the way
out; `bootstrap.lua` waits for Mason and for the tree-sitter parsers to finish.
Skip it and the same installs simply happen the first time you open the editor
for real. Either way, watch them with `:Mason`, `:Lazy` and `:checkhealth`.

`shellcheck`, `ripgrep`, `fd`, `lazygit`, `tree-sitter-cli` and the language
runtimes are system packages from `yay-apps.txt`, not Mason packages.

## Adding your own plugins

Put them in a **new** file under `lua/plugins/`, for example
`lua/plugins/my-plugins.lua`:

```lua
return {
  { "folke/zen-mode.nvim", cmd = "ZenMode" },
}
```

Every `.lua` file in `lua/plugins/` is picked up automatically, and the specs
are merged, so several files can configure the same plugin.

Keep your own plugins out of the `dotfiles-*.lua` files and out of
`config/`: a reinstall overwrites the files that ship with this repo, and a
file it does not know about is left alone. If you do need to change a shipped
file, change it here in the repository and reinstall from it, so the edit
survives.
