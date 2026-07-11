local M = {}

M.names = {
  [1] = "File",
  [2] = "Module",
  [3] = "Namespace",
  [4] = "Package",
  [5] = "Class",
  [6] = "Method",
  [7] = "Property",
  [8] = "Field",
  [9] = "Constructor",
  [10] = "Enum",
  [11] = "Interface",
  [12] = "Function",
  [13] = "Variable",
  [14] = "Constant",
  [15] = "String",
  [16] = "Number",
  [17] = "Boolean",
  [18] = "Array",
  [19] = "Object",
  [20] = "Keyword",
  [21] = "Null",
  [22] = "EnumMember",
  [23] = "Struct",
  [24] = "Event",
  [25] = "Operator",
  [26] = "TypeParameter",
}

M.icons = {
  File = "󰈔 ",
  Module = "󰏗 ",
  Namespace = "󰅩 ",
  Package = "󰆦 ",
  Class = " ",
  Method = "󰆧 ",
  Property = " ",
  Field = " ",
  Constructor = " ",
  Enum = " ",
  Interface = " ",
  Function = "󰊕 ",
  Variable = "󰀫 ",
  Constant = "󰏿 ",
  String = "󰉾 ",
  Number = "󰎠 ",
  Boolean = " ",
  Array = "󰅪 ",
  Object = "󰅩 ",
  Keyword = "󰌋 ",
  Null = "󰢤 ",
  EnumMember = " ",
  Struct = " ",
  Event = " ",
  Operator = "󰆕 ",
  TypeParameter = "󰆩 ",
}

local links = {
  File = "Directory",
  Module = "Include",
  Namespace = "Include",
  Package = "Include",
  Class = "Type",
  Method = "Function",
  Property = "Identifier",
  Field = "Identifier",
  Constructor = "Function",
  Enum = "Type",
  Interface = "Type",
  Function = "Function",
  Variable = "Identifier",
  Constant = "Constant",
  String = "String",
  Number = "Number",
  Boolean = "Boolean",
  Array = "Type",
  Object = "Type",
  Keyword = "Keyword",
  Null = "Constant",
  EnumMember = "Constant",
  Struct = "Type",
  Event = "Special",
  Operator = "Operator",
  TypeParameter = "Type",
}

function M.setup_highlights()
  vim.api.nvim_set_hl(0, "ZedBarNormal", { default = true, link = "WinBar" })
  vim.api.nvim_set_hl(0, "ZedBarFile", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "ZedBarSeparator", { default = true, link = "Comment" })

  for _, kind in pairs(M.names) do
    local link = links[kind] or "Normal"
    vim.api.nvim_set_hl(0, "ZedBarKind" .. kind, { default = true, link = link })
    vim.api.nvim_set_hl(0, "ZedBarIconKind" .. kind, { default = true, link = link })
  end
end

return M
