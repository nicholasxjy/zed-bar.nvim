local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)

local treesitter = require("zed-bar.sources.treesitter")
local zed_bar = require("zed-bar")
local symbol_utils = require("zed-bar.symbols")

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, root .. "/tests/benchmark-fixture.lua")
vim.bo[buf].filetype = "lua"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "local function render(context)",
  "  local current_symbols = sources.get_symbols(context, {",
  "    buf = context.buf,",
  "    win = context.win,",
  "  })",
  "  if current_symbols then",
  "    return current_symbols",
  "  end",
  "end",
})
vim.api.nvim_win_set_buf(0, buf)

local parser = vim.treesitter.get_parser(buf, "lua")
parser:parse()
local cursors = { { 2, 8 }, { 3, 10 }, { 4, 10 }, { 6, 6 }, { 7, 8 } }

local lsp_symbols = {}
for index = 1, 2000 do
  local line = (index - 1) * 3
  lsp_symbols[index] = {
    children = {},
    kind = 12,
    name = "symbol_" .. index,
    range = {
      start = { line = line, character = 0 },
      ["end"] = { line = line + 1, character = 0 },
    },
  }
end

for index = 1, 200 do
  local cursor = cursors[index % #cursors + 1]
  treesitter.get_symbols(buf, 0, cursor, 8)
end

collectgarbage("collect")
local memory_before = collectgarbage("count")
local source_started = vim.uv.hrtime()
for index = 1, 5000 do
  local cursor = cursors[index % #cursors + 1]
  treesitter.get_symbols(buf, 0, cursor, 8)
end
local source_ms = (vim.uv.hrtime() - source_started) / 1e6

local lsp_started = vim.uv.hrtime()
for index = 1, 5000 do
  local symbol_index = index * 7919 % #lsp_symbols + 1
  symbol_utils.path(lsp_symbols, { line = (symbol_index - 1) * 3, character = 0 }, 8)
end
local lsp_ms = (vim.uv.hrtime() - lsp_started) / 1e6

zed_bar.setup({ update_debounce = 0, symbol_debounce = 0 })
local render_started = vim.uv.hrtime()
for index = 1, 3000 do
  local cursor = cursors[index % #cursors + 1]
  vim.api.nvim_win_set_cursor(0, cursor)
  zed_bar._render(0)
end
local render_ms = (vim.uv.hrtime() - render_started) / 1e6
collectgarbage("collect")

print(vim.json.encode({
  lsp_ms = lsp_ms,
  render_ms = render_ms,
  retained_kb = collectgarbage("count") - memory_before,
  source_ms = source_ms,
}))
