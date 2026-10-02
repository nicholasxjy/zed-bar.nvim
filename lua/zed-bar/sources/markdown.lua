local M = {}

local cache = {}
local attached = {}

-- Parser state is saved every `checkpoint_interval` lines so an edit only re-parses from the
-- nearest checkpoint above the first changed line instead of from the top of the buffer.
local checkpoint_interval = 128

local function new_state(changedtick)
  return {
    changedtick = changedtick,
    checkpoints = {},
    dirty_from = nil,
    fence = nil,
    fence_length = 0,
    headings = {},
    parsed_to = 0,
    previous_line = nil,
    previous_is_heading = false,
  }
end

local function rollback(current, line)
  local index = math.floor(line / checkpoint_interval)
  while index > 0 and not current.checkpoints[index] do
    index = index - 1
  end
  local checkpoint = current.checkpoints[index]
  if not checkpoint then
    return false
  end
  for stale = #current.checkpoints, index + 1, -1 do
    current.checkpoints[stale] = nil
  end
  for stale = #current.headings, checkpoint.heading_count + 1, -1 do
    current.headings[stale] = nil
  end
  current.fence = checkpoint.fence
  current.fence_length = checkpoint.fence_length
  current.parsed_to = index * checkpoint_interval
  current.previous_line = checkpoint.previous_line
  current.previous_is_heading = checkpoint.previous_is_heading
  return true
end

local function attach(buf)
  if attached[buf] then
    return
  end
  attached[buf] = vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, first_line)
      local current = cache[buf]
      if not current then
        attached[buf] = nil
        return true
      end
      if not current.dirty_from or first_line < current.dirty_from then
        current.dirty_from = first_line
      end
    end,
    on_reload = function()
      cache[buf] = nil
    end,
    on_detach = function()
      attached[buf] = nil
      cache[buf] = nil
    end,
  }) or nil
end

local function state(buf)
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  local current = cache[buf]
  if current and current.changedtick ~= changedtick then
    local dirty_from = current.dirty_from
    current.dirty_from = nil
    current.changedtick = changedtick
    if dirty_from and dirty_from >= current.parsed_to then
      -- Only lines that have not been parsed yet changed.
      return current
    end
    if not dirty_from or not rollback(current, dirty_from) then
      current = nil
    end
  end
  if not current then
    current = new_state(changedtick)
    cache[buf] = current
    attach(buf)
  end
  return current
end

local function parse_line(current, line, line_number)
  if line_number % checkpoint_interval == 0 then
    current.checkpoints[line_number / checkpoint_interval] = {
      fence = current.fence,
      fence_length = current.fence_length,
      heading_count = #current.headings,
      previous_line = current.previous_line,
      previous_is_heading = current.previous_is_heading,
    }
  end

  local is_heading = false
  local marker, rest = line:match("^%s*(```+)(.*)$")
  if not marker then
    marker, rest = line:match("^%s*(~~~+)(.*)$")
  end
  if current.fence then
    -- Only a run of the same fence character, at least as long and without an info string,
    -- closes the block.
    if
      marker
      and marker:sub(1, 1) == current.fence
      and #marker >= current.fence_length
      and not rest:find("%S")
    then
      current.fence = nil
    end
  elseif marker then
    current.fence = marker:sub(1, 1)
    current.fence_length = #marker
  else
    local hashes, name = line:match("^%s*(#+)%s+(.+)$")
    if hashes and #hashes <= 6 then
      name = vim.trim(name:gsub("%s+#+%s*$", ""))
      if name ~= "" then
        local headings = current.headings
        headings[#headings + 1] = { name = name, level = #hashes, line = line_number }
        is_heading = true
      end
    elseif
      current.previous_line
      and not current.previous_is_heading
      and line:match("^%s*[=-]+%s*$")
    then
      local previous = vim.trim(current.previous_line)
      if previous ~= "" then
        local headings = current.headings
        headings[#headings + 1] = {
          name = previous,
          level = line:find("=", 1, true) and 1 or 2,
          line = line_number - 1,
        }
        is_heading = true
      end
    end
  end
  current.previous_line = line
  current.previous_is_heading = is_heading
end

local function parse_to(buf, line_end)
  local current = state(buf)
  if current.parsed_to >= line_end then
    return current
  end

  local first_line = current.parsed_to
  local lines = vim.api.nvim_buf_get_lines(buf, first_line, line_end, false)
  for index, line in ipairs(lines) do
    parse_line(current, line, first_line + index - 1)
  end

  current.parsed_to = first_line + #lines
  return current
end

-- Index of the last heading at or above `line` (headings are stored in line order).
local function last_heading_at(headings, line)
  local low, high, candidate = 1, #headings, 0
  while low <= high do
    local middle = math.floor((low + high) / 2)
    if headings[middle].line <= line then
      candidate = middle
      low = middle + 1
    else
      high = middle - 1
    end
  end
  return candidate
end

function M.get_symbols(buf, _, cursor, max_depth)
  if vim.api.nvim_get_option_value("filetype", { buf = buf }) ~= "markdown" then
    return {}
  end

  local line_end = math.min(vim.api.nvim_buf_line_count(buf), cursor[1] + 200)
  local current = parse_to(buf, line_end)
  local headings = current.headings

  local reversed = {}
  local current_level = 7
  for index = last_heading_at(headings, cursor[1] - 1), 1, -1 do
    local heading = headings[index]
    if heading.level < current_level then
      reversed[#reversed + 1] = heading
      current_level = heading.level
      if current_level == 1 or #reversed >= max_depth then
        break
      end
    end
  end

  local result = {}
  for index = #reversed, 1, -1 do
    local heading = reversed[index]
    result[#result + 1] = { name = heading.name, kind = "MarkdownH" .. heading.level }
  end
  return result
end

function M.invalidate(buf)
  cache[buf] = nil
end

return M
