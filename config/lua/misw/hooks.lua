-- nvim hooks: every *.lua in /workspace/.container/nvim/ (host:
-- ~/workspace/.container/nvim/; another dir: $KIDE_NVIM_HOOKS), sourced in
-- name order once the UI is up, after kide's own config. Like the shell hooks,
-- but the image ships none: every file there is yours (site config such as the
-- AI endpoint, see misw.ai). A failing hook is reported and skipped.
local M = {}

function M.run()
  local dir = vim.env.KIDE_NVIM_HOOKS or "/workspace/.container/nvim"
  local files = vim.fn.glob(dir .. "/*.lua", false, true)
  table.sort(files)
  for _, file in ipairs(files) do
    local ok, err = pcall(dofile, file)
    if not ok then
      vim.notify(("nvim hook %s: %s"):format(file, err), vim.log.levels.ERROR)
    end
  end
end

return M
