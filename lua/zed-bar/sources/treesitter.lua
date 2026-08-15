local M = {}

local type_kinds = {
  { "method", "Method" },
  { "constructor", "Constructor" },
  { "function", "Function" },
  { "call", "Call" },
  { "class", "Class" },
  { "struct", "Struct" },
  { "interface", "Interface" },
  { "enum_member", "EnumMember" },
  { "enum", "Enum" },
  { "namespace", "Namespace" },
  { "module", "Module" },
  { "macro", "Macro" },
  { "type", "Type" },
  { "constant", "Constant" },
  { "variable", "Variable" },
  { "lexical_declaration", "Declaration" },
  { "declaration", "Declaration" },
  { "property", "Property" },
  { "field", "Field" },
  { "identifier", "Identifier" },
  { "if_", "IfStatement" },
  { "for_", "ForStatement" },
  { "while_", "WhileStatement" },
  { "do_", "DoStatement" },
  { "switch_", "SwitchStatement" },
  { "case_", "CaseStatement" },
  { "return_", "ReturnStatement" },
  { "repeat", "Repeat" },
  { "jsx_element", "Element" },
  { "element", "Element" },
  { "mapping_pair", "BlockMappingPair" },
  { "pair", "Pair" },
  { "table", "Table" },
  { "list", "List" },
  { "section", "Section" },
  { "rule_set", "RuleSet" },
  { "rule", "Rule" },
  { "scope", "Scope" },
  { "reference", "Reference" },
  { "specifier", "Specifier" },
  { "statement", "Statement" },
}

local kind_cache = {}
local no_kind = {}

local function kind(node_type)
  local cached = kind_cache[node_type]
  if cached then
    return cached ~= no_kind and cached or nil
  end
  for _, item in ipairs(type_kinds) do
    if node_type:find(item[1], 1, true) then
      kind_cache[node_type] = item[2]
      return item[2]
    end
  end
  kind_cache[node_type] = no_kind
end

local function node_text(node, buf)
  if not node then
    return ""
  end
  local text = vim.treesitter.get_node_text(node, buf)
  if not text:find("%s") then
    return text
  end
  return vim.trim(text:gsub("%s+", " "))
end

local function truncate(name)
  return #name <= 60 and name or vim.fn.strcharpart(name, 0, 60)
end

local function is_identifier_byte(byte)
  return (byte >= 48 and byte <= 57)
    or (byte >= 65 and byte <= 90)
    or (byte >= 97 and byte <= 122)
    or byte == 95
    or byte >= 128
end

local function is_name_prefix_byte(byte)
  return byte == 35 or byte == 126 or byte == 33 or byte == 64
    or byte == 42 or byte == 38 or byte == 46
end

local function separator_end(text, index)
  local length = #text
  if index > length then
    return nil
  end

  local byte = text:byte(index)
  if byte == 32 or (byte >= 9 and byte <= 13) then
    repeat
      index = index + 1
    until index > length
      or not (text:byte(index) == 32 or (text:byte(index) >= 9 and text:byte(index) <= 13))
    return index
  end
  if byte == 58 then
    repeat
      index = index + 1
    until index > length or text:byte(index) ~= 58
    return index
  end
  if byte == 45 then
    if index + 1 <= length and text:byte(index + 1) == 62 then
      return index + 2
    end
    repeat
      index = index + 1
    until index > length or text:byte(index) ~= 45
    return index
  end
  if byte == 46 then
    repeat
      index = index + 1
    until index > length or text:byte(index) ~= 46
    return index
  end
end

local function extract_name(text)
  local length = #text
  local index = 1
  while index <= length and not is_identifier_byte(text:byte(index)) do
    index = index + 1
  end
  if index > length then
    return ""
  end

  local start = index
  while start > 1 and is_name_prefix_byte(text:byte(start - 1)) do
    start = start - 1
  end

  local finish = index
  while true do
    repeat
      index = index + 1
    until index > length or not is_identifier_byte(text:byte(index))
    if index <= length and text:byte(index) == 33 then
      index = index + 1
    end
    finish = index

    local candidate = separator_end(text, index)
    if not candidate then
      break
    end
    while candidate <= length and is_name_prefix_byte(text:byte(candidate)) do
      candidate = candidate + 1
    end
    if candidate > length or not is_identifier_byte(text:byte(candidate)) then
      break
    end
    index = candidate
  end

  local name = text:sub(start, finish - 1)
  return truncate(name)
end

local declaration_keywords = {
  ["const"] = true,
  ["declare"] = true,
  ["default"] = true,
  ["export"] = true,
  ["final"] = true,
  ["let"] = true,
  ["local"] = true,
  ["mut"] = true,
  ["private"] = true,
  ["protected"] = true,
  ["public"] = true,
  ["readonly"] = true,
  ["static"] = true,
  ["var"] = true,
}

local function canonical_name(name)
  while true do
    local first, rest = name:match("^(%S+)%s+(.+)$")
    if not first or not declaration_keywords[first] then
      return name
    end
    name = rest
  end
end

local name_fields = { "name", "declarator", "key", "field", "tag_name" }
local kinds_with_name_fields = {
  BlockMappingPair = true,
  Class = true,
  Constructor = true,
  Declaration = true,
  Element = true,
  Enum = true,
  EnumMember = true,
  Field = true,
  Function = true,
  Interface = true,
  Method = true,
  Module = true,
  Namespace = true,
  Pair = true,
  Property = true,
  Struct = true,
  Type = true,
  Variable = true,
}

local function short_name(node, buf, node_kind)
  if node_kind == "Identifier" then
    return truncate(node_text(node, buf))
  end
  if kinds_with_name_fields[node_kind] then
    for _, field in ipairs(name_fields) do
      local child = node:field(field)[1]
      local name = extract_name(node_text(child, buf))
      if name ~= "" then
        return name
      end
    end
  end

  return extract_name(node_text(node, buf))
end

local function symbols_from_node(node, buf, max_depth, matched_nodes)
  local result = {}
  local previous_canonical
  while node and #result < max_depth do
    local node_kind = kind(node:type())
    if node_kind and (not matched_nodes or matched_nodes[node:id()]) then
      local name = short_name(node, buf, node_kind)
      if name ~= "" then
        local canonical = canonical_name(name)
        if not previous_canonical or previous_canonical ~= canonical then
          result[#result + 1] = { name = name, kind = node_kind }
          previous_canonical = canonical
        end
      end
    end
    node = node:parent()
  end
  for index = 1, math.floor(#result / 2) do
    local reverse_index = #result - index + 1
    result[index], result[reverse_index] = result[reverse_index], result[index]
  end
  return result
end

local no_nvim_treesitter = {}
local nvim_treesitter = no_nvim_treesitter
local nvim_treesitter_name
local checked_nvim_treesitter = false

local function get_nvim_treesitter()
  local ts_utils_name = "nvim-treesitter.ts_utils"
  local plugin_name = "nvim-treesitter"
  if nvim_treesitter ~= no_nvim_treesitter then
    local ts_utils_available = package.loaded[ts_utils_name] or package.preload[ts_utils_name]
    if
      (nvim_treesitter_name == plugin_name and ts_utils_available)
      or package.loaded[nvim_treesitter_name] ~= nvim_treesitter
    then
      nvim_treesitter = no_nvim_treesitter
      nvim_treesitter_name = nil
    else
      return nvim_treesitter
    end
  end
  if
    checked_nvim_treesitter
    and not package.loaded[ts_utils_name]
    and not package.preload[ts_utils_name]
    and not package.loaded[plugin_name]
    and not package.preload[plugin_name]
  then
    return
  end
  checked_nvim_treesitter = true
  local ok, ts_utils = pcall(require, ts_utils_name)
  if ok then
    nvim_treesitter = ts_utils
    nvim_treesitter_name = ts_utils_name
    return ts_utils
  end
  local ok_plugin, nvim_treesitter_module = pcall(require, plugin_name)
  if ok_plugin then
    nvim_treesitter = nvim_treesitter_module
    nvim_treesitter_name = plugin_name
    return nvim_treesitter_module
  end
  nvim_treesitter = no_nvim_treesitter
end

local function node_at_cursor(buf, win, cursor, ts_utils)
  if type(ts_utils) == "table" then
    local get_node_at_cursor = ts_utils.get_node_at_cursor
    if type(get_node_at_cursor) == "function" then
      local window = win or 0
      local ok_buf, window_buf = pcall(vim.api.nvim_win_get_buf, window)
      local ok_cursor, window_cursor = pcall(vim.api.nvim_win_get_cursor, window)
      local same_context = ok_buf
        and ok_cursor
        and window_buf == buf
        and window_cursor[1] == cursor[1]
        and window_cursor[2] == cursor[2]
      if same_context then
        local node = vim.F.npcall(get_node_at_cursor, window)
        if node then
          return node
        end
      end

      local get_root_for_position = ts_utils.get_root_for_position
      if type(get_root_for_position) ~= "function" then
        local node = vim.F.npcall(get_node_at_cursor, window)
        if node then
          return node
        end
      else
        local ok, parsers = pcall(require, "nvim-treesitter.parsers")
        if ok then
          local parser = vim.F.npcall(parsers.get_parser, buf)
          local row, column = cursor[1] - 1, cursor[2]
          local root = parser and vim.F.npcall(get_root_for_position, row, column, parser)
          if root and type(root.named_descendant_for_range) == "function" then
            return vim.F.npcall(root.named_descendant_for_range, root, row, column, row, column)
          end
        end
      end
    end
  end

  return vim.F.npcall(vim.treesitter.get_node, {
    bufnr = buf,
    pos = { cursor[1] - 1, cursor[2] },
  })
end

local function query_nodes(buf, cursor, ts_utils)
  if not ts_utils then
    return
  end

  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return
  end
  local ok_lang, lang = pcall(parser.lang, parser)
  local ok_query, query = pcall(vim.treesitter.query.get, lang, "locals")
  if not ok_lang or not ok_query or not query then
    return
  end

  local ok_nodes, matched_nodes = pcall(function()
    local trees = parser:parse()
    local root = trees[1] and trees[1]:root()
    if not root then
      return
    end

    local row, column = cursor[1] - 1, cursor[2]
    local nodes = {}
    for capture_id, node in query:iter_captures(root, buf, row, row + 1) do
      if query.captures[capture_id] == "local.scope" then
        local start_row, start_column, end_row, end_column = node:range()
        if (start_row < row or (start_row == row and start_column <= column))
          and (row < end_row or (row == end_row and column <= end_column))
        then
          nodes[node:id()] = true
        end
      end
    end
    return next(nodes) and nodes or nil
  end)
  return ok_nodes and matched_nodes or nil
end

function M.get_symbols(buf, win, cursor, max_depth)
  local column = cursor[2]
  if column > 0 and vim.api.nvim_get_mode().mode:find("i", 1, true) then
    column = column - 1
  end
  local ts_utils = get_nvim_treesitter()
  local position = { cursor[1], column }
  local matched_nodes = query_nodes(buf, position, ts_utils)
  local node = node_at_cursor(buf, win, position, ts_utils)
  local result = symbols_from_node(node, buf, max_depth, matched_nodes)
  if result[1] or not matched_nodes then
    return result
  end
  return symbols_from_node(node, buf, max_depth)
end

function M.invalidate() end

M._kind = kind
M._extract_name = extract_name
M._canonical_name = canonical_name

return M
