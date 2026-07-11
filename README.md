# zed-bar.nvim

A small, source-aware Neovim winbar inspired by Zed's breadcrumb layout.

It renders the current buffer path first, followed by the symbol hierarchy at the cursor. Symbols
come from Markdown headings, LSP, or Tree-sitter and include a Nerd Font icon plus a matching
highlight.

## Features

- Current buffer path with its own highlight group
- Cursor-aware symbol breadcrumbs with Nerd Font icons
- LSP, Tree-sitter, and Markdown heading sources
- Per-kind highlights for functions, classes, methods, variables, headings, control flow, and more
- Asynchronous LSP requests with cancellation and debounced updates
- No required plugin dependencies

## Requirements

- Neovim 0.11+
- A language server with `textDocument/documentSymbol` support or a Tree-sitter parser for code
  buffers (Markdown headings work without either)
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
  -- Sources are tried in order; the first non-empty result wins.
  sources = function(buf)
    if vim.bo[buf].filetype == "markdown" then
      return { "markdown", "lsp", "treesitter" }
    end
    return { "lsp", "treesitter" }
  end,
  enabled = function(buf, win)
    return vim.bo[buf].buftype == ""
  end,
})
```

`path` can also be a function with the signature `function(buf, full_path): string`.

Run `:ZedBarRefresh` to request fresh symbols manually.

## Symbol sources

Sources use fallback semantics: the first source that returns symbols at the cursor wins.

- `lsp`: uses `textDocument/documentSymbol` and supports nested `DocumentSymbol` and flat
  `SymbolInformation` responses.
- `treesitter`: follows the syntax-node ancestors at the cursor. It recognizes functions, methods,
  classes, declarations, variables, calls, control flow, JSX elements, mappings, and other common
  node types.
- `markdown`: builds the current heading hierarchy from ATX and Setext headings while ignoring
  headings inside fenced code blocks.

The defaults are:

- Markdown buffers: `markdown → lsp → treesitter`
- Other file buffers: `lsp → treesitter`

Change the order or omit a source through `sources`. To always prefer Tree-sitter:

```lua
require("zed-bar").setup({
  sources = { "treesitter", "lsp" },
})
```

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

Cursor movement walks the cached LSP/Markdown data or the current Tree-sitter ancestor chain, then
updates a pre-rendered winbar string. LSP requests are asynchronous, debounced, and limited to
buffer text changes, writes, attach events, or explicit refreshes. An outdated in-flight request
is cancelled before a new one is sent. When LSP has no symbol at the cursor, Tree-sitter is used
automatically. The winbar row is reserved before the buffer is displayed, and identical renders
are skipped to avoid first-entry flicker and unnecessary redraws.

## Testing

```sh
nvim --headless -u NONE -l tests/run.lua
```
