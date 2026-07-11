local M = {}

local code_sources = { "lsp", "treesitter" }
local markdown_sources = { "markdown", "lsp", "treesitter" }

M.defaults = {
  path = "relative",
  separator = " › ",
  padding = { left = 1, right = 1 },
  update_debounce = 24,
  symbol_debounce = 120,
  max_depth = 8,
  sources = function(buf)
    if vim.bo[buf].filetype == "markdown" then
      return markdown_sources
    end
    return code_sources
  end,
  enabled = function(buf, win)
    return vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_win_is_valid(win)
      and vim.bo[buf].buftype == ""
      and vim.api.nvim_buf_get_name(buf) ~= ""
  end,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
