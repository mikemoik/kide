-- AI chat and edits (gp.nvim) against a chat-completions endpoint, no tool
-- calling needed. Set up only from an nvim hook (misw.hooks), e.g.
-- /workspace/.container/nvim/50-gp.lua:
--   require("misw.ai").setup({ providers = { … }, agents = { … } })
-- The table is gp.nvim's setup() config (see :h gp.nvim), merged over kide's
-- defaults: every built-in provider off, so nothing goes to api.openai.com &
-- co. unless the hook names it; no voice (whisper) or image generation; chats
-- in /workspace/.container/kide/gp/chats (survive the container). Without a
-- hook gp.nvim is loaded but inert: no commands, no keymaps, no requests.
local M = {}

-- chats next to the shell history; not writable (host install, read-only
-- workspace): gp's default under stdpath("data")
local function chat_dir()
  local dir = "/workspace/.container/kide/gp/chats"
  if pcall(vim.fn.mkdir, dir, "p") and vim.fn.filewritable(dir) == 2 then
    return dir
  end
end

local defaults = {
  -- a provider given as {} is disabled; the other built-ins are off upstream
  providers = { openai = {} },
  whisper = { disable = true },
  image = { disable = true },
}

local function keymaps()
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
  end
  map("n", "<leader>aa", "<cmd>GpChatToggle vsplit<cr>", "Toggle Chat")
  map("x", "<leader>aa", ":<C-u>'<,'>GpChatToggle vsplit<cr>", "Chat with Selection")
  map("n", "<leader>an", "<cmd>GpChatNew vsplit<cr>", "New Chat")
  map("x", "<leader>an", ":<C-u>'<,'>GpChatNew vsplit<cr>", "New Chat with Selection")
  map("x", "<leader>ap", ":<C-u>'<,'>GpChatPaste vsplit<cr>", "Paste Selection to Chat")
  map("n", "<leader>af", "<cmd>GpChatFinder<cr>", "Find Chat")
  map("n", "<leader>ar", "<cmd>GpRewrite<cr>", "Rewrite Line")
  map("x", "<leader>ar", ":<C-u>'<,'>GpRewrite<cr>", "Rewrite Selection")
  map("n", "<leader>ao", "<cmd>GpAppend<cr>", "Append after Line")
  map("x", "<leader>ao", ":<C-u>'<,'>GpAppend<cr>", "Append after Selection")
  map("n", "<leader>aO", "<cmd>GpPrepend<cr>", "Prepend before Line")
  map("x", "<leader>aO", ":<C-u>'<,'>GpPrepend<cr>", "Prepend before Selection")
  map("x", "<leader>ai", ":<C-u>'<,'>GpImplement<cr>", "Implement Selection (comments)")
  map("n", "<leader>a.", "<cmd>GpNextAgent<cr>", "Next Agent")
  map({ "n", "x" }, "<leader>as", "<cmd>GpStop<cr>", "Stop")
  pcall(function()
    require("which-key").add({ { "<leader>a", group = "ai", mode = { "n", "x" } } })
  end)
end

function M.setup(opts)
  opts = vim.deepcopy(opts or {})
  -- agents are a list: gp merges them by name, a deep merge would by index
  local agents = opts.agents
  opts.agents = nil
  local config = vim.tbl_deep_extend("force", defaults, { chat_dir = chat_dir() }, opts)
  config.agents = agents
  require("gp").setup(config)
  keymaps()
end

return M
