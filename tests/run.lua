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
local sources = require("zed-bar.sources")

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

local markdown_buf = vim.api.nvim_create_buf(false, true)
vim.bo[markdown_buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(markdown_buf, 0, -1, false, {
  "# Project",
  "intro",
  "## API",
  "```lua",
  "### ignored",
  "```",
  "### Endpoint ###",
  "body",
})
local markdown_symbols = sources.markdown.get_symbols(markdown_buf, 0, { 8, 0 }, 8)
eq(
  vim.tbl_map(function(symbol)
    return symbol.name
  end, markdown_symbols),
  { "Project", "API", "Endpoint" },
  "Markdown headings ignore fenced code and form a hierarchy"
)

vim.api.nvim_buf_set_lines(markdown_buf, 6, 7, false, { "### Request" })
markdown_symbols = sources.markdown.get_symbols(markdown_buf, 0, { 8, 0 }, 8)
eq(markdown_symbols[3].name, "Request", "Markdown cache follows changedtick")

local long_markdown_buf = vim.api.nvim_create_buf(false, true)
vim.bo[long_markdown_buf].filetype = "markdown"
local long_markdown_lines = { "# Root" }
for _ = 2, 249 do
  table.insert(long_markdown_lines, "text")
end
table.insert(long_markdown_lines, "## Late section")
table.insert(long_markdown_lines, "body")
vim.api.nvim_buf_set_lines(long_markdown_buf, 0, -1, false, long_markdown_lines)
sources.markdown.get_symbols(long_markdown_buf, 0, { 1, 0 }, 8)
local extended_markdown = sources.markdown.get_symbols(long_markdown_buf, 0, { 251, 0 }, 8)
eq(extended_markdown[2].name, "Late section", "Markdown parsing extends with the cursor")

local fallback_symbols = sources.get_symbols({ "lsp", "markdown" }, {
  buf = markdown_buf,
  win = 0,
  cursor = { 8, 0 },
  max_depth = 8,
  lsp_symbols = {},
})
eq(fallback_symbols[3].name, "Request", "an empty LSP result falls back to Markdown")
local preferred_symbols = sources.get_symbols({ "lsp", "markdown" }, {
  buf = markdown_buf,
  win = 0,
  cursor = { 8, 0 },
  max_depth = 8,
  lsp_symbols = { { name = "from LSP", kind = 12 } },
})
eq(preferred_symbols[1].name, "from LSP", "the first non-empty source wins")

local treesitter = sources.treesitter
eq(treesitter._kind("function_declaration"), "Function", "Tree-sitter function kind")
eq(treesitter._kind("method_definition"), "Method", "Tree-sitter method kind")
eq(treesitter._kind("jsx_element"), "Element", "Tree-sitter element kind")
eq(treesitter._kind("if_statement"), "IfStatement", "Tree-sitter control-flow kind")
eq(treesitter._extract_name("return inner()"), "return inner", "stop before call arguments")
eq(treesitter._extract_name("if (ready) {"), "if", "stop before a condition")
eq(treesitter._extract_name("const value = call()"), "const value", "stop before assignment")
eq(treesitter._extract_name("foo.bar:baz()"), "foo.bar:baz", "keep qualified names")

local treesitter_buf = vim.api.nvim_create_buf(true, false)
vim.bo[treesitter_buf].filetype = "typescript"
vim.api.nvim_buf_set_lines(treesitter_buf, 0, -1, false, {
  "function outer() {",
  "  const inner = () => 1",
  "  return inner()",
  "}",
})
local has_parser, parser = pcall(vim.treesitter.get_parser, treesitter_buf, "typescript")
if has_parser then
  parser:parse()
  local treesitter_symbols = treesitter.get_symbols(treesitter_buf, 0, { 3, 10 }, 8)
  assert(treesitter_symbols[1], "Tree-sitter returns symbols for the current line")
  assert(
    vim.iter(treesitter_symbols):any(function(symbol)
      return symbol.kind == "Function" or symbol.kind == "Call"
    end),
    "Tree-sitter includes the enclosing function or current call"
  )
  for _, symbol in ipairs(treesitter_symbols) do
    assert(not symbol.name:find("[(){}=]"), "Tree-sitter symbols use short names: " .. symbol.name)
  end
end

local lua_buf = vim.api.nvim_create_buf(true, false)
vim.bo[lua_buf].filetype = "lua"
vim.api.nvim_buf_set_lines(lua_buf, 0, -1, false, { "vim.g.loaded_zed_bar = true" })
local has_lua_parser, lua_parser = pcall(vim.treesitter.get_parser, lua_buf, "lua")
if has_lua_parser then
  lua_parser:parse()
  local lua_symbols = treesitter.get_symbols(lua_buf, 0, { 1, 0 }, 8)
  eq(
    vim.tbl_map(function(symbol)
      return symbol.name
    end, lua_symbols),
    { "vim.g.loaded_zed_bar", "vim" },
    "same-name parent nodes are removed while the later child is kept"
  )
  eq(lua_symbols[1].kind, "Variable", "the more specific child symbol is kept")
end

local zed_bar = require("zed-bar")
zed_bar.setup({ path = "relative", update_debounce = 0, symbol_debounce = 0 })
vim.api.nvim_buf_set_name(0, root .. "/src/components/CNUserModal/index.tsx")
zed_bar._render(0)
eq(zed_bar._render(0), false, "unchanged winbar content does not trigger another assignment")
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

if has_parser then
  vim.api.nvim_buf_set_name(treesitter_buf, root .. "/src/fallback.ts")
  vim.api.nvim_win_set_buf(0, treesitter_buf)
  vim.api.nvim_win_set_cursor(0, { 3, 10 })
  zed_bar._render(0)
  assert(
    vim.wo.winbar:find("outer", 1, true),
    "winbar renders the Tree-sitter fallback: " .. vim.wo.winbar
  )
end

local first_enter_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(first_enter_buf, root .. "/src/first-enter.lua")
vim.api.nvim_win_set_buf(0, first_enter_buf)
vim.wo.winbar = ""
vim.api.nvim_exec_autocmds("BufReadPre", { buffer = first_enter_buf })
assert(vim.wo.winbar:find("src/first-enter.lua", 1, true), "BufReadPre reserves the winbar row")

print("zed-bar.nvim tests passed")
