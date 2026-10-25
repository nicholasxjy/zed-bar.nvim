local config = require("zed-bar.config")
local kinds = require("zed-bar.kinds")
local menu = require("zed-bar.menu")
local sources = require("zed-bar.sources")
local symbols = require("zed-bar.symbols")

local M = {}

local group = vim.api.nvim_create_augroup("ZedBar", { clear = true })
local cache = {}
local path_cache = {}
local render_cache = {}
-- What the last render of each window showed, for clicks and navigation.
local shown = {}
local window_timers = {}
local window_callbacks = {}
local symbol_timers = {}
local symbol_timer_generations = {}
local timer_generation = 0
-- The last focused non-floating window; it stays active while a float (such as the menu) has
-- focus.
local active_win
local hidden = false
local devicons
-- Values derived from `config.options` once per `setup()` instead of on every render.
local compiled = {}

local click_handler = "v:lua.require'zed-bar'._click"
local strwidth = vim.api.nvim_strwidth

local function statusline_escape(value)
  return value:gsub("%%", "%%%%")
end

local function component(text, highlight)
  return "%#" .. highlight .. "#" .. statusline_escape(text) .. "%*"
end

-- Click regions use 1-based ids: 1 is the file, `index + 1` is the symbol at `index`.
local function click_start(id)
  return "%" .. id .. "@" .. click_handler .. "@"
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

local function compile_style(dim)
  local options = config.options
  local status = options.file_status or {}
  local function highlight(name)
    return dim and "ZedBarInactive" or name
  end
  return {
    highlight = highlight,
    left = component(string.rep(" ", options.padding.left), highlight("ZedBarNormal")),
    right = component(string.rep(" ", options.padding.right), highlight("ZedBarNormal")),
    separator = component(options.separator, highlight("ZedBarSeparator")),
    ellipsis = component("…", highlight("ZedBarSeparator")),
    modified = status.modified and component(" " .. status.modified, highlight("ZedBarModified")),
    readonly = status.readonly and component(" " .. status.readonly, highlight("ZedBarReadonly")),
    kind_prefixes = {},
  }
end

local function compile_options()
  local options = config.options
  local disabled = {}
  for _, filetype in ipairs(options.disabled_filetypes) do
    disabled[filetype] = true
  end
  local status = options.file_status or {}
  compiled = {
    disabled = disabled,
    -- A user `path` or `sources` function may depend on state outside the render cache key.
    can_cache = type(options.path) ~= "function"
      and (type(options.sources) == "table" or options.sources == config.defaults.sources),
    padding_width = options.padding.left + options.padding.right,
    separator_width = strwidth(options.separator),
    modified_width = status.modified and strwidth(" " .. status.modified) or 0,
    readonly_width = status.readonly and strwidth(" " .. status.readonly) or 0,
    icon_widths = {},
    active = compile_style(false),
  }
  compiled.inactive = options.dim_inactive and compile_style(true) or compiled.active
end
compile_options()

local function kind_icon(kind)
  return config.options.icons and config.options.kinds[kind] or ""
end

local function kind_icon_width(kind)
  local width = compiled.icon_widths[kind]
  if not width then
    width = strwidth(kind_icon(kind))
    compiled.icon_widths[kind] = width
  end
  return width
end

-- Icon and name highlight for a symbol kind; only the symbol name varies per render.
local function kind_prefix(style, kind)
  local prefix = style.kind_prefixes[kind]
  if not prefix then
    prefix = component(kind_icon(kind), style.highlight("ZedBarIconKind" .. kind))
      .. "%#"
      .. style.highlight("ZedBarKind" .. kind)
      .. "#"
    style.kind_prefixes[kind] = prefix
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

local function file_icon(name)
  if not config.options.icons then
    return
  end
  local mini_icons = rawget(_G, "MiniIcons")
  if mini_icons then
    local ok, icon, highlight = pcall(mini_icons.get, "file", name)
    if ok and icon then
      return icon .. " ", highlight
    end
  end
  if devicons == nil then
    local ok, module = pcall(require, "nvim-web-devicons")
    devicons = ok and module or false
  end
  if devicons then
    local icon, highlight = devicons.get_icon(vim.fs.basename(name), nil, { default = true })
    if icon then
      return icon .. " ", highlight
    end
  end
end

-- "lua/zed-bar/" -> "l/z/", keeping "~" and the dot of hidden directories.
local function abbreviate(dir)
  return (
    dir:gsub("([^/]+)/", function(part)
      return vim.fn.strcharpart(part, 0, part:sub(1, 1) == "." and 2 or 1) .. "/"
    end)
  )
end

local function path_info(buf, name)
  local value = config.options.path
  value = type(value) == "function" and value(buf, name)
    or value == "basename" and vim.fs.basename(name)
    or vim.fn.fnamemodify(name, ":~:.")
  local dir, file = value:match("^(.*/)([^/]*)$")
  dir, file = dir or "", file or value
  local short_dir = abbreviate(dir)
  local icon, icon_highlight = file_icon(name)
  return {
    name = name,
    value = value,
    dir = dir,
    dir_width = strwidth(dir),
    short_dir = short_dir,
    short_dir_width = strwidth(short_dir),
    file = file,
    file_width = strwidth(file),
    icon = icon,
    icon_highlight = icon_highlight or "ZedBarFile",
    icon_width = icon and strwidth(icon) or 0,
  }
end

-- `path_cache` is reset by `setup()` and `DirChanged`, so it only has to be keyed by name.
local function get_path(buf, name)
  if type(config.options.path) == "function" then
    return path_info(buf, name)
  end
  local cached = path_cache[buf]
  if cached and cached.name == name then
    return cached
  end
  cached = path_info(buf, name)
  path_cache[buf] = cached
  return cached
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
  return not hidden and not is_disabled(buf) and config.options.enabled(buf, win)
end

local function is_active(win)
  local current = vim.api.nvim_get_current_win()
  return win == current
    or (win == active_win and vim.api.nvim_win_get_config(current).relative ~= "")
end

local function truncate_width(text, width)
  local result = ""
  for index = 1, vim.fn.strchars(text) do
    local next_result = vim.fn.strcharpart(text, 0, index)
    if strwidth(next_result) > width then
      break
    end
    result = next_result
  end
  return result
end

-- Fits the breadcrumb into `width` by giving up, in order: full directory names, outer symbols
-- (collapsed into "…"), the directory, the end of the innermost name, and finally all symbols.
-- The file name is kept longest.
local function layout(info, current_symbols, status_width, width)
  local separator_width = compiled.separator_width
  local fixed = compiled.padding_width + info.icon_width + info.file_width + status_width
  local count = #current_symbols
  local widths, symbols_width = {}, 0
  for index, symbol in ipairs(current_symbols) do
    widths[index] = separator_width + kind_icon_width(symbols.kind(symbol)) + strwidth(symbol.name)
    symbols_width = symbols_width + widths[index]
  end

  local result = { dir = info.dir, first = 1, last = count }
  local total = fixed + info.dir_width + symbols_width
  if total <= width then
    return result
  end

  result.dir = info.short_dir
  total = total - info.dir_width + info.short_dir_width
  while total > width and result.first < count do
    if result.first == 1 then
      total = total + separator_width + 1
    end
    total = total - widths[result.first]
    result.first = result.first + 1
  end
  if total > width and result.dir ~= "" then
    total = total - info.short_dir_width
    result.dir = ""
  end
  if total > width and count > 0 then
    local name = current_symbols[count].name
    local room = strwidth(name) - (total - width) - 1
    if room >= 1 then
      result.last_name = truncate_width(name, room) .. "…"
      total = width
    else
      result.first, result.last = 1, 0
      total = fixed
    end
  end
  result.overflow = total > width
  return result
end

local function build(win, info, current_symbols, active, status)
  local style = active and compiled.active or compiled.inactive
  local status_width = (status.modified and compiled.modified_width or 0)
    + (status.readonly and compiled.readonly_width or 0)
  local fit = layout(info, current_symbols, status_width, vim.api.nvim_win_get_width(win))

  local parts = { style.left }
  if fit.overflow then
    parts[#parts + 1] = "%<"
  end
  parts[#parts + 1] = click_start(1)
  if info.icon then
    parts[#parts + 1] = component(info.icon, style.highlight(info.icon_highlight))
  end
  if fit.dir ~= "" then
    parts[#parts + 1] = component(fit.dir, style.highlight("ZedBarDir"))
  end
  parts[#parts + 1] = component(info.file, style.highlight("ZedBarFile"))
  parts[#parts + 1] = "%X"
  if status.modified and style.modified then
    parts[#parts + 1] = style.modified
  end
  if status.readonly and style.readonly then
    parts[#parts + 1] = style.readonly
  end

  -- Display columns where each level starts, to anchor the menu under it.
  local column = config.options.padding.left
  local columns = { [0] = column }
  column = column
    + info.icon_width
    + strwidth(fit.dir)
    + info.file_width
    + status_width
    + compiled.separator_width
  if fit.first > 1 then
    parts[#parts + 1] = style.separator
    parts[#parts + 1] = click_start(fit.first)
    parts[#parts + 1] = style.ellipsis
    parts[#parts + 1] = "%X"
    for index = 1, fit.first - 1 do
      columns[index] = column
    end
    column = column + 1 + compiled.separator_width
  end
  for index = fit.first, fit.last do
    local symbol = current_symbols[index]
    local kind = symbols.kind(symbol)
    local name = index == fit.last and fit.last_name or symbol.name
    columns[index] = column
    column = column + kind_icon_width(kind) + strwidth(name) + compiled.separator_width
    parts[#parts + 1] = style.separator
    parts[#parts + 1] = click_start(index + 1)
    parts[#parts + 1] = kind_prefix(style, kind)
    parts[#parts + 1] = statusline_escape(name)
    parts[#parts + 1] = "%*%X"
  end
  parts[#parts + 1] = style.right
  return table.concat(parts), columns
end

local function render(win, path_only)
  if win == 0 then
    win = vim.api.nvim_get_current_win()
  end
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if not is_enabled(buf, win) then
    render_cache[win] = nil
    shown[win] = nil
    return set_winbar(win, "")
  end

  local name = vim.api.nvim_buf_get_name(buf)
  local active = is_active(win)
  local status = {
    modified = vim.api.nvim_get_option_value("modified", { buf = buf }),
    readonly = vim.api.nvim_get_option_value("readonly", { buf = buf }),
  }
  local info = get_path(buf, name)
  if path_only then
    local value, columns = build(win, info, {}, active, status)
    render_cache[win] = nil
    shown[win] = { buf = buf, info = info, symbols = {}, columns = columns }
    return set_winbar(win, value)
  end

  local state = cache[buf]
  local cursor = vim.api.nvim_win_get_cursor(win)
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
  local current_mode = vim.api.nvim_get_mode().mode
  local current_winbar = get_winbar(win)
  local width = vim.api.nvim_win_get_width(win)
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
    and previous_render.width == width
    and previous_render.active == active
    and previous_render.modified == status.modified
    and previous_render.readonly == status.readonly
    and previous_render.value == current_winbar
  then
    return false
  end

  local detail = config.options.detail
  local function lsp_symbols()
    if not lsp_symbols_table or not lsp_symbols_table[1] then
      return {}
    end
    local path = symbols.path(
      lsp_symbols_table,
      position(buf, cursor, state.encoding),
      config.options.max_depth
    )
    return detail == "scope" and symbols.scope(path) or path
  end

  local source_names = config.options.sources
  if type(source_names) == "function" then
    source_names = source_names(buf, win)
  end
  local current_symbols, source = sources.get_symbols(source_names, {
    buf = buf,
    win = win,
    cursor = cursor,
    max_depth = config.options.max_depth,
    detail = detail,
    lsp_symbols = lsp_symbols,
  })

  local value, columns = build(win, info, current_symbols, active, status)
  shown[win] = {
    buf = buf,
    info = info,
    source = source,
    symbols = current_symbols,
    columns = columns,
  }
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
    current_render.width = width
    current_render.active = active
    current_render.modified = status.modified
    current_render.readonly = status.readonly
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

local function render_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    render(win)
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

-- Navigation ----------------------------------------------------------------------------------

-- LSP positions count characters in the client's encoding; the cursor counts bytes.
local function lsp_start(buf, encoding, range)
  local row = range.start.line
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if not line then
    return row, 0
  end
  local ok, col = pcall(vim.str_byteindex, line, encoding or "utf-16", range.start.character, false)
  return row, ok and col or 0
end

local function lsp_entries(buf, encoding, nodes)
  local entries = {}
  for index, node in ipairs(nodes) do
    local row, col = lsp_start(buf, encoding, node.range)
    entries[index] =
      { name = node.name, kind = symbols.kind(node), row = row, col = col, node = node }
    if node.children[1] then
      entries[index].children = function()
        return lsp_entries(buf, encoding, node.children)
      end
    end
  end
  return entries
end

local function symbol_start(view, symbol)
  if view.source == "lsp" then
    local state = cache[view.buf]
    return lsp_start(view.buf, state and state.encoding, symbol.range)
  end
  return symbol.row or 0, symbol.col or 0
end

-- The menu levels along the breadcrumb: the siblings of each shown symbol, from the top level
-- down. Tree-sitter has no sibling outline, so its breadcrumb becomes a single list of scopes.
local function menu_levels(win, view)
  local path = view.symbols
  local roots, matches
  if view.source == "lsp" and cache[view.buf] then
    roots = lsp_entries(view.buf, cache[view.buf].encoding, cache[view.buf].symbols)
    matches = function(entry, symbol)
      return entry.node == symbol
    end
  elseif view.source == "markdown" then
    roots = sources.markdown.tree(view.buf)
    matches = function(entry, symbol)
      return entry.row == symbol.row
    end
  else
    if not path[1] then
      return
    end
    local entries = {}
    for index, symbol in ipairs(path) do
      local row, col = symbol_start(view, symbol)
      entries[index] = { name = symbol.name, kind = symbols.kind(symbol), row = row, col = col }
    end
    return { { entries = entries, selected = #entries, title = view.info.file } }
  end
  if not roots[1] then
    return
  end

  local levels = {}
  local entries, title, parent = roots, view.info.file, nil
  for depth, symbol in ipairs(path) do
    local selected
    for index, entry in ipairs(entries) do
      if matches(entry, symbol) then
        selected = index
        break
      end
    end
    if not selected then
      break
    end
    levels[depth] = { entries = entries, selected = selected, title = title, parent = parent }
    parent = entries[selected]
    title = parent.name
    entries = menu.children(parent)
    if not entries then
      break
    end
  end
  if not levels[1] then
    -- Between symbols: select the last top-level symbol above the cursor.
    local row = vim.api.nvim_win_get_cursor(win)[1] - 1
    local selected = 1
    for index, entry in ipairs(roots) do
      if entry.row <= row then
        selected = index
      end
    end
    levels[1] = { entries = roots, selected = selected, title = view.info.file }
  end
  return levels
end

local function jump(win, row, col)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.api.nvim_set_current_win(win)
  vim.cmd("normal! m'")
  local buf = vim.api.nvim_win_get_buf(win)
  vim.api.nvim_win_set_cursor(win, { math.min(row + 1, vim.api.nvim_buf_line_count(buf)), col })
  vim.cmd("normal! zv")
  render(win)
end

-- Renders `win` now so navigation works from the cursor even before a debounced render ran.
local function current_view(win)
  win = win or vim.api.nvim_get_current_win()
  render(win)
  return win, shown[win]
end

local function open_menu(win, view, level, from_click)
  local levels = view and menu_levels(win, view)
  if not levels then
    vim.notify("zed-bar: no symbols to navigate", vim.log.levels.INFO)
    return
  end
  level = math.max(1, math.min(level or #levels, #levels))
  menu.open({
    win = win,
    levels = levels,
    level = level,
    column = function(index)
      return view.columns[index] or view.columns[#view.columns] or view.columns[0]
    end,
    icon = kind_icon,
    from_click = from_click,
    on_choose = function(entry)
      jump(win, entry.row, entry.col)
    end,
  })
end

function M._click(id, _, button)
  if button ~= "l" then
    return
  end
  local win = vim.fn.getmousepos().winid
  if not shown[win] then
    win = vim.api.nvim_get_current_win()
  end
  local view = shown[win]
  if not view then
    return
  end
  local index = id - 1
  local symbol = view.symbols[index]
  if symbol and view.source ~= "lsp" and view.source ~= "markdown" then
    jump(win, symbol_start(view, symbol))
    return
  end
  open_menu(win, view, math.max(index, 1), true)
end

function M.pick(win)
  local view
  win, view = current_view(win)
  open_menu(win, view)
end

function M.parent(win)
  local view
  win, view = current_view(win)
  if not view then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local cursor_row, cursor_col = cursor[1] - 1, cursor[2]
  for index = #view.symbols, 1, -1 do
    local row, col = symbol_start(view, view.symbols[index])
    if row < cursor_row or (row == cursor_row and col < cursor_col) then
      jump(win, row, col)
      return
    end
  end
end

function M.yank(win)
  local view
  win, view = current_view(win)
  if not view then
    return
  end
  local parts = { view.info.value }
  for _, symbol in ipairs(view.symbols) do
    parts[#parts + 1] = symbol.name
  end
  local text = table.concat(parts, config.options.separator)
  vim.fn.setreg(vim.v.register, text)
  vim.notify("zed-bar: copied " .. text, vim.log.levels.INFO)
end

function M.toggle()
  hidden = not hidden
  render_cache = {}
  render_all()
end

function M.info(win)
  local view
  win, view = current_view(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local source_names = config.options.sources
  if type(source_names) == "function" then
    source_names = source_names(buf, win)
  end
  local state = cache[buf]
  local client = supporting_client(buf)
  local lines = {
    "zed-bar",
    "  enabled: " .. tostring(is_enabled(buf, win)),
    "  sources: " .. table.concat(source_names, " → "),
    "  shown from: " .. (view and view.source or "none"),
    "  detail: " .. config.options.detail,
    "  LSP: " .. (client and (client.name or "client") or "no documentSymbol client"),
  }
  if state then
    lines[#lines + 1] = "  LSP symbols: "
      .. #state.symbols
      .. " top-level"
      .. (state.request_id and " (request pending)" or "")
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
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
  devicons = nil
  active_win = vim.api.nvim_get_current_win()

  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd("BufReadPre", {
    group = group,
    callback = function(args)
      render_buffer(args.buf, true)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufNewFile", "BufEnter", "BufModifiedSet" }, {
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
      local win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_config(win).relative == "" and active_win ~= win then
        local previous = active_win
        active_win = win
        if previous then
          render(previous)
        end
      end
      render(win)
      if supporting_client(args.buf) and not cache[args.buf] then
        request_symbols(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      for _, win in ipairs(vim.v.event.windows or {}) do
        render(win)
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
        shown[win] = nil
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
      render_all()
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
