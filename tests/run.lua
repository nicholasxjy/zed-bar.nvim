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

local overlapping_symbols = symbols.normalize({
  {
    name = "outer",
    kind = 12,
    range = { start = { line = 0, character = 0 }, ["end"] = { line = 100, character = 0 } },
  },
  {
    name = "earlier inner",
    kind = 12,
    range = { start = { line = 10, character = 0 }, ["end"] = { line = 20, character = 0 } },
  },
})
eq(
  symbols.path(overlapping_symbols, { line = 50, character = 0 })[1].name,
  "outer",
  "binary lookup still finds an earlier overlapping range"
)

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
eq(treesitter._canonical_name("local current_symbols"), "current_symbols", "ignore local")
eq(treesitter._canonical_name("public static value"), "value", "ignore declaration modifiers")
eq(treesitter._canonical_name("return value"), "return value", "keep control-flow keywords")

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

if has_parser then
  local class_buf = vim.api.nvim_create_buf(true, false)
  vim.bo[class_buf].filetype = "typescript"
  vim.api.nvim_buf_set_lines(class_buf, 0, -1, false, {
    "class Foo {",
    "  bar = 1",
    "",
    "  baz() {}",
    "}",
    "const App = () => {",
    "  const first = 1",
    "",
    "}",
  })
  local function names_at(row, column)
    return vim.tbl_map(function(symbol)
      return symbol.name
    end, treesitter.get_symbols(class_buf, 0, { row, column }, 8))
  end
  eq(names_at(3, 0), { "Foo" }, "anonymous class bodies are not named after their first member")
  eq(names_at(8, 0), { "App" }, "anonymous arrow functions are not named after their body")

  vim.api.nvim_buf_set_lines(class_buf, 0, 1, false, { "class Renamed {" })
  eq(names_at(3, 0), { "Renamed" }, "a stale Tree-sitter tree is re-parsed after an edit")
  vim.api.nvim_buf_set_lines(class_buf, 1, -1, false, {})
  eq(names_at(1, 0), { "Renamed" }, "lookups stay safe after lines covered by old nodes are deleted")
end

local fence_buf = vim.api.nvim_create_buf(false, true)
vim.bo[fence_buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(fence_buf, 0, -1, false, {
  "# Top",
  "````",
  "```lua",
  "# not a heading",
  "```",
  "````",
  "## Real",
  "body",
})
eq(
  vim.tbl_map(function(symbol)
    return symbol.name
  end, sources.markdown.get_symbols(fence_buf, 0, { 8, 0 }, 8)),
  { "Top", "Real" },
  "only a matching fence without an info string closes a code block"
)

local incremental_buf = vim.api.nvim_create_buf(false, true)
vim.bo[incremental_buf].filetype = "markdown"
local incremental_lines = {}
for index = 1, 600 do
  incremental_lines[index] = index % 100 == 1 and ("# Part " .. index) or "text"
end
vim.api.nvim_buf_set_lines(incremental_buf, 0, -1, false, incremental_lines)
sources.markdown.get_symbols(incremental_buf, 0, { 600, 0 }, 8)
vim.api.nvim_buf_set_lines(incremental_buf, 450, 451, false, { "## Inserted" })
vim.api.nvim_buf_set_lines(incremental_buf, 10, 12, false, {})
local incremental_symbols = sources.markdown.get_symbols(incremental_buf, 0, { 470, 0 }, 8)
sources.markdown.invalidate(incremental_buf)
eq(
  incremental_symbols,
  sources.markdown.get_symbols(incremental_buf, 0, { 470, 0 }, 8),
  "incremental Markdown parsing matches a full parse after edits"
)
eq(incremental_symbols[2].name, "Inserted", "incremental Markdown parsing sees new headings")

local duplicate_buf = vim.api.nvim_create_buf(true, false)
vim.bo[duplicate_buf].filetype = "lua"
vim.api.nvim_buf_set_lines(duplicate_buf, 0, -1, false, {
  "local function render()",
  "  local current_symbols = sources.get_symbols(source_names, {",
  "    buf = buf,",
  "  })",
  "end",
})
local has_duplicate_parser, duplicate_parser =
  pcall(vim.treesitter.get_parser, duplicate_buf, "lua")
if has_duplicate_parser then
  duplicate_parser:parse()
  local duplicate_symbols = treesitter.get_symbols(duplicate_buf, 0, { 3, 6 }, 8)
  local has_nvim_treesitter = pcall(require, "nvim-treesitter.ts_utils")
  if not has_nvim_treesitter then
    has_nvim_treesitter = pcall(require, "nvim-treesitter")
  end
  local has_locals_query = has_nvim_treesitter
    and pcall(vim.treesitter.query.get, "lua", "locals")

  eq(
    vim.tbl_map(function(symbol)
      return symbol.name
    end, duplicate_symbols),
    has_locals_query and { "render" }
      or { "render", "current_symbols", "sources.get_symbols", "buf" },
    "declaration parents do not repeat their more specific child"
  )

  local original_query_get = vim.treesitter.query.get
  local original_ts_utils_loaded = package.loaded["nvim-treesitter.ts_utils"]
  local original_ts_utils_preload = package.preload["nvim-treesitter.ts_utils"]

  local original_get_node = vim.treesitter.get_node
  local node = original_get_node({ bufnr = duplicate_buf, pos = { 2, 6 } })
  package.loaded["nvim-treesitter.ts_utils"] = nil
  package.preload["nvim-treesitter.ts_utils"] = function()
    return {
      get_node_at_cursor = function()
        return node
      end,
    }
  end
  vim.treesitter.get_node = function()
    error("native node lookup should not run when nvim-treesitter is available")
  end
  vim.treesitter.query.get = function(lang, name)
    if lang == "lua" and name == "locals" then
      return vim.treesitter.query.parse("lua", "(function_declaration) @local.scope")
    end
    return original_query_get(lang, name)
  end
  local query_symbols = treesitter.get_symbols(duplicate_buf, 0, { 3, 6 }, 8)
  vim.treesitter.query.get = original_query_get
  vim.treesitter.get_node = original_get_node
  package.preload["nvim-treesitter.ts_utils"] = original_ts_utils_preload
  package.loaded["nvim-treesitter.ts_utils"] = original_ts_utils_loaded
  eq(
    vim.tbl_map(function(symbol)
      return symbol.name
    end, query_symbols),
    { "render" },
    "nvim-treesitter node lookup and locals queries select semantic ancestors"
  )

  local original_get_parser = vim.treesitter.get_parser
  local fallback_nvim_treesitter_loaded = package.loaded["nvim-treesitter"]
  local fallback_nvim_treesitter_preload = package.preload["nvim-treesitter"]
  local fallback_ts_utils_loaded = package.loaded["nvim-treesitter.ts_utils"]
  local fallback_ts_utils_preload = package.preload["nvim-treesitter.ts_utils"]

  package.loaded["nvim-treesitter.ts_utils"] = nil
  package.loaded["nvim-treesitter"] = nil
  package.preload["nvim-treesitter"] = function()
    error("nvim-treesitter is unavailable")
  end

  package.preload["nvim-treesitter.ts_utils"] = function()
    error("nvim-treesitter is unavailable")
  end
  local original_get_node = vim.treesitter.get_node
  local node = original_get_node({ bufnr = duplicate_buf, pos = { 2, 6 } })
  vim.treesitter.get_parser = function()
    return nil
  end
  vim.treesitter.get_node = function()
    return node
  end
  local nil_parser_symbols = treesitter.get_symbols(duplicate_buf, 0, { 3, 6 }, 8)
  vim.treesitter.get_parser = original_get_parser
  vim.treesitter.get_node = original_get_node
  package.preload["nvim-treesitter.ts_utils"] = fallback_ts_utils_preload
  package.loaded["nvim-treesitter.ts_utils"] = fallback_ts_utils_loaded
  package.preload["nvim-treesitter"] = fallback_nvim_treesitter_preload
  package.loaded["nvim-treesitter"] = fallback_nvim_treesitter_loaded
  eq(
    vim.tbl_map(function(symbol)
      return symbol.name
    end, nil_parser_symbols),
    { "render", "current_symbols", "sources.get_symbols", "buf" },
    "missing nvim-treesitter falls back to ancestor matching"
  )
end

local lsp_preferred = sources.get_symbols({ "lsp", "treesitter" }, {
  buf = duplicate_buf,
  win = 0,
  cursor = { 3, 6 },
  max_depth = 8,
  lsp_symbols = { { name = "LSP symbol", kind = 12 } },
})
eq(lsp_preferred, { { name = "LSP symbol", kind = 12 } }, "LSP prevents Tree-sitter overlap")

local zed_bar = require("zed-bar")
zed_bar.setup({ path = "relative", update_debounce = 0, symbol_debounce = 0 })
vim.api.nvim_buf_set_name(0, root .. "/src/components/CNUserModal/index.tsx")
zed_bar._render(0)
eq(zed_bar._render(0), false, "unchanged winbar content does not trigger another assignment")
local winbar = vim.wo.winbar
assert(
  vim.api
    .nvim_eval_statusline(winbar, { winid = 0, use_winbar = true }).str
    :find("src/components/CNUserModal/index.tsx", 1, true),
  "relative buffer path is rendered"
)
assert(winbar:find("%#ZedBarDir#src/components/CNUserModal/%*", 1, true), "directory is dimmed")
assert(winbar:find("%#ZedBarFile#index.tsx%*", 1, true), "file name uses its own highlight")

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
  " src/components/CNUserModal/index.tsx ● ›  CNUserModal › 󰊕 setOpen ",
  "rendered layout matches the approved component order and spacing"
)

zed_bar.setup({
  kinds = { Function = "fn " },
  update_debounce = 0,
  symbol_debounce = 0,
})
zed_bar._render(0)
evaluated = vim.api.nvim_eval_statusline(vim.wo.winbar, {
  winid = 0,
  highlights = true,
  use_winbar = true,
})
assert(evaluated.str:find("fn setOpen", 1, true), "symbol kind icons can be configured")

local replacement_client = { offset_encoding = "utf-16" }
function replacement_client:request(_, _, callback)
  next_request_id = next_request_id + 1
  callbacks[next_request_id] = callback
  return true, next_request_id
end
function replacement_client:cancel_request() end
vim.lsp.get_clients = function()
  return { replacement_client }
end
local requests_before_detach = next_request_id
vim.api.nvim_exec_autocmds("LspDetach", { group = "ZedBar", buffer = 0 })
vim.wait(100, function()
  return next_request_id > requests_before_detach
end)
eq(
  next_request_id,
  requests_before_detach + 1,
  "a remaining LSP client re-requests symbols after another client detaches"
)
vim.lsp.get_clients = function()
  return { client }
end

vim.bo.filetype = "lua"
zed_bar.setup({ disabled_filetypes = { "lua" } })
eq(vim.wo.winbar, "", "disabled filetypes clear the winbar")
local requests_before_refresh = next_request_id
zed_bar.refresh()
eq(next_request_id, requests_before_refresh, "disabled filetypes do not request LSP symbols")
vim.bo.filetype = "typescriptreact"

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
assert(
  vim.api
    .nvim_eval_statusline(vim.wo.winbar, { winid = 0, use_winbar = true }).str
    :find("src/first-enter.lua", 1, true),
  "BufReadPre reserves the winbar row"
)

local custom_path_calls = 0
zed_bar.setup({
  path = function(_, name)
    custom_path_calls = custom_path_calls + 1
    return vim.fs.basename(name)
  end,
  update_debounce = 0,
})
local calls_after_setup = custom_path_calls
zed_bar._render(0)
zed_bar._render(0)
eq(custom_path_calls, calls_after_setup + 2, "custom path functions are never render-cached")

local autoread_path = vim.fn.tempname() .. ".lua"
vim.fn.writefile({ "function old()", "  return 1", "end" }, autoread_path)
vim.cmd.edit(vim.fn.fnameescape(autoread_path))
vim.bo.filetype = "lua"
local has_autoread_parser, autoread_parser = pcall(vim.treesitter.get_parser, 0, "lua")
if has_autoread_parser then
  autoread_parser:parse()
  vim.api.nvim_win_set_cursor(0, { 3, 4 })
  zed_bar._render(0)
  vim.fn.writefile({ "local x = 1" }, autoread_path)
  local checktime_ok, checktime_error = pcall(vim.cmd.checktime)
  assert(
    checktime_ok,
    "checktime should not fail while refreshing an externally changed file: "
      .. tostring(checktime_error)
  )
  eq(
    vim.api.nvim_buf_get_lines(0, 0, -1, false),
    { "local x = 1" },
    "checktime loads the externally changed file"
  )
  vim.wait(100)
  assert(not vim.wo.winbar:find("old", 1, true), "checktime refreshes the Tree-sitter winbar")
end
vim.fn.delete(autoread_path)

vim.cmd.runtime("plugin/zed-bar.lua")
local icons = require("zed-bar.kinds").icons

local function names(list)
  return vim.tbl_map(function(symbol)
    return symbol.name
  end, list)
end

local scope_buf = vim.api.nvim_create_buf(true, false)
vim.bo[scope_buf].filetype = "lua"
vim.api.nvim_buf_set_lines(scope_buf, 0, -1, false, {
  "local function request_symbols(buf)",
  "  local _, request_id = client:request(",
  "    'textDocument/documentSymbol',",
  "    {},",
  "    function(err, result)",
  "      if not err then",
  "        state.symbols = result",
  "      end",
  "    end",
  "  )",
  "  local count = 1",
  "end",
  "describe('x', function()",
  "  it('works', function()",
  "    assert(true)",
  "  end)",
  "end)",
})
local has_scope_parser, scope_parser = pcall(vim.treesitter.get_parser, scope_buf, "lua")
if has_scope_parser then
  scope_parser:parse()
  eq(
    names(treesitter.get_symbols(scope_buf, 0, { 7, 10 }, 8, "scope")),
    { "request_symbols", "client:request" },
    "scope detail names an anonymous callback after its call and drops locals and control flow"
  )
  eq(
    names(treesitter.get_symbols(scope_buf, 0, { 11, 10 }, 8, "scope")),
    { "request_symbols" },
    "scope detail drops bindings that do not hold a scope"
  )
  eq(
    names(treesitter.get_symbols(scope_buf, 0, { 15, 4 }, 8, "scope")),
    { "describe", "it" },
    "scope detail names test blocks after their calls"
  )
  assert(
    vim.iter(treesitter.get_symbols(scope_buf, 0, { 7, 10 }, 8, "full")):any(function(symbol)
      return symbol.kind == "IfStatement"
    end),
    "full detail keeps control flow"
  )
  local first_scope = treesitter.get_symbols(scope_buf, 0, { 7, 10 }, 8, "scope")[1]
  eq({ first_scope.row, first_scope.col }, { 0, 0 }, "Tree-sitter symbols carry their start")
end

if has_parser then
  local react_buf = vim.api.nvim_create_buf(true, false)
  vim.bo[react_buf].filetype = "typescript"
  vim.api.nvim_buf_set_lines(react_buf, 0, -1, false, {
    "const App = () => {",
    "  const handler = () => {",
    "    if (ready) {",
    "      run()",
    "    }",
    "  }",
    "  return null",
    "}",
  })
  vim.treesitter.get_parser(react_buf, "typescript"):parse()
  eq(
    names(treesitter.get_symbols(react_buf, 0, { 4, 6 }, 8, "scope")),
    { "App", "handler" },
    "scope detail names arrow functions after their variables"
  )
  eq(
    names(treesitter.get_symbols(react_buf, 0, { 7, 4 }, 8, "scope")),
    { "App" },
    "scope detail drops return statements"
  )
end

local local_tree = symbols.normalize({
  {
    name = "outer",
    kind = 12,
    range = { start = { line = 0, character = 0 }, ["end"] = { line = 10, character = 0 } },
    children = {
      {
        name = "count",
        kind = 13,
        range = { start = { line = 3, character = 2 }, ["end"] = { line = 3, character = 20 } },
      },
      {
        name = "callback",
        kind = 13,
        range = { start = { line = 5, character = 2 }, ["end"] = { line = 8, character = 3 } },
      },
    },
  },
})
eq(
  names(symbols.scope(symbols.path(local_tree, { line = 3, character = 4 }))),
  { "outer" },
  "scope detail drops a single-line LSP variable at the cursor"
)
eq(
  names(symbols.scope(symbols.path(local_tree, { line = 6, character = 4 }))),
  { "outer", "callback" },
  "scope detail keeps a multi-line LSP variable"
)

vim.cmd("silent! only")
local ux_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(ux_buf, root .. "/src/ux/panel.tsx")
vim.api.nvim_win_set_buf(0, ux_buf)
vim.api.nvim_buf_set_lines(ux_buf, 0, -1, false, vim.fn["repeat"]({ "        code" }, 30))
local function lsp_range(start_line, start_character, end_line, end_character)
  return {
    start = { line = start_line, character = start_character },
    ["end"] = { line = end_line, character = end_character },
  }
end
local ux_symbols = {
  {
    name = "Panel",
    kind = 5,
    range = lsp_range(0, 0, 19, 1),
    children = {
      { name = "open", kind = 6, range = lsp_range(2, 2, 5, 3) },
      {
        name = "close",
        kind = 6,
        range = lsp_range(7, 2, 10, 3),
        children = { { name = "count", kind = 13, range = lsp_range(8, 4, 8, 20) } },
      },
    },
  },
  { name = "helper", kind = 12, range = lsp_range(21, 0, 25, 1) },
}
local ux_client = { offset_encoding = "utf-16" }
function ux_client:request(_, _, callback)
  vim.schedule(function()
    callback(nil, ux_symbols)
  end)
  return true, 1
end
function ux_client:cancel_request() end
vim.lsp.get_clients = function()
  return { ux_client }
end

local function rendered(win)
  return vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str
end

zed_bar.setup({ update_debounce = 0, symbol_debounce = 0 })
vim.api.nvim_win_set_cursor(0, { 9, 6 })
zed_bar.refresh()
vim.wait(200, function()
  return vim.wo.winbar:find("close", 1, true) ~= nil
end)
eq(
  rendered(0),
  " src/ux/panel.tsx ● › " .. icons.Class .. "Panel › " .. icons.Method .. "close ",
  "scope detail drops the local variable at the cursor and the modified flag follows the name"
)
assert(vim.wo.winbar:find("ZedBarModified", 1, true), "modified flag has its own highlight")
vim.bo[ux_buf].modified = false
zed_bar._render(0)
eq(
  rendered(0),
  " src/ux/panel.tsx › " .. icons.Class .. "Panel › " .. icons.Method .. "close ",
  "the modified flag disappears after the buffer is saved"
)
vim.bo[ux_buf].readonly = true
zed_bar._render(0)
assert(vim.wo.winbar:find("ZedBarReadonly", 1, true), "readonly buffers are flagged")
vim.bo[ux_buf].readonly = false

local wide_win = vim.api.nvim_get_current_win()
vim.cmd("vsplit")
local narrow_win = vim.api.nvim_get_current_win()
vim.cmd("vertical resize 37")
zed_bar._render(narrow_win)
eq(
  rendered(narrow_win),
  " s/u/panel.tsx › " .. icons.Class .. "Panel › " .. icons.Method .. "close ",
  "directories are abbreviated first when the window is narrow"
)
vim.cmd("vertical resize 26")
zed_bar._render(narrow_win)
eq(
  rendered(narrow_win),
  " panel.tsx › … › " .. icons.Method .. "close ",
  "outer symbols collapse and directories drop before the file name or innermost symbol"
)
vim.cmd("vertical resize 14")
zed_bar._render(narrow_win)
local tiny = rendered(narrow_win)
assert(vim.api.nvim_strwidth(tiny) <= 14, "the winbar fits a tiny window: " .. tiny)
assert(tiny:find("panel.tsx", 1, true), "the file name survives a tiny window: " .. tiny)

assert(vim.wo[wide_win].winbar:find("ZedBarInactive", 1, true), "inactive windows are dimmed")
assert(
  not vim.wo[wide_win].winbar:find("ZedBarKindMethod", 1, true),
  "inactive windows do not use kind colors"
)
assert(
  not vim.wo[narrow_win].winbar:find("ZedBarInactive", 1, true),
  "the active window is not dimmed"
)
vim.api.nvim_set_current_win(wide_win)
assert(
  vim.wo[narrow_win].winbar:find("ZedBarInactive", 1, true),
  "the window that loses focus is dimmed"
)
assert(
  not vim.wo[wide_win].winbar:find("ZedBarInactive", 1, true),
  "the window that gains focus is no longer dimmed"
)
vim.api.nvim_win_set_width(narrow_win, 40)
zed_bar.setup({ dim_inactive = false, update_debounce = 0, symbol_debounce = 0 })
assert(
  vim.wo[narrow_win].winbar:find("ZedBarKindMethod", 1, true),
  "dim_inactive = false keeps kind colors in inactive windows"
)
vim.cmd("silent! only")

zed_bar.setup({ icons = false, update_debounce = 0, symbol_debounce = 0 })
eq(rendered(0), " src/ux/panel.tsx › Panel › close ", "icons = false renders plain names")

zed_bar.setup({ update_debounce = 0, symbol_debounce = 0 })
local source_win = vim.api.nvim_get_current_win()
local function menu_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end
local function press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
end

vim.api.nvim_win_set_cursor(source_win, { 9, 6 })
zed_bar.pick()
assert(
  vim.api.nvim_get_current_win() ~= source_win and vim.api.nvim_win_get_config(0).relative ~= "",
  "pick opens a floating menu"
)
eq(
  menu_lines(),
  { icons.Method .. "open", icons.Method .. "close" },
  "the menu lists the siblings of the innermost symbol"
)
eq(vim.api.nvim_win_get_cursor(0)[1], 2, "the current symbol is selected")
press("h")
eq(
  menu_lines(),
  { icons.Class .. "Panel", icons.Function .. "helper" },
  "h moves up to the parent level"
)
eq(vim.api.nvim_win_get_cursor(0)[1], 1, "the parent is selected")
press("l")
eq(menu_lines(), { icons.Method .. "open", icons.Method .. "close" }, "l opens the children")
eq(vim.api.nvim_win_get_cursor(0)[1], 2, "the child on the current path is selected")
press("k")
press("<CR>")
eq(vim.api.nvim_get_current_win(), source_win, "choosing an entry closes the menu")
eq(vim.api.nvim_win_get_cursor(source_win), { 3, 2 }, "choosing an entry jumps to its start")

zed_bar.pick()
press("q")
eq(vim.api.nvim_get_current_win(), source_win, "q closes the menu")
eq(#vim.api.nvim_list_wins(), 1, "closing the menu removes the float")

vim.api.nvim_win_set_cursor(source_win, { 9, 6 })
zed_bar._render(source_win)
zed_bar._click(1, 1, "l", "    ")
eq(
  menu_lines(),
  { icons.Class .. "Panel", icons.Function .. "helper" },
  "clicking the file name opens the top-level outline"
)
press("<Esc>")
zed_bar._click(3, 1, "l", "    ")
eq(
  menu_lines(),
  { icons.Method .. "open", icons.Method .. "close" },
  "clicking a symbol opens its siblings"
)
press("<Esc>")

vim.api.nvim_win_set_cursor(source_win, { 9, 6 })
zed_bar.parent()
eq(vim.api.nvim_win_get_cursor(0), { 8, 2 }, "parent jumps to the enclosing symbol start")
zed_bar.parent()
eq(vim.api.nvim_win_get_cursor(0), { 1, 0 }, "a second parent jump goes one level up")

local original_notify = vim.notify
local notified
vim.notify = function(message)
  notified = message
end
vim.api.nvim_win_set_cursor(source_win, { 9, 6 })
zed_bar.yank()
eq(vim.fn.getreg('"'), "src/ux/panel.tsx › Panel › close", "yank copies the breadcrumb text")

vim.cmd("ZedBar toggle")
eq(vim.wo.winbar, "", "toggle hides the winbar")
vim.cmd("ZedBar toggle")
assert(vim.wo.winbar:find("panel.tsx", 1, true), "toggle shows the winbar again")
eq(
  vim.fn.getcompletion("ZedBar ", "cmdline"),
  { "info", "parent", "pick", "refresh", "toggle", "yank" },
  ":ZedBar completes its subcommands"
)
vim.cmd("ZedBar info")
vim.notify = original_notify
assert(notified and notified:find("lsp", 1, true), "info reports the active source")

local guide_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(guide_buf, root .. "/docs/guide.md")
vim.bo[guide_buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(guide_buf, 0, -1, false, {
  "# Intro",
  "## Setup",
  "text",
  "## Usage",
  "text",
  "# API",
})
vim.api.nvim_win_set_buf(source_win, guide_buf)
vim.api.nvim_win_set_cursor(source_win, { 5, 0 })
zed_bar.pick()
eq(
  menu_lines(),
  { icons.MarkdownH2 .. "Setup", icons.MarkdownH2 .. "Usage" },
  "Markdown headings list their siblings"
)
eq(vim.api.nvim_win_get_cursor(0)[1], 2, "the current heading is selected")
press("h")
eq(
  menu_lines(),
  { icons.MarkdownH1 .. "Intro", icons.MarkdownH1 .. "API" },
  "h moves up to the parent heading level"
)
press("j")
press("<CR>")
eq(vim.api.nvim_win_get_cursor(source_win), { 6, 0 }, "choosing a heading jumps to it")

vim.lsp.get_clients = function()
  return {}
end
if has_scope_parser then
  vim.api.nvim_buf_set_name(scope_buf, root .. "/src/scope.lua")
  vim.api.nvim_win_set_buf(source_win, scope_buf)
  vim.api.nvim_win_set_cursor(source_win, { 7, 10 })
  zed_bar.pick()
  eq(
    menu_lines(),
    { icons.Function .. "request_symbols", icons.Call .. "client:request" },
    "Tree-sitter breadcrumbs open as a list of enclosing scopes"
  )
  press("k")
  press("<CR>")
  eq(vim.api.nvim_win_get_cursor(source_win), { 1, 0 }, "choosing a scope jumps to it")
end
vim.lsp.get_clients = original_get_clients

print("zed-bar.nvim tests passed")
