-- ===========================================================================
--  setup-DotFiles :: curated additions on top of LazyVim
--
--  Ported one to one from podman_base's lua/plugins/wrk-plugins.lua. The
--  plugin set, the keys, the options and the LSP/formatter/linter selection
--  are the same; only the comments that talked about the image were rewritten
--  for a host, and the file was renamed wrk-* -> dotfiles-*.
-- ===========================================================================

return {
  -- --- colours -------------------------------------------------------------
  { "catppuccin/nvim", name = "catppuccin", priority = 1000, opts = { flavour = "mocha" } },
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },

  -- --- git -----------------------------------------------------------------
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
    keys = {
      { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview: working tree" },
      { "<leader>gV", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history" },
    },
    opts = {},
  },

  -- lazygit is a real binary from the package list (yay-apps.txt), not a
  -- plugin, so wire it to the terminal helper.
  {
    "folke/snacks.nvim",
    optional = true,
    keys = {
      {
        "<leader>gg",
        function() Snacks.lazygit({ cwd = LazyVim.root.git() }) end,
        desc = "Lazygit (repo root)",
      },
      { "<leader>gG", function() Snacks.lazygit() end, desc = "Lazygit (cwd)" },
    },
  },

  -- --- navigation ----------------------------------------------------------
  {
    "stevearc/oil.nvim",
    cmd = "Oil",
    keys = { { "-", "<cmd>Oil<cr>", desc = "Open parent directory (oil)" } },
    opts = { view_options = { show_hidden = true } },
  },

  -- --- diagnostics / todo --------------------------------------------------
  { "folke/trouble.nvim", optional = true },
  { "folke/todo-comments.nvim", optional = true },

  -- --- LSP: servers configured here, installed by Mason --------------------
  --  podman_base bakes these in at build time; here Mason installs them on the
  --  first start (see dotfiles-ensure.lua). The server list is the same.
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        virtual_text = { spacing = 4, prefix = "\u{25cf}" },
        severity_sort = true,
      },
      servers = {
        bashls = {},
        lua_ls = {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
              hint = { enable = true },
            },
          },
        },
      },
    },
  },

  -- --- formatting ----------------------------------------------------------
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        sh = { "shfmt" },
        bash = { "shfmt" },
        zsh = { "shfmt" },
        lua = { "stylua" },
      },
    },
  },

  -- --- linting -------------------------------------------------------------
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      -- shellcheck is a system package on this host (yay-apps.txt), exactly as
      -- it is a pacman package in the image; do not reference linters that are
      -- not installed - nvim-lint errors out on those.
      linters_by_ft = {
        sh = { "shellcheck" },
        bash = { "shellcheck" },
      },
    },
  },
}
