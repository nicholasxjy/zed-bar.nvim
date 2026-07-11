if vim.g.loaded_zed_bar then
  return
end
vim.g.loaded_zed_bar = true

vim.api.nvim_create_user_command("ZedBarRefresh", function()
  require("zed-bar").refresh()
end, { desc = "Refresh zed-bar symbols" })
