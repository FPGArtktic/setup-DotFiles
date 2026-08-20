-- ===========================================================================
--  setup-DotFiles :: LazyVim "extras" selection
--
--  Same list as podman_base's lua/plugins/wrk-extras.lua, and the same
--  defensive probe. The probe is not an offline trick, so it is kept:
--  importing a module that does not exist in the installed LazyVim version is
--  a hard startup error, and LazyVim is not on disk at all on the very first
--  run. A LazyVim release that renames or drops an extra would break startup
--  on the next update just as surely online as offline, so we import only what
--  is actually there. The probe itself gained one fix - see the comment in the
--  loop at the bottom.
--
--  Consequence, on a host exactly as in the image: the first `nvim` run
--  installs LazyVim itself, and a SECOND run (or `:Lazy sync`) picks up these
--  extras, because they can only be probed once LazyVim exists on disk.
--  podman_base solves this by running `Lazy! sync` several times during the
--  build; on a host the installer runs the same headless sync twice after
--  copying this tree, so by the time you open the editor everything is there.
-- ===========================================================================

local wanted = {
  -- languages -------------------------------------------------------------
  "lang.json",
  "lang.yaml",
  "lang.toml",
  "lang.markdown",
  "lang.python",
  "lang.typescript",
  "lang.go",
  "lang.clangd",
  "lang.docker",
  "lang.git",
  "lang.sql",
  -- editing / UI ----------------------------------------------------------
  "coding.mini-surround",
  "editor.telescope",
  "editor.inc-rename",
  "util.mini-hipatterns",
  "formatting.prettier",
  -- debugging -------------------------------------------------------------
  "dap.core",
}

local root = vim.fn.stdpath("data") .. "/lazy/LazyVim/lua/lazyvim/plugins/extras/"
local uv = vim.uv or vim.loop
local spec = {}

for _, mod in ipairs(wanted) do
  local base = root .. mod:gsub("%.", "/")
  -- DEPARTURE FROM podman_base: it only probes "<mod>.lua". Some extras are
  -- directory modules instead - LazyVim 16 turned lang.typescript into
  -- extras/lang/typescript/init.lua - and `require` resolves both forms, so
  -- checking only the flat file silently drops the extra. Probing for
  -- "<mod>/init.lua" as well keeps this list meaning what it says. Verified
  -- against LazyVim 16.0.0, where lang.typescript is exactly that case.
  if uv.fs_stat(base .. ".lua") or uv.fs_stat(base .. "/init.lua") then
    spec[#spec + 1] = { import = "lazyvim.plugins.extras." .. mod }
  end
end

return spec
