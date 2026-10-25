local M = {}

local namespace = vim.api.nvim_create_namespace("zed-bar-menu")

-- Entry children are either a list or a function that builds the list on demand.
function M.children(entry)
  local children = entry.children
  if type(children) == "function" then
    children = children()
  end
  return children and children[1] and children or nil
end

-- Opens a floating list of `opts.levels[opts.level].entries` under the winbar of `opts.win`.
-- `h`/`l` move between a level and the children of the selected entry, `<CR>` chooses it.
function M.open(opts)
  local win, levels = opts.win, opts.levels
  local index = opts.level
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local float

  local function dismiss()
    if float and vim.api.nvim_win_is_valid(float) then
      vim.api.nvim_win_close(float, true)
    end
    float = nil
  end

  local function close()
    dismiss()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end

  local function show()
    local level = levels[index]
    local lines, width = {}, vim.api.nvim_strwidth(level.title or "")
    for line, entry in ipairs(level.entries) do
      lines[line] = opts.icon(entry.kind) .. entry.name
      width = math.max(width, vim.api.nvim_strwidth(lines[line]))
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    for line, entry in ipairs(level.entries) do
      local icon_end = #opts.icon(entry.kind)
      vim.api.nvim_buf_set_extmark(buf, namespace, line - 1, 0, {
        end_col = icon_end,
        hl_group = "ZedBarIconKind" .. entry.kind,
      })
      vim.api.nvim_buf_set_extmark(buf, namespace, line - 1, icon_end, {
        end_col = #lines[line],
        hl_group = "ZedBarKind" .. entry.kind,
      })
    end

    local win_width = vim.api.nvim_win_get_width(win)
    local has_border = vim.o.winborder ~= "none"
    width = math.max(1, math.min(width, win_width - 2))
    local config = {
      relative = "win",
      win = win,
      -- Row 0 is the winbar itself.
      row = vim.wo[win].winbar ~= "" and 1 or 0,
      col = math.max(0, math.min(opts.column(index), win_width - width - 2)),
      width = width,
      height = math.max(1, math.min(#lines, vim.api.nvim_win_get_height(win) - 3)),
      border = vim.o.winborder == "" and "rounded" or nil,
      title = has_border and level.title or nil,
    }
    if float then
      vim.api.nvim_win_set_config(float, config)
    else
      config.style = "minimal"
      float = vim.api.nvim_open_win(buf, true, config)
      vim.wo[float].cursorline = true
    end
    vim.api.nvim_win_set_cursor(float, { level.selected, 0 })
  end

  local function selected()
    levels[index].selected = vim.api.nvim_win_get_cursor(float)[1]
    return levels[index].entries[levels[index].selected]
  end

  local function choose()
    local entry = selected()
    close()
    opts.on_choose(entry)
  end

  local function up()
    selected()
    if index > 1 then
      index = index - 1
      show()
    end
  end

  local function down()
    local entry = selected()
    local next_level = levels[index + 1]
    if not next_level or next_level.parent ~= entry then
      local children = M.children(entry)
      if not children then
        return
      end
      -- A different branch: forget the deeper levels of the previous one.
      for stale = #levels, index + 1, -1 do
        levels[stale] = nil
      end
      levels[index + 1] = { entries = children, selected = 1, title = entry.name, parent = entry }
    end
    index = index + 1
    show()
  end

  show()
  local function map(lhs, callback)
    vim.keymap.set("n", lhs, callback, { buffer = buf, nowait = true })
  end
  map("<CR>", choose)
  map("<2-LeftMouse>", choose)
  map("q", close)
  map("<Esc>", close)
  map("h", up)
  map("<Left>", up)
  map("l", down)
  map("<Right>", down)
  -- A winbar click opens the menu on the mouse press; the release then focuses the window
  -- under the winbar again.
  local awaiting_release = opts.from_click
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if not float or not vim.api.nvim_win_is_valid(float) then
          return
        end
        local mouse = vim.fn.getmousepos()
        if
          awaiting_release
          and vim.api.nvim_get_current_win() == win
          and mouse.winid == win
          and mouse.winrow == 1
        then
          awaiting_release = false
          vim.api.nvim_set_current_win(float)
          return
        end
        -- Focus moved elsewhere (a mouse click, a window command): leave it there.
        dismiss()
      end)
    end,
  })
end

return M
