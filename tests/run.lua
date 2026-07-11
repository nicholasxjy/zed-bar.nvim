local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)

local function eq(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(
      (message or "values differ")
        .. "\nexpected: "
        .. vim.inspect(expected)
        .. "\nactual: "
        .. vim.inspect(actual)
    )
  end
end

local symbols = require("zed-bar.symbols")

local document_symbols = symbols.normalize({
  {
    name = "CNUserModal",
    kind = 5,
    range = { start = { line = 0, character = 0 }, ["end"] = { line = 20, character = 0 } },
    children = {
      {
        name = "setOpen",
        kind = 12,
        range = { start = { line = 5, character = 2 }, ["end"] = { line = 8, character = 3 } },
      },
    },
  },
})

local path = symbols.path(document_symbols, { line = 6, character = 1 })
eq(
  vim.tbl_map(function(symbol)
    return symbol.name
  end, path),
  { "CNUserModal", "setOpen" },
  "nested DocumentSymbol path"
)

local disordered = symbols.normalize({
  {
    name = "later",
    kind = 12,
    range = { start = { line = 30, character = 0 }, ["end"] = { line = 31, character = 0 } },
  },
  {
    name = "earlier",
    kind = 12,
    range = { start = { line = 20, character = 0 }, ["end"] = { line = 21, character = 0 } },
  },
})
eq(disordered[1].name, "earlier", "disordered LSP symbols are sorted")

local flat_symbols = symbols.normalize({
  {
    name = "outer",
    kind = 12,
    location = {
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 10, character = 0 } },
    },
  },
  {
    name = "inner",
    kind = 13,
    location = {
      range = { start = { line = 3, character = 0 }, ["end"] = { line = 4, character = 0 } },
    },
  },
  {
    name = "sibling",
    kind = 12,
    location = {
      range = { start = { line = 12, character = 0 }, ["end"] = { line = 15, character = 0 } },
    },
  },
})
eq(
  symbols.path(flat_symbols, { line = 3, character = 2 })[2].name,
  "inner",
  "flat SymbolInformation tree"
)
eq(#symbols.path(flat_symbols, { line = 11, character = 0 }), 0, "cursor outside symbols")

local zed_bar = require("zed-bar")
zed_bar.setup({ path = "relative", update_debounce = 0, symbol_debounce = 0 })
vim.api.nvim_buf_set_name(0, root .. "/src/components/CNUserModal/index.tsx")
zed_bar._render(0)
local winbar = vim.wo.winbar
assert(
  winbar:find("src/components/CNUserModal/index.tsx", 1, true),
  "relative buffer path is rendered"
)
assert(winbar:find("ZedBarFile", 1, true), "file path uses its own highlight")

vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({ "" }, 10))
vim.api.nvim_win_set_cursor(0, { 7, 0 })

local original_get_clients = vim.lsp.get_clients
local callbacks = {}
local cancelled = {}
local next_request_id = 0
local client = { offset_encoding = "utf-16" }
function client:request(_, _, callback)
  next_request_id = next_request_id + 1
  callbacks[next_request_id] = callback
  return true, next_request_id
end
function client:cancel_request(request_id)
  table.insert(cancelled, request_id)
end
vim.lsp.get_clients = function()
  return { client }
end

zed_bar.refresh()
zed_bar.refresh()
eq(cancelled, { 1 }, "an outdated LSP request is cancelled")
zed_bar._render(0)
assert(vim.wo.winbar:find("index.tsx", 1, true), "pending LSP requests keep the file component")

callbacks[1](nil, document_symbols)
callbacks[2](nil, document_symbols)
vim.wait(100, function()
  return vim.wo.winbar:find("setOpen", 1, true) ~= nil
end)
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
vim.wait(20)
eq(next_request_id, 2, "cursor movement does not request LSP symbols")

winbar = vim.wo.winbar
assert(winbar:find("CNUserModal", 1, true), "parent symbol is rendered")
assert(winbar:find("setOpen", 1, true), "cursor symbol is rendered")
assert(winbar:find("ZedBarIconKindFunction", 1, true), "symbol icon uses a kind highlight")
assert(winbar:find("ZedBarKindFunction", 1, true), "symbol name uses a kind highlight")

local evaluated = vim.api.nvim_eval_statusline(winbar, {
  winid = 0,
  highlights = true,
  use_winbar = true,
})
eq(
  evaluated.str,
  " src/components/CNUserModal/index.tsx ›  CNUserModal › 󰊕 setOpen ",
  "rendered layout matches the approved component order and spacing"
)

vim.lsp.get_clients = original_get_clients

print("zed-bar.nvim tests passed")
