# Visual reference

- Reference: `reference.png`
- Surface: Neovim `winbar`
- State: a TypeScript buffer with nested LSP document symbols
- Reproduction: open a file with an attached LSP and run `:set winbar?`

The source image comes from a GUI editor with unconstrained row height. Neovim's winbar is one
terminal cell tall, so validation targets component order, spacing, separator shape, and highlight
roles rather than GUI pixel dimensions.
