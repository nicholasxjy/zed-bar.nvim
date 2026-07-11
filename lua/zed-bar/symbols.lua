local kinds = require("zed-bar.kinds")

local M = {}

local function before(a, b)
  return a.line < b.line or (a.line == b.line and a.character < b.character)
end

local function position_in_range(position, range)
  return not before(position, range.start) and not before(range["end"], position)
end

local function range_contains(outer, inner)
  local contains = not before(inner.start, outer.start) and not before(outer["end"], inner["end"])
  local equal = not before(outer.start, inner.start)
    and not before(inner.start, outer.start)
    and not before(outer["end"], inner["end"])
    and not before(inner["end"], outer["end"])
  return contains and not equal
end

local function normalize_document_symbol(symbol)
  local normalized = {
    name = symbol.name,
    kind = symbol.kind,
    range = symbol.range,
    children = {},
  }

  for _, child in ipairs(symbol.children or {}) do
    if child.range then
      table.insert(normalized.children, normalize_document_symbol(child))
    end
  end

  return normalized
end

local function sort_tree(tree)
  table.sort(tree, function(a, b)
    return before(a.range.start, b.range.start)
  end)
  for _, symbol in ipairs(tree) do
    sort_tree(symbol.children)
  end
  return tree
end

local function normalize_symbol_information(symbols)
  local flat = {}
  for _, symbol in ipairs(symbols) do
    if symbol.location and symbol.location.range then
      table.insert(flat, {
        name = symbol.name,
        kind = symbol.kind,
        range = symbol.location.range,
        children = {},
      })
    end
  end

  table.sort(flat, function(a, b)
    if before(a.range.start, b.range.start) then
      return true
    end
    if before(b.range.start, a.range.start) then
      return false
    end
    return before(b.range["end"], a.range["end"])
  end)

  local roots, stack = {}, {}
  for _, symbol in ipairs(flat) do
    while stack[#stack] and not range_contains(stack[#stack].range, symbol.range) do
      table.remove(stack)
    end
    if stack[#stack] then
      table.insert(stack[#stack].children, symbol)
    else
      table.insert(roots, symbol)
    end
    table.insert(stack, symbol)
  end
  return roots
end

function M.normalize(symbols)
  if not symbols or not symbols[1] then
    return {}
  end
  if symbols[1].location then
    return normalize_symbol_information(symbols)
  end

  local result = {}
  for _, symbol in ipairs(symbols) do
    if symbol.range then
      table.insert(result, normalize_document_symbol(symbol))
    end
  end
  return sort_tree(result)
end

local function find_path(symbols, position, path, max_depth)
  if #path >= max_depth then
    return
  end

  for index = #symbols, 1, -1 do
    local symbol = symbols[index]
    if position_in_range(position, symbol.range) then
      table.insert(path, symbol)
      find_path(symbol.children, position, path, max_depth)
      return
    end
  end
end

function M.path(symbols, position, max_depth)
  local result = {}
  find_path(symbols, position, result, max_depth or math.huge)
  return result
end

function M.kind(symbol)
  if type(symbol.kind) == "string" then
    return symbol.kind
  end
  return kinds.names[symbol.kind] or "Object"
end

return M
