# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Features

- Show only enclosing scopes by default (`detail = "scope"`): anonymous functions and tables are
  named after the binding, key, or call that holds them, and locals, calls, and control flow at the
  cursor are left out; `detail = "full"` keeps the previous behavior
- Split the path into a dimmed directory (`ZedBarDir`) and the file name (`ZedBarFile`), with a file
  icon from mini.icons or nvim-web-devicons and modified/readonly flags (`file_status`)
- Fit narrow windows by abbreviating directories, collapsing outer symbols into `…`, and truncating
  the innermost name while keeping the file name visible
- Dim inactive windows with `ZedBarInactive` (`dim_inactive`)
- Click a symbol to open a menu of its siblings, or the file name for the top-level outline; move
  between levels with `h`/`l` and jump with `<CR>`
- Add `:ZedBar {pick,parent,yank,toggle,refresh,info}` and the matching Lua functions
- Add `icons = false` for fonts without Nerd Font glyphs

### Changed

- `ZedBarFile` now covers only the file name and links to `WinBar`; the directory uses `ZedBarDir`
- Tree-sitter `function_call` and `method_call` nodes are calls, not functions

## [v0.0.6] - 2026-10-02

### Performance

- Read Tree-sitter node names from a bounded prefix instead of the full node text (a cursor
  inside a 3,000-line component drops from ~4.4 ms to ~30 µs per lookup)
- Parse Markdown headings incrementally from checkpoints instead of re-parsing the buffer after
  every edit (~2.8 ms to ~40 µs at 19k lines), and stop discarding that cache on each edit
- Pre-render separator, icon, and highlight segments once per `setup()`, resolve the LSP path
  only when the `lsp` source is consulted, and cache renders for static `sources` lists
- Avoid `vim.wo`/`vim.bo` proxy allocations and linear `disabled_filetypes` scans on the render path

### Bug Fixes

- Re-parse an outdated Tree-sitter tree before looking up nodes, so breadcrumbs follow edits
  without a highlighter and stale node ranges no longer raise errors
- Stop naming anonymous blocks (class/interface bodies, statement blocks, tables, `() => {`)
  after their first inner identifier
- Only close Markdown code fences with a matching fence of at least the same length and no info
  string
- Re-request symbols from a remaining LSP client when another client detaches

## [v0.0.5] - 2026-08-30

### Bug Fixes

- Avoid stale Tree-sitter nodes during autoread
  ([#5](https://github.com/nicholasxjy/zed-bar.nvim/pull/5))

## [v0.0.4] - 2026-08-16

### Performance

- Optimize winbar rendering and Tree-sitter symbol extraction
  ([`2f47106`](https://github.com/nicholasxjy/zed-bar.nvim/commit/2f47106))

## [v0.0.3] - 2026-08-02

### Features

- Use optional nvim-treesitter node parsing for more precise code-symbol matching
- Add nvim-treesitter scopes support
- Configure symbol kinds and disabled filetypes

### Bug Fixes

- Handle missing treesitter parser gracefully
- Deduplicate declaration symbols

## [v0.0.2] - 2026-07-12

### Features

- Initial Zed-style breadcrumb winbar with LSP, Tree-sitter, and Markdown sources

## [v0.0.1] - 2026-07-11

### Initial release
