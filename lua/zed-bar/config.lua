local M = {}
local kinds = require("zed-bar.kinds")

local code_sources = { "lsp", "treesitter" }
local markdown_sources = { "markdown", "lsp", "treesitter" }

M.defaults = {
  path = "relative",
  separator = " › ",
  padding = { left = 1, right = 1 },
  update_debounce = 24,
  symbol_debounce = 120,
  max_depth = 8,
  -- "scope" shows only the symbols that enclose the cursor (modules, classes, functions,
  -- headings, data keys); "full" also shows bindings, calls, and control flow.
  detail = "scope",
  -- Symbol kind icons, plus a file icon when mini.icons or nvim-web-devicons is available.
  icons = true,
  kinds = kinds.icons,
  -- Flags after the file name; set an entry to false to hide it.
  file_status = { modified = "●", readonly = "󰌾" },
  dim_inactive = true,
  disabled_filetypes = {},
  sources = function(buf)
    if vim.api.nvim_get_option_value("filetype", { buf = buf }) == "markdown" then
      return markdown_sources
    end
    return code_sources
  end,
  enabled = function(buf, win)
    return vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_get_option_value("buftype", { buf = buf }) == ""
      and vim.api.nvim_buf_get_name(buf) ~= ""
  end,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
