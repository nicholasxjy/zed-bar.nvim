local M = {}

local cache = {}

local function state(buf)
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  if not cache[buf] or cache[buf].changedtick ~= changedtick then
    cache[buf] = {
      changedtick = changedtick,
      fence = nil,
      headings = {},
      parsed_to = 0,
      previous_line = nil,
      previous_is_heading = false,
    }
  end
  return cache[buf]
end

local function parse_to(buf, line_end)
  local current = state(buf)
  if current.parsed_to >= line_end then
    return current
  end

  local lines = vim.api.nvim_buf_get_lines(buf, current.parsed_to, line_end, false)

  for index, line in ipairs(lines) do
    local line_number = current.parsed_to + index - 1
    local is_heading = false
    local marker = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if marker then
      if not current.fence then
        current.fence = marker:sub(1, 1)
      elseif marker:sub(1, 1) == current.fence then
        current.fence = nil
      end
    elseif not current.fence then
      local hashes, name = line:match("^%s*(#+)%s+(.+)$")
      if hashes and #hashes <= 6 then
        name = vim.trim(name:gsub("%s+#+%s*$", ""))
        if name ~= "" then
          table.insert(current.headings, { name = name, level = #hashes, line = line_number })
          is_heading = true
        end
      elseif
        current.previous_line
        and not current.previous_is_heading
        and line:match("^%s*[=-]+%s*$")
      then
        local previous = vim.trim(current.previous_line)
        if previous ~= "" then
          table.insert(current.headings, {
            name = previous,
            level = line:find("=", 1, true) and 1 or 2,
            line = line_number - 1,
          })
          is_heading = true
        end
      end
    end
    current.previous_line = line
    current.previous_is_heading = is_heading
  end

  current.parsed_to = current.parsed_to + #lines
  return current
end

function M.get_symbols(buf, _, cursor, max_depth)
  if vim.bo[buf].filetype ~= "markdown" then
    return {}
  end

  local line_end = math.min(vim.api.nvim_buf_line_count(buf), cursor[1] + 200)
  local current = parse_to(buf, line_end)

  local result = {}
  local current_level = 7
  for index = #current.headings, 1, -1 do
    local heading = current.headings[index]
    if heading.line <= cursor[1] - 1 and heading.level < current_level then
      table.insert(result, 1, {
        name = heading.name,
        kind = "MarkdownH" .. heading.level,
      })
      current_level = heading.level
      if current_level == 1 or #result >= max_depth then
        break
      end
    end
  end
  return result
end

function M.invalidate(buf)
  cache[buf] = nil
end

return M
