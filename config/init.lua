-- kide: misw's kreatos nvim config, built offline from source.
-- Plugins are vendored (see manifest/plugins.tsv) and installed by build-ide.sh as
-- opt packages under site/; parsers and queries live in site/ too. Nothing
-- here downloads: no vim.pack, no claudecode, no JSON schemas.

-- layout installed by build-ide.sh: <share>/config (this file) and <share>/site
local config = vim.fs.dirname(vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)))
vim.g.kide_site = vim.fs.joinpath(vim.fs.dirname(config), "site")
vim.opt.rtp:prepend(config)
vim.opt.rtp:prepend(vim.g.kide_site)
vim.opt.packpath:prepend(vim.g.kide_site)

require("misw.options")

for _, name in ipairs({
  -- look
  "ethereal.nvim",
  "mini.icons",
  "snacks.nvim",
  "bufferline.nvim",
  "lualine.nvim",
  "nui.nvim",
  "noice.nvim",
  -- editing
  "which-key.nvim",
  "flash.nvim",
  "mini.ai",
  "mini.pairs",
  "trouble.nvim",
  "todo-comments.nvim",
  "grug-far.nvim",
  "persistence.nvim",
  "plenary.nvim",
  "neo-tree.nvim",
  "yazi.nvim",
  -- code
  "nvim-treesitter",
  "nvim-treesitter-textobjects",
  "nvim-lspconfig",
  "lazydev.nvim",
  "blink.cmp",
  "friendly-snippets",
  "conform.nvim",
  "gitsigns.nvim",
  -- debug
  "nvim-dap",
  "nvim-nio",
  "nvim-dap-ui",
  "nvim-dap-python",
  "nvim-dap-virtual-text",
  -- c/c++
  "clangd_extensions.nvim",
  "cmake-tools.nvim",
  "neogen",
  "neotest",
  "neotest-gtest",
}) do
  vim.cmd.packadd(name)
end

local util = require("misw.util")

-- before the first redraw
require("misw.ui").setup()
require("misw.keymaps")
require("misw.autocmds")
require("misw.editor").setup()
require("misw.treesitter").setup()
require("misw.cpp").setup() -- before misw.lsp: it configures clangd
require("misw.lsp").setup()
require("misw.completion").setup()
require("misw.format").setup()
require("misw.git").setup()

-- after the UI is up
util.later(function()
  -- over SSH there is no clipboard tool: yanks stay inside kide, and the
  -- "+ / "* registers (Y, see keymaps.lua) go to the terminal by OSC 52
  -- (Windows Terminal, WezTerm; PuTTY ignores it). The terminal does not
  -- answer OSC 52 reads, so "+p pastes the last "+ yank (kept here); paste
  -- from the terminal with Ctrl+Shift+V.
  if vim.env.SSH_CONNECTION then
    local osc52 = require("vim.ui.clipboard.osc52")
    local last = { {}, "v" }
    local function copy(reg)
      local send = osc52.copy(reg)
      return function(lines, regtype)
        last = { lines, regtype }
        send(lines)
      end
    end
    local function paste()
      return last
    end
    vim.g.clipboard = {
      name = "OSC 52",
      copy = { ["+"] = copy("+"), ["*"] = copy("*") },
      paste = { ["+"] = paste, ["*"] = paste },
    }
  end
  vim.opt.clipboard = vim.env.SSH_CONNECTION and "" or "unnamedplus"
  require("misw.editor").later() -- trouble.setup() before lualine's trouble.statusline()
  require("misw.ui").later()
  require("misw.dap").setup()
end)
