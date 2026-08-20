-- ===========================================================================
--  setup-DotFiles :: install-time Neovim bootstrap
--
--  NOT loaded by Neovim on startup - nothing outside init.lua and lua/ ever
--  is. This file exists to be run once by the installer:
--
--    nvim --headless -c "luafile $HOME/.config/nvim/bootstrap.lua"
--
--  It is the host counterpart of podman_base's
--  usr/local/share/podman-wrk/nvim-bootstrap.lua and it is here for exactly
--  the same reason: `nvim --headless "+Lazy! sync" +qa` fires the Mason and
--  tree-sitter installs and then quits, and Mason kills them on the way out
--  ("Neovim is exiting while packages are still installing"). The install
--  looks successful and leaves you with no language servers. This script
--  issues the same installs and then BLOCKS until they have finished, so a
--  completed run means the tools are really on disk.
--
--  Note the invocation: `nvim -l script.lua` does NOT source init.lua, so
--  lazy.nvim never runs and neither :Lazy nor Mason exist. `-c luafile` runs
--  after a normal startup, which is what we need. The script quits by itself,
--  so do not append a `-c qa` - that is precisely the race described above.
--
--  DIFFERENCE FROM podman_base: that script exits non-zero when nothing could
--  be installed, because an air-gapped image with no language servers cannot
--  be repaired on the target and the build must fail loudly. Here it always
--  exits 0 and only prints a warning: this is a host with internet, anything
--  that failed can be installed later with `:Mason` or `:Lazy sync`, and
--  aborting a dotfiles installation over a slow mirror would be wrong.
--
--  It also carries no package lists of its own. podman_base has to pass them
--  in through WRK_NVIM_LSP / WRK_NVIM_TS because its runtime config CLEARS
--  every ensure_installed list; ours keeps them active (see
--  lua/plugins/dotfiles-ensure.lua), so this script reads what the resolved
--  plugin spec asks for. One list, no chance of the two drifting apart.
-- ===========================================================================

local TIMEOUT_MS = tonumber(vim.env.DOTFILES_BOOTSTRAP_TIMEOUT or "") or (30 * 60 * 1000)

-- How long to keep waiting when nothing observable is happening any more but
-- something is still missing. Anything left after that has failed to install.
local IDLE_GIVE_UP_SECONDS = 60

local function out(fmt, ...)
  io.stdout:write(string.format(fmt, ...) .. "\n")
  io.stdout:flush()
end

-- ---------------------------------------------------------------------------
--  Force the lazy-loaded plugins to load now: their user commands, Lua modules
--  and - the point of the exercise - their ensure_installed handlers do not
--  exist until they do.
-- ---------------------------------------------------------------------------
local function load(plugin)
  pcall(vim.cmd, "Lazy! load " .. plugin)
end

load("mason.nvim")
load("mason-lspconfig.nvim")
load("nvim-treesitter")

-- ---------------------------------------------------------------------------
--  What the resolved spec asks for. `lazy.core.plugin.values` is how LazyVim
--  itself reads a plugin's merged opts, so this returns LazyVim's own entries
--  plus everything lua/plugins/dotfiles-ensure.lua adds.
-- ---------------------------------------------------------------------------
local function spec_list(plugin_name, key)
  local ok, Config = pcall(require, "lazy.core.config")
  if not ok then return {} end
  local plugin = Config.plugins[plugin_name]
  if not plugin then return {} end
  local got, opts = pcall(function()
    return require("lazy.core.plugin").values(plugin, "opts", false)
  end)
  if got and type(opts) == "table" and type(opts[key]) == "table" then
    -- The merged list can contain duplicates; the callers do not care, but a
    -- deduplicated list keeps the progress counters honest.
    local seen, list = {}, {}
    for _, v in ipairs(opts[key]) do
      if type(v) == "string" and not seen[v] then
        seen[v] = true
        list[#list + 1] = v
      end
    end
    return list
  end
  return {}
end

-- ---------------------------------------------------------------------------
--  Mason
--
--  Waiting is done on the install HANDLES, exactly as podman_base's bootstrap
--  does: `handle:once("closed", ...)` fires whether the install succeeded or
--  failed. Polling mason-registry.get_installing_packages() instead looks
--  tidier but is not dependable across mason versions - where it is missing,
--  every poll reports "nothing is installing" and the script walks out on
--  downloads that are very much still running. Learned the hard way.
--
--  LazyVim starts these installs itself the moment mason.nvim loads, so a
--  package may already be on its way; that one is polled rather than started
--  a second time.
-- ---------------------------------------------------------------------------
local function mason_registry()
  local ok, registry = pcall(require, "mason-registry")
  if not ok then return nil end
  return registry
end

local function mason_package(registry, name)
  local ok, pkg = pcall(registry.get_package, name)
  if ok then return pkg end
  return nil
end

-- Starts `pkg` if it is idle and returns a table with either an install handle
-- to wait on, or nothing, meaning "poll is_installed() instead".
local function start_install(pkg)
  local busy = false
  local ok, res = pcall(function() return pkg:is_installing() end)
  if ok then busy = res and true or false end
  if busy then return nil end
  local started, handle = pcall(function() return pkg:install() end)
  if started and type(handle) == "table" and type(handle.once) == "function" then
    return handle
  end
  return nil
end

local function install_mason()
  local registry = mason_registry()
  if not registry then
    out("mason: registry unavailable - skipping")
    return 0
  end

  pcall(function() registry.refresh() end)

  local wanted = spec_list("mason.nvim", "ensure_installed")
  out("mason: %d package(s) wanted", #wanted)

  local pending = 0     -- installs we started and hold a handle for
  local polled = {}     -- installs someone else started, watched by polling
  local unknown = {}

  for _, name in ipairs(wanted) do
    local pkg = mason_package(registry, name)
    if not pkg then
      out("mason: unknown package %q - skipping", name)
      unknown[#unknown + 1] = name
    elseif not pkg:is_installed() then
      local handle = start_install(pkg)
      if handle then
        pending = pending + 1
        handle:once("closed", function() pending = pending - 1 end)
      else
        polled[#polled + 1] = name
      end
    end
  end

  local function polled_left()
    local n = 0
    for _, name in ipairs(polled) do
      local pkg = mason_package(registry, name)
      if pkg and not pkg:is_installed() then n = n + 1 end
    end
    return n
  end

  -- Of the packages we only poll, how many is mason working on right now. This
  -- is what keeps the wait alive: LazyVim usually queues everything before
  -- this script runs, so `pending` is 0 and a plain "nothing changed for a
  -- while" rule would abandon downloads that are perfectly healthy, just slow.
  local function polled_busy()
    local n = 0
    for _, name in ipairs(polled) do
      local pkg = mason_package(registry, name)
      if pkg then
        local ok, busy = pcall(function() return pkg:is_installing() end)
        if ok and busy then n = n + 1 end
      end
    end
    return n
  end

  local idle, last_left, last_line = 0, nil, nil
  vim.wait(TIMEOUT_MS, function()
    local left = polled_left()
    local busy = polled_busy()

    local line = pending .. "/" .. busy .. "/" .. left
    if line ~= last_line then
      last_line = line
      if pending > 0 or left > 0 then
        out("mason: %d started here, %d installing, %d still missing ...", pending, busy, left)
      end
    end

    if pending <= 0 and left == 0 then return true end

    -- Something finished since the last poll: that is progress, keep waiting.
    if last_left == nil or left < last_left then
      last_left = left
      idle = 0
      return false
    end

    if pending <= 0 and busy == 0 then
      idle = idle + 1
      -- Nothing of ours is running and nothing new is appearing: whatever is
      -- left is not going to install itself.
      if idle >= IDLE_GIVE_UP_SECONDS then return true end
    else
      idle = 0
    end
    return false
  end, 1000)

  local failed = {}
  for _, name in ipairs(wanted) do
    local pkg = mason_package(registry, name)
    if pkg and not pkg:is_installed() then failed[#failed + 1] = name end
  end

  local installed = {}
  pcall(function() installed = registry.get_installed_package_names() or {} end)
  table.sort(installed)
  out("mason: %d package(s) installed: %s", #installed, table.concat(installed, " "))
  if #failed > 0 then
    out("mason: %d not installed: %s", #failed, table.concat(failed, " "))
    out("mason: retry them from inside Neovim with :Mason")
  end
  return #installed
end

-- ---------------------------------------------------------------------------
--  Tree-sitter
--
--  Two incompatible generations are in the wild and LazyVim has moved between
--  them, so handle both:
--    * main branch   - require("nvim-treesitter").install(langs) returns an
--                      awaitable object with :wait(timeout)
--    * master branch - the :TSUpdateSync / :TSInstallSync commands
--  Either way we block until the parsers are actually on disk.
-- ---------------------------------------------------------------------------
local function parser_count()
  local seen = {}
  for _, dir in ipairs(vim.api.nvim_get_runtime_file("parser", true)) do
    local ok, iter = pcall(vim.fs.dir, dir)
    if ok then
      for name in iter do
        seen[name] = true
      end
    end
  end
  return vim.tbl_count(seen)
end

-- The main branch compiles every parser with the tree-sitter CLI. It is a
-- system package on this host (tree-sitter-cli in yay-apps.txt), exactly as it
-- is a pacman package in podman_base's image - but if the machine has not got
-- it, every single parser fails with ENOENT, so install it through Mason and
-- wait for it BEFORE touching the parsers. Doing it here rather than adding it
-- to dotfiles-ensure.lua keeps that file's package list equal to podman_base's.
local function ensure_tree_sitter_cli()
  if vim.fn.executable("tree-sitter") == 1 then return true end

  out("treesitter: the tree-sitter CLI is missing - installing it with Mason ...")
  local registry = mason_registry()
  local pkg = registry and mason_package(registry, "tree-sitter-cli")
  if pkg then
    if not pkg:is_installed() then
      local handle = start_install(pkg)
      if handle then
        local done = false
        handle:once("closed", function() done = true end)
        vim.wait(TIMEOUT_MS, function() return done end, 500)
      else
        vim.wait(TIMEOUT_MS, function() return pkg:is_installed() end, 1000)
      end
    end
    -- mason.nvim is set to prepend its bin directory to PATH, so a binary it
    -- has just written is picked up without restarting Neovim.
    vim.wait(5000, function() return vim.fn.executable("tree-sitter") == 1 end, 250)
  end

  if vim.fn.executable("tree-sitter") == 1 then return true end
  out("treesitter: WARNING - no tree-sitter CLI. Install the tree-sitter-cli")
  out("treesitter:           package, then run :TSUpdate inside Neovim.")
  return false
end

local function install_treesitter()
  -- The language list is the one the spec resolved, i.e. LazyVim's own entries
  -- plus TS_LANGUAGES from lua/plugins/dotfiles-ensure.lua.
  local langs = spec_list("nvim-treesitter", "ensure_installed")
  if #langs == 0 then
    out("treesitter: no language list resolved - relying on the plugin's own setup")
  end

  local ok, nts = pcall(require, "nvim-treesitter")

  if ok and type(nts.install) == "function" and #langs > 0 then
    if not ensure_tree_sitter_cli() then
      -- Without the CLI every language would fail identically; one clear
      -- message beats forty stack traces.
      out("treesitter: skipping parser installation")
      return parser_count()
    end
    out("treesitter: installing %d language(s) via the main-branch API ...", #langs)
    local started, handle = pcall(nts.install, langs)
    if started and type(handle) == "table" and type(handle.wait) == "function" then
      -- pwait is the non-throwing variant where available.
      local waiter = type(handle.pwait) == "function" and handle.pwait or handle.wait
      pcall(waiter, handle, TIMEOUT_MS)
    else
      -- Could not await it explicitly; fall back to polling the parser dir.
      local target = parser_count()
      vim.wait(TIMEOUT_MS, function()
        local now = parser_count()
        if now > target then target = now end
        return false
      end, 1000)
    end
  elseif vim.fn.exists(":TSUpdateSync") == 2 then
    -- The master branch compiles with a plain C compiler, no CLI needed.
    out("treesitter: running TSUpdateSync ...")
    pcall(vim.cmd, "TSUpdateSync")
  elseif vim.fn.exists(":TSInstallSync") == 2 then
    out("treesitter: running TSInstallSync ...")
    pcall(vim.cmd, "TSInstallSync " .. table.concat(langs, " "))
  else
    out("treesitter: no way to install parsers found")
  end

  local n = parser_count()
  if ok and type(nts.get_installed) == "function" then
    local got, list = pcall(nts.get_installed)
    if got and type(list) == "table" then
      out("treesitter: %d language(s) registered as installed", #list)
    end
  end
  out("treesitter: %d parser file(s) on disk", n)
  return n
end

-- ---------------------------------------------------------------------------
local mason_count = install_mason()
local parsers = install_treesitter()

out("bootstrap: mason=%d parsers=%d", mason_count, parsers)

if mason_count == 0 and parsers == 0 then
  -- A warning, not a failure: see the header. Repairable from inside Neovim.
  out("bootstrap: WARNING - nothing was installed. Check your network, then run")
  out("bootstrap:           :Lazy sync  and  :Mason  inside Neovim.")
end

vim.cmd("qa!")
