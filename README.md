# snipe.nvim

A floating picker suite for Neovim — files, buffers, grep, undo history, keymaps, and more.

## Install

With **lazy.nvim**:

```lua
{
  "yourgithub/snipe.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",  -- optional, for icons
  },
  event = "VeryLazy",
  config = function()
    require("snipe").setup()
  end,
}
```

## Default Keymaps

| Key           | Picker                    |
|---------------|---------------------------|
| `<leader>ff`  | Files (fd)                |
| `<leader>fb`  | Buffers                   |
| `<leader>f'`  | Marks                     |
| `<leader>fr`  | LSP References            |
| `<leader>fo`  | Recent Files              |
| `<leader>fj`  | Projects                  |
| `<leader>fd`  | Diagnostics (buffer)      |
| `<leader>f;`  | Diagnostics (workspace)   |
| `<leader>fw`  | Ripgrep (fast)            |
| `<leader>sg`  | Grep (git root)           |
| `<leader>s.`  | Grep (cwd)                |
| `<leader>sw`  | Grep word (root)          |
| `<leader>sW`  | Grep word (cwd)           |
| `<leader>sa`  | Autocmds                  |
| `<leader>sc`  | Command History           |
| `<leader>sC`  | Commands                  |
| `<leader>sh`  | Help Pages                |
| `<leader>sH`  | Highlights                |
| `<leader>si`  | Icons                     |
| `<leader>sj`  | Jumps                     |
| `<leader>sk`  | Keymaps                   |
| `<leader>sl`  | Location List             |
| `<leader>sM`  | Man Pages                 |
| `<leader>sp`  | Plugin Spec (lazy.nvim)   |
| `<leader>sq`  | Quickfix                  |
| `<leader>su`  | Undo History (dual-pane)  |
| `<leader>s"`  | Registers                 |
| `<leader>s/`  | Search History            |
| `<leader>sn`  | Noice History             |

## Disable default keymaps

```lua
require("snipe").setup({ keys = false })

-- then bind manually:
local snipe = require("snipe")
vim.keymap.set("n", "<leader>ff", snipe.nav.files)
vim.keymap.set("n", "<leader>su", snipe.search.undo)
vim.keymap.set("n", "<leader>fw", snipe.rg.rg)
```

## Picker keybindings (inside any picker)

| Key              | Action            |
|------------------|-------------------|
| `<CR>`           | Open selection    |
| `<C-n>` / `↓`   | Next result       |
| `<C-p>` / `↑`   | Previous result   |
| `j` / `k`        | Navigate (normal) |
| `q`              | Close             |

## Requirements

- Neovim ≥ 0.10
- `fd` or `find` (for file picker)
- `rg` / ripgrep (for grep pickers)
- `nvim-web-devicons` (optional, for icons)
