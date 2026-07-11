# zed-bar.nvim

A small, LSP-powered Neovim winbar inspired by Zed's breadcrumb layout.

It renders the current buffer path first, followed by the symbol hierarchy at the cursor. Each
symbol includes a Nerd Font icon and a highlight matching its LSP `SymbolKind`.

## Requirements

- Neovim 0.11+
- A language server that supports `textDocument/documentSymbol`
- A Nerd Font for symbol icons

## Installation

### `vim.pack`

```lua
vim.pack.add({
  "https://github.com/nicholasxjy/zed-bar.nvim",
})

require("zed-bar").setup()
```

### lazy.nvim

```lua
{
  "nicholasxjy/zed-bar.nvim",
  config = function()
    require("zed-bar").setup()
  end,
}
```

## Configuration

```lua
require("zed-bar").setup({
  -- "relative" matches the reference layout; "basename" shows only the file name.
  path = "relative",
  separator = " › ",
  padding = { left = 1, right = 1 },
  update_debounce = 24,
  symbol_debounce = 120,
  max_depth = 8,
  enabled = function(buf, win)
    return vim.bo[buf].buftype == ""
  end,
})
```

`path` can also be a function with the signature `function(buf, full_path): string`.

Run `:ZedBarRefresh` to request fresh symbols manually.

## Highlights

- `ZedBarNormal`
- `ZedBarFile`
- `ZedBarSeparator`
- `ZedBarKind{SymbolKind}` (for example, `ZedBarKindFunction`)
- `ZedBarIconKind{SymbolKind}` (for example, `ZedBarIconKindFunction`)

Every group is defined with `default = true`, so colors can be set before or after `setup()`.

```lua
vim.api.nvim_set_hl(0, "ZedBarFile", { fg = "#a9b1c3", bold = true })
vim.api.nvim_set_hl(0, "ZedBarSeparator", { fg = "#596171" })
```

## Performance

Cursor movement only walks a cached symbol tree and updates a pre-rendered winbar string. LSP
requests are asynchronous, debounced, and limited to buffer text changes, writes, attach events,
or explicit refreshes. An outdated in-flight request is cancelled before a new one is sent.

## Testing

```sh
nvim --headless -u NONE -l tests/run.lua
```
