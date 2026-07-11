local config = require("zed-bar.config")
local kinds = require("zed-bar.kinds")
local sources = require("zed-bar.sources")
local symbols = require("zed-bar.symbols")

local M = {}

local group = vim.api.nvim_create_augroup("ZedBar", { clear = true })
local cache = {}
local path_cache = {}
local render_cache = {}
local window_timers = {}
local symbol_timers = {}
local symbol_timer_generations = {}
local timer_generation = 0

local function statusline_escape(value)
  return value:gsub("%%", "%%%%")
end

local function component(text, highlight)
  return "%#" .. highlight .. "#" .. statusline_escape(text) .. "%*"
end

local function set_winbar(win, value)
  if vim.wo[win].winbar == value then
    return false
  end
  vim.wo[win].winbar = value
  return true
end

local function close_timer(timer)
  if not timer then
    return
  end
  timer:stop()
  if not timer:is_closing() then
    timer:close()
  end
end

local function get_path(buf, name)
  if config.options.path == "basename" then
    local cached = path_cache[buf]
    if cached and cached.name == name and cached.mode == "basename" then
      return cached.value
    end
    local value = vim.fs.basename(name)
    path_cache[buf] = { mode = "basename", name = name, value = value }
    return value
  end
  if type(config.options.path) == "function" then
    return config.options.path(buf, name)
  end
  local cached = path_cache[buf]
  if cached and cached.name == name and cached.mode == "relative" then
    return cached.value
  end
  local value = vim.fn.fnamemodify(name, ":~:.")
  path_cache[buf] = { mode = "relative", name = name, value = value }
  return value
end

local function position(win, encoding)
  local ok, params = pcall(vim.lsp.util.make_position_params, win, encoding or "utf-16")
  if ok then
    return params.position
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  return { line = cursor[1] - 1, character = cursor[2] }
end

local function render(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if not config.options.enabled(buf, win) then
    render_cache[win] = nil
    return set_winbar(win, "")
  end

  local state = cache[buf]
  local cursor = vim.api.nvim_win_get_cursor(win)
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local filetype = vim.bo[buf].filetype
  local can_cache = type(config.options.path) ~= "function"
    and config.options.sources == config.defaults.sources
  local previous_render = render_cache[win]
  local lsp_symbols_table = state and state.symbols or nil
  if
    can_cache
    and previous_render
    and previous_render.buf == buf
    and previous_render.changedtick == changedtick
    and previous_render.col == cursor[2]
    and previous_render.filetype == filetype
    and previous_render.line == cursor[1]
    and previous_render.lsp_symbols == lsp_symbols_table
    and previous_render.name == name
    and previous_render.value == vim.wo[win].winbar
  then
    return false
  end

  local parts = { component(get_path(buf, name), "ZedBarFile") }
  local lsp_symbols = {}
  if state and state.symbols then
    lsp_symbols =
      symbols.path(state.symbols, position(win, state.encoding), config.options.max_depth)
  end

  local source_names = config.options.sources
  if type(source_names) == "function" then
    source_names = source_names(buf, win)
  end
  local current_symbols = sources.get_symbols(source_names, {
    buf = buf,
    win = win,
    cursor = cursor,
    max_depth = config.options.max_depth,
    lsp_symbols = lsp_symbols,
  })
  for _, symbol in ipairs(current_symbols) do
    local kind = symbols.kind(symbol)
    table.insert(parts, component(config.options.separator, "ZedBarSeparator"))
    table.insert(parts, component(kinds.icons[kind] or "", "ZedBarIconKind" .. kind))
    table.insert(parts, component(symbol.name, "ZedBarKind" .. kind))
  end

  local padding = config.options.padding
  local value = component(string.rep(" ", padding.left), "ZedBarNormal")
    .. table.concat(parts)
    .. component(string.rep(" ", padding.right), "ZedBarNormal")
  if can_cache then
    local current_render = previous_render or {}
    current_render.buf = buf
    current_render.changedtick = changedtick
    current_render.col = cursor[2]
    current_render.filetype = filetype
    current_render.line = cursor[1]
    current_render.lsp_symbols = lsp_symbols_table
    current_render.name = name
    current_render.value = value
    render_cache[win] = current_render
  else
    render_cache[win] = nil
  end
  return set_winbar(win, value)
end

local function render_buffer(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    render(win)
  end
end

local function invalidate_render_buffer(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    render_cache[win] = nil
  end
end

local function schedule_render(win)
  if window_timers[win] then
    window_timers[win]:stop()
  else
    window_timers[win] = vim.uv.new_timer()
  end
  window_timers[win]:start(
    config.options.update_debounce,
    0,
    vim.schedule_wrap(function()
      render(win)
    end)
  )
end

local function supporting_client(buf)
  return vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" })[1]
end

local function request_symbols(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local client = supporting_client(buf)
  if not client then
    cache[buf] = nil
    render_buffer(buf)
    return
  end

  local state = cache[buf] or { symbols = {} }
  cache[buf] = state
  if state.client and state.request_id then
    state.client:cancel_request(state.request_id)
  end
  state.client = client
  state.encoding = client.offset_encoding

  local request_id
  local _
  _, request_id = client:request(
    "textDocument/documentSymbol",
    { textDocument = vim.lsp.util.make_text_document_params(buf) },
    function(err, result)
      if cache[buf] ~= state or request_id ~= state.request_id then
        return
      end
      state.request_id = nil
      if not err then
        state.symbols = symbols.normalize(result)
        render_buffer(buf)
      end
    end,
    buf
  )
  state.request_id = request_id
end

local function schedule_symbols(buf)
  if symbol_timers[buf] then
    symbol_timers[buf]:stop()
  else
    symbol_timers[buf] = vim.uv.new_timer()
  end
  timer_generation = timer_generation + 1
  local generation = timer_generation
  symbol_timer_generations[buf] = generation
  symbol_timers[buf]:start(
    config.options.symbol_debounce,
    0,
    vim.schedule_wrap(function()
      if symbol_timer_generations[buf] ~= generation then
        return
      end
      local timer = symbol_timers[buf]
      symbol_timers[buf] = nil
      symbol_timer_generations[buf] = nil
      close_timer(timer)
      invalidate_render_buffer(buf)
      sources.invalidate(buf)
      request_symbols(buf)
    end)
  )
end

local function cleanup(buf)
  local state = cache[buf]
  if state and state.client and state.request_id then
    state.client:cancel_request(state.request_id)
  end
  cache[buf] = nil
  path_cache[buf] = nil
  sources.invalidate(buf)
  if symbol_timers[buf] then
    close_timer(symbol_timers[buf])
    symbol_timers[buf] = nil
  end
  symbol_timer_generations[buf] = nil
  invalidate_render_buffer(buf)
end

function M.setup(opts)
  for _, timer in pairs(window_timers) do
    close_timer(timer)
  end
  for _, timer in pairs(symbol_timers) do
    close_timer(timer)
  end
  window_timers = {}
  symbol_timers = {}
  symbol_timer_generations = {}
  config.setup(opts)
  kinds.setup_highlights()
  path_cache = {}
  render_cache = {}

  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile", "BufEnter" }, {
    group = group,
    callback = function(args)
      render_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    callback = function(args)
      render(vim.api.nvim_get_current_win())
      if supporting_client(args.buf) and not cache[args.buf] then
        request_symbols(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufFilePost", {
    group = group,
    callback = function(args)
      path_cache[args.buf] = nil
      invalidate_render_buffer(args.buf)
      render_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(args)
      render_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function()
      schedule_render(vim.api.nvim_get_current_win())
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = group,
    callback = function(args)
      schedule_symbols(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      vim.schedule(function()
        request_symbols(args.buf)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(args)
      vim.schedule(function()
        if not supporting_client(args.buf) then
          cleanup(args.buf)
          render_buffer(args.buf)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload", "BufWipeout" }, {
    group = group,
    callback = function(args)
      cleanup(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      if win and window_timers[win] then
        close_timer(window_timers[win])
        window_timers[win] = nil
      end
      if win then
        render_cache[win] = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = kinds.setup_highlights,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      path_cache = {}
      render_cache = {}
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        render(win)
      end
    end,
  })

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    render(win)
    local buf = vim.api.nvim_win_get_buf(win)
    if supporting_client(buf) and not cache[buf] then
      request_symbols(buf)
    end
  end
end

function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  invalidate_render_buffer(buf)
  sources.invalidate(buf)
  request_symbols(buf)
end

M._symbols = symbols
M._sources = sources
M._render = render
M._set_winbar = set_winbar

return M
