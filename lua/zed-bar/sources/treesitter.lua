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

local function kind(node_type)
  for _, item in ipairs(type_kinds) do
    if node_type:find(item[1], 1, true) then
      return item[2]
    end
  end
end

local function node_text(node, buf)
  if not node then
    return ""
  end
  local ok, text = pcall(vim.treesitter.get_node_text, node, buf)
  if not ok or type(text) ~= "string" then
    return ""
  end
  return vim.trim(text:gsub("%s+", " "))
end

local function short_name(node, buf)
  for _, field in ipairs({ "name", "declarator", "key", "field", "tag_name" }) do
    local child = node:field(field)[1]
    local text = node_text(child, buf)
    if text ~= "" then
      return vim.fn.strcharpart(text, 0, 60)
    end
  end

  local text = node_text(node, buf)
  return vim.fn.strcharpart(text, 0, 60)
end

function M.get_symbols(buf, _, cursor, max_depth)
  local ok = pcall(vim.treesitter.get_parser, buf)
  if not ok then
    return {}
  end

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
      local name = short_name(node, buf)
      local previous = result[1]
      if name ~= "" and (not previous or previous.name ~= name or previous.kind ~= node_kind) then
        table.insert(result, 1, { name = name, kind = node_kind })
      end
    end
    node = node:parent()
  end
  return result
end

function M.invalidate() end

M._kind = kind

return M
