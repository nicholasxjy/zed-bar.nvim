local config = require("zed-bar.config")
local kinds = require("zed-bar.kinds")
local symbols = require("zed-bar.symbols")

local M = {}

local group = vim.api.nvim_create_augroup("ZedBar", { clear = true })
local cache = {}
local window_timers = {}
local symbol_timers = {}

local function statusline_escape(value)
  return value:gsub("%%", "%%%%")
end

local function component(text, highlight)
  return "%#" .. highlight .. "#" .. statusline_escape(text) .. "%*"
end

local function get_path(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if config.options.path == "basename" then
    return vim.fs.basename(name)
  end
  if type(config.options.path) == "function" then
    return config.options.path(buf, name)
  end
  return vim.fn.fnamemodify(name, ":~:.")
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
    vim.wo[win].winbar = ""
    return
  end

  local parts = { component(get_path(buf), "ZedBarFile") }
  local state = cache[buf]
  if state and state.symbols then
    local path =
      symbols.path(state.symbols, position(win, state.encoding), config.options.max_depth)
    for _, symbol in ipairs(path) do
      local kind = symbols.kind(symbol)
      table.insert(parts, component(config.options.separator, "ZedBarSeparator"))
      table.insert(parts, component(kinds.icons[kind] or "", "ZedBarIconKind" .. kind))
      table.insert(parts, component(symbol.name, "ZedBarKind" .. kind))
    end
  end

  local padding = config.options.padding
  vim.wo[win].winbar = component(string.rep(" ", padding.left), "ZedBarNormal")
    .. table.concat(parts)
    .. component(string.rep(" ", padding.right), "ZedBarNormal")
end

local function render_buffer(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    render(win)
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
  symbol_timers[buf]:start(
    config.options.symbol_debounce,
    0,
    vim.schedule_wrap(function()
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
  if symbol_timers[buf] then
    symbol_timers[buf]:stop()
    symbol_timers[buf]:close()
    symbol_timers[buf] = nil
  end
end

function M.setup(opts)
  config.setup(opts)
  kinds.setup_highlights()

  vim.api.nvim_clear_autocmds({ group = group })
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
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
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
        window_timers[win]:stop()
        window_timers[win]:close()
        window_timers[win] = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = kinds.setup_highlights,
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
  request_symbols(buf or vim.api.nvim_get_current_buf())
end

M._symbols = symbols
M._render = render

return M
