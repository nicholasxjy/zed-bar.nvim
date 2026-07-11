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

local name_pattern = [[[#~!@*&.]*\k\+!\?\%\(\%\(\s\+\|:\+\|->\|-\+\|\.\+\)[#~!@*&.]*\k\+!\?\)*]]
local name_regex = vim.regex(name_pattern)

local function truncate(name)
  return #name <= 60 and name or vim.fn.strcharpart(name, 0, 60)
end

local function extract_name(text)
  local start, finish = name_regex:match_str(text)
  if not start then
    return ""
  end
  local name = text:sub(start + 1, finish)
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

function M.get_symbols(buf, _, cursor, max_depth)
  local column = cursor[2]
  if column > 0 and vim.fn.mode():find("i", 1, true) then
    column = column - 1
  end
  local node = vim.F.npcall(vim.treesitter.get_node, {
    bufnr = buf,
    pos = { cursor[1] - 1, column },
  })

  local result = {}
  while node and #result < max_depth do
    local node_kind = kind(node:type())
    if node_kind then
      local name = short_name(node, buf, node_kind)
      local previous = result[#result]
      if name ~= "" and (not previous or canonical_name(previous.name) ~= canonical_name(name)) then
        result[#result + 1] = { name = name, kind = node_kind }
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

function M.invalidate() end

M._kind = kind
M._extract_name = extract_name
M._canonical_name = canonical_name

return M
