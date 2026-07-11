local M = {}

M.defaults = {
  path = "relative",
  separator = " › ",
  padding = { left = 1, right = 1 },
  update_debounce = 24,
  symbol_debounce = 120,
  max_depth = 8,
  sources = function(buf)
    if vim.bo[buf].filetype == "markdown" then
      return { "markdown", "lsp", "treesitter" }
    end
    return { "lsp", "treesitter" }
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
