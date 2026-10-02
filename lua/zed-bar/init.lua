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
local window_callbacks = {}
local symbol_timers = {}
local symbol_timer_generations = {}
local timer_generation = 0
-- Values derived from `config.options` once per `setup()` instead of on every render.
local compiled = {}

local function statusline_escape(value)
  return value:gsub("%%", "%%%%")
end

local function component(text, highlight)
  return "%#" .. highlight .. "#" .. statusline_escape(text) .. "%*"
end

local function get_winbar(win)
  return vim.api.nvim_get_option_value("winbar", { win = win })
end

local function set_winbar(win, value)
  if get_winbar(win) == value then
    return false
  end
  vim.api.nvim_set_option_value("winbar", value, { win = win })
  return true
end

local function compile_options()
  local options = config.options
  local disabled = {}
  for _, filetype in ipairs(options.disabled_filetypes) do
    disabled[filetype] = true
  end
  compiled = {
    disabled = disabled,
    -- A user `path` or `sources` function may depend on state outside the render cache key.
    can_cache = type(options.path) ~= "function"
      and (type(options.sources) == "table" or options.sources == config.defaults.sources),
    left = component(string.rep(" ", options.padding.left), "ZedBarNormal"),
    right = component(string.rep(" ", options.padding.right), "ZedBarNormal"),
    separator = component(options.separator, "ZedBarSeparator"),
    kind_prefixes = {},
  }
end
compile_options()

-- Separator, icon and name highlight for a symbol kind; only the symbol name varies per render.
local function kind_prefix(kind)
  local prefix = compiled.kind_prefixes[kind]
  if not prefix then
    prefix = compiled.separator
      .. component(config.options.kinds[kind] or "", "ZedBarIconKind" .. kind)
      .. "%#ZedBarKind"
      .. kind
      .. "#"
    compiled.kind_prefixes[kind] = prefix
  end
  return prefix
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

-- `path_cache` is reset by `setup()` and `DirChanged`, so it only has to be keyed by name.
local function get_path(buf, name)
  local path = config.options.path
  if type(path) == "function" then
    return path(buf, name)
  end
  local cached = path_cache[buf]
  if cached and cached.name == name then
    return cached.value
  end
  local value = path == "basename" and vim.fs.basename(name) or vim.fn.fnamemodify(name, ":~:.")
  path_cache[buf] = { name = name, value = value }
  return value
end

local function position(buf, cursor, encoding)
  local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], true)[1]
  if not line then
    return { line = 0, character = 0 }
  end
  return {
    line = cursor[1] - 1,
    character = vim.str_utfindex(line, encoding or "utf-16", cursor[2], false),
  }
end

local function is_disabled(buf)
  return compiled.disabled[vim.api.nvim_get_option_value("filetype", { buf = buf })] == true
end

local function is_enabled(buf, win)
  return not is_disabled(buf) and config.options.enabled(buf, win)
end

local function render(win, path_only)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if not is_enabled(buf, win) then
    render_cache[win] = nil
    return set_winbar(win, "")
  end

  local name = vim.api.nvim_buf_get_name(buf)
  if path_only then
    local value = compiled.left .. component(get_path(buf, name), "ZedBarFile") .. compiled.right
    render_cache[win] = nil
    return set_winbar(win, value)
  end

  local state = cache[buf]
  local cursor = vim.api.nvim_win_get_cursor(win)
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
  local current_mode = vim.api.nvim_get_mode().mode
  local current_winbar = get_winbar(win)
  local can_cache = compiled.can_cache
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
    and previous_render.mode == current_mode
    and previous_render.name == name
    and previous_render.value == current_winbar
  then
    return false
  end

  local parts = { compiled.left, component(get_path(buf, name), "ZedBarFile") }
  local function lsp_symbols()
    if not lsp_symbols_table or not lsp_symbols_table[1] then
      return {}
    end
    return symbols.path(
      lsp_symbols_table,
      position(buf, cursor, state.encoding),
      config.options.max_depth
    )
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
    parts[#parts + 1] = kind_prefix(symbols.kind(symbol))
    parts[#parts + 1] = statusline_escape(symbol.name)
    parts[#parts + 1] = "%*"
  end
  parts[#parts + 1] = compiled.right

  local value = table.concat(parts)
  if can_cache then
    local current_render = previous_render or {}
    current_render.buf = buf
    current_render.changedtick = changedtick
    current_render.col = cursor[2]
    current_render.filetype = filetype
    current_render.line = cursor[1]
    current_render.lsp_symbols = lsp_symbols_table
    current_render.mode = current_mode
    current_render.name = name
    current_render.value = value
    render_cache[win] = current_render
  else
    render_cache[win] = nil
  end
  return set_winbar(win, value)
end

local function render_buffer(buf, path_only)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    render(win, path_only)
  end
end

local function invalidate_render_buffer(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    render_cache[win] = nil
  end
end

local function schedule_render(win)
  local timer = window_timers[win]
  if not timer then
    timer = vim.uv.new_timer()
    window_timers[win] = timer
    window_callbacks[win] = vim.schedule_wrap(function()
      render(win)
    end)
  end
  -- Starting an active timer restarts it, which is the debounce.
  timer:start(config.options.update_debounce, 0, window_callbacks[win])
end

local function supporting_client(buf)
  return vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" })[1]
end

local function request_symbols(buf)
  if not vim.api.nvim_buf_is_valid(buf) or is_disabled(buf) then
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
      -- Source caches follow `changedtick` themselves; dropping them here would force the
      -- Markdown source to re-parse the whole buffer after every edit.
      invalidate_render_buffer(buf)
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
  window_callbacks = {}
  symbol_timers = {}
  symbol_timer_generations = {}
  config.setup(opts)
  compile_options()
  kinds.setup_highlights(config.options.kinds)
  path_cache = {}
  render_cache = {}

  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd("BufReadPre", {
    group = group,
    callback = function(args)
      render_buffer(args.buf, true)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufNewFile", "BufEnter" }, {
    group = group,
    callback = function(args)
      render_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(args)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(args.buf) then
          return
        end
        -- The Tree-sitter source re-parses a stale tree itself before looking up nodes.
        invalidate_render_buffer(args.buf)
        sources.invalidate(args.buf)
        request_symbols(args.buf)
      end)
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
      if is_disabled(args.buf) then
        cleanup(args.buf)
      end
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
        if not vim.api.nvim_buf_is_valid(args.buf) then
          return
        end
        local client = supporting_client(args.buf)
        if not client then
          cleanup(args.buf)
          render_buffer(args.buf)
        elseif not cache[args.buf] or cache[args.buf].client ~= client then
          -- Another client can still provide symbols; replace the detached client's results.
          request_symbols(args.buf)
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
        window_callbacks[win] = nil
      end
      if win then
        render_cache[win] = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      kinds.setup_highlights(config.options.kinds)
    end,
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
    local buf = vim.api.nvim_win_get_buf(win)
    if is_disabled(buf) then
      cleanup(buf)
    end
    render(win)
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
