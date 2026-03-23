-- lua/snipe/init.lua
-- Public API. Call require("snipe").setup() to register default keymaps,
-- or call individual pickers directly: require("snipe").nav.files() etc.

local M = {}

M.nav    = require("snipe.nav")
M.search = require("snipe.search")
M.rg     = require("snipe.rg")

---@class SnipeConfig
---@field keys boolean   Register default keymaps (default: true)

---@param opts? SnipeConfig
function M.setup(opts)
  opts = vim.tbl_extend("force", { keys = true }, opts or {})
  if opts.keys then
    require("snipe.keys").register()
  end
end

return M
