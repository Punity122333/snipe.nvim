local M  = {}

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
    -- Pre-populate the file cache in the background so the first <leader>ff is instant.
    require("snipe.nav").warm_cache()

    local warm_group = vim.api.nvim_create_augroup("SnipeWarm", { clear = true })
    vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
        group = warm_group,
        callback = function()
            vim.defer_fn(function()
                require("snipe.nav").warm_cache()
                require("snipe.picker").setup_hl()
            end, 10)
        end,
    })
end

return M
