-- ===========================================================================
--  setup-DotFiles :: lazy.nvim bootstrap
--  Based on the LazyVim starter, and on podman_base's lua/config/lazy.lua.
--
--  DIFFERENCE FROM podman_base (the only one): podman_base builds an
--  AIR-GAPPED image, so every plugin is downloaded once at build time and
--  lazy.nvim is forbidden to touch the network afterwards. This machine is a
--  REAL HOST WITH INTERNET, so the same configuration simply fetches what it
--  needs, whenever it needs it. Every option below that differs says so.
-- ===========================================================================

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

-- ONLINE: podman_base wraps this clone in a custom "cannot be cloned offline,
-- rebuild the image on a machine with internet access" error, because on an
-- air-gapped target the failure is unrecoverable and needs explaining. On a
-- host, a failed clone means the network is broken, and lazy.nvim's own
-- message plus git's stderr say that better than anything we could add. So
-- this is the plain upstream bootstrap.
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "plugins" },
  },
  defaults = { lazy = false, version = false },
  install = {
    -- ONLINE: podman_base sets `missing = building`, i.e. install only while
    -- the image is being built and never afterwards. Here missing plugins are
    -- always installed - that is the whole point of a host install: whatever
    -- the spec asks for has to end up on disk, on the first start and after
    -- every later edit of lua/plugins/.
    missing = true,
    colorscheme = { "catppuccin", "tokyonight", "habamax" },
  },
  -- ONLINE: podman_base disables the update checker because there is nothing
  -- to check against. Here it runs, but silently: updates show up in :Lazy
  -- when you open it instead of interrupting you with a notification.
  checker = { enabled = true, notify = false },
  -- Unchanged from podman_base: reloading the spec on every write to a config
  -- file is noise, not a feature. `:Lazy sync` after an edit is explicit.
  change_detection = { enabled = false, notify = false },
  -- ONLINE: podman_base pins `rocks = { enabled = false, hererocks = false }`
  -- and `pkg.sources = { "lazy" }` because luarocks and rockspec resolution
  -- both need the network. On a host these are lazy.nvim's own defaults,
  -- written out explicitly so the departure is visible: a plugin you add later
  -- that declares rockspec or packspec dependencies resolves normally.
  -- hererocks stays false, so a system luarocks is used when one is installed
  -- rather than lazy.nvim building its own Lua toolchain behind your back.
  rocks = { hererocks = false },
  pkg = { enabled = true, sources = { "lazy", "rockspec", "packspec" } },
  ui = { border = "rounded" },
  performance = {
    rtp = {
      -- Built-in plugins we never use; not loading them keeps startup short.
      disabled_plugins = {
        "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin", "netrwPlugin",
      },
    },
  },
})
