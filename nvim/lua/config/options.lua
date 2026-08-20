-- ===========================================================================
--  setup-DotFiles :: Neovim options (loaded by LazyVim before plugins)
--
--  Identical to podman_base's lua/config/options.lua - only the comments that
--  described the container were rewritten for a host. No option was changed:
--  the editor must feel the same in the container and on the machine.
-- ===========================================================================

local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false
opt.signcolumn = "yes"
opt.termguicolors = true

opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.softtabstop = 4
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true
opt.inccommand = "split"

opt.splitright = true
opt.splitbelow = true

opt.updatetime = 200
opt.timeoutlen = 400
opt.confirm = true

-- Persistent undo lives under $XDG_STATE_HOME (~/.local/state/nvim/undo), so
-- undo history survives closing the editor, logging out and rebooting.
opt.undofile = true
opt.undolevels = 10000
opt.swapfile = false

-- Uses the session clipboard through wl-clipboard on Wayland or xclip on X11;
-- harmless in a plain TTY, where it silently does nothing.
opt.clipboard = "unnamedplus"

-- Grep through ripgrep, which the package list installs.
opt.grepprg = "rg --vimgrep --smart-case"
opt.grepformat = "%f:%l:%c:%m"

-- LazyVim reads these globals.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.lazyvim_picker = "auto"
vim.g.autoformat = true
