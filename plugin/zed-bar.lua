if vim.g.loaded_zed_bar then
  return
end
vim.g.loaded_zed_bar = true

vim.api.nvim_create_user_command("ZedBarRefresh", function()
  require("zed-bar").refresh()
end, { desc = "Refresh zed-bar symbols" })

local subcommands = { "info", "parent", "pick", "refresh", "toggle", "yank" }

vim.api.nvim_create_user_command("ZedBar", function(args)
  local name = args.fargs[1]
  if not vim.tbl_contains(subcommands, name) then
    vim.notify(("zed-bar: unknown subcommand %q"):format(name), vim.log.levels.ERROR)
    return
  end
  require("zed-bar")[name]()
end, {
  nargs = 1,
  complete = function(arglead)
    return vim.tbl_filter(function(name)
      return vim.startswith(name, arglead)
    end, subcommands)
  end,
  desc = "zed-bar: " .. table.concat(subcommands, ", "),
})
