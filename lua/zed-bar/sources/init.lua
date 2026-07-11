local M = {}

local builtins = {
  markdown = require("zed-bar.sources.markdown"),
  treesitter = require("zed-bar.sources.treesitter"),
}

function M.get_symbols(source_names, context)
  for _, name in ipairs(source_names) do
    local result
    if name == "lsp" then
      result = context.lsp_symbols
    elseif builtins[name] then
      result =
        builtins[name].get_symbols(context.buf, context.win, context.cursor, context.max_depth)
    end
    if result and result[1] then
      return result
    end
  end
  return {}
end

function M.invalidate(buf)
  for _, source in pairs(builtins) do
    source.invalidate(buf)
  end
end

M.markdown = builtins.markdown
M.treesitter = builtins.treesitter

return M
