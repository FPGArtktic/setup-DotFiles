-- ===========================================================================
--  setup-DotFiles :: make sure everything is actually installed
--
--  This is podman_base's lua/plugins/wrk-offline.lua turned inside out.
--
--  There, mason's and nvim-treesitter's `ensure_installed` lists were honoured
--  while the image was being built (WRK_BUILD=1) and then CLEARED at runtime,
--  because on an air-gapped machine every remaining entry turns into a failed
--  download and a wall of error notifications on startup.
--
--  Here we are on a host with internet, so the lists stay ACTIVE - that is the
--  whole point: every language server, formatter, linter and parser the
--  container ships with has to be present on the machine too. Nothing is
--  cleared, nothing is conditional, there is no build flag.
--
--  The lists themselves are NOT new. They are the same sets podman_base bakes
--  into the image:
--    * the Mason list  = the Containerfile's `ARG WRK_NVIM_LSP`, installed
--      there by usr/local/share/podman-wrk/nvim-bootstrap.lua;
--    * the parser list = DEFAULT_TS_LANGS in that same nvim-bootstrap.lua,
--      which is also the list wrk-offline.lua installs during a build.
--  Keep the two in step if you ever change one.
-- ===========================================================================

-- Append without introducing duplicates: LazyVim and its language extras fill
-- these lists too, and we only want to add what is missing.
local function extend(list, items)
  local seen = {}
  for _, v in ipairs(list) do
    seen[v] = true
  end
  for _, v in ipairs(items) do
    if not seen[v] then
      seen[v] = true
      list[#list + 1] = v
    end
  end
  return list
end

--  Language servers, formatters and linters installed through Mason.
--  Mason package names, not lspconfig names.
--  Same set as `ARG WRK_NVIM_LSP` in podman_base's Containerfile.
local MASON_PACKAGES = {
  "lua-language-server",
  "bash-language-server",
  "basedpyright",
  "json-lsp",
  "yaml-language-server",
  "typescript-language-server",
  "clangd",
  "stylua",
  "shfmt",
  "ruff",
}

--  Tree-sitter parsers. Same list as DEFAULT_TS_LANGS in nvim-bootstrap.lua.
--  Only names the installed nvim-treesitter actually knows: "jsonc" for
--  instance is rejected by the main branch and just prints a warning.
local TS_LANGUAGES = {
  "bash", "c", "cpp", "css", "diff", "dockerfile", "git_config",
  "gitcommit", "gitignore", "go", "html", "javascript", "json",
  "lua", "luadoc", "make", "markdown", "markdown_inline", "printf",
  "python", "query", "regex", "rust", "sql", "toml", "tsx",
  "typescript", "vim", "vimdoc", "xml", "yaml",
}

--  Note: shellcheck, ripgrep, fd, lazygit and the language runtimes are NOT
--  in the Mason list. They are system packages here (yay-apps.txt), exactly as
--  they are pacman packages in the image - installing a second copy through
--  Mason would only put a stale binary in front of the packaged one.

return {
  --  Only the current mason.nvim name (mason-org/*) is used. lazy.nvim
  --  normalises the old williamboman/* name onto it, and naming the old one
  --  explicitly makes it print a "was renamed to" notice on every startup.
  --
  --  podman_base splits this into two specs - one to clear the list, one to
  --  set PATH. With nothing left to clear, both halves fit in one spec.
  {
    "mason-org/mason.nvim",
    optional = true,
    opts = function(_, opts)
      -- Mason binaries must be on PATH for the servers to be found.
      opts.PATH = "prepend"
      opts.ensure_installed = extend(opts.ensure_installed or {}, MASON_PACKAGES)
      return opts
    end,
  },

  --  mason-lspconfig.nvim, mason-tool-installer.nvim and mason-nvim-dap.nvim
  --  are deliberately absent from this file. podman_base has to name them
  --  because it needs to switch their automatic installation OFF; online they
  --  are left exactly as LazyVim configures them, which is ON.

  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = extend(opts.ensure_installed or {}, TS_LANGUAGES)
      -- ONLINE: podman_base sets `auto_install = false` at runtime, because a
      -- parser that is not in the image can never be fetched. Here a file type
      -- outside the list above compiles its parser on the spot.
      opts.auto_install = true
      return opts
    end,
  },
}
