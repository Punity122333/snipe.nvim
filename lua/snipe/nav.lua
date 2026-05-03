-- lua/snipe/nav.lua
-- File, buffer, mark, LSP-reference, oldfile, project, git-file, config-file and diagnostic pickers.

local M = {}

local P = require("snipe.picker")

local function open_picker(opts) P.open_picker(opts) end
local function get_icon(f) return P.get_icon(f) end
local function filter(...) return P.filter(...) end
local function read_file(p) return P.read_file(p) end
local function jump_to(...) P.jump_to(...) end
local function file_preview(p, l) return P.file_preview(p, l) end
local function render_file_row(...) return P.render_file_row(...) end

-- Cache fd availability once at module load (vim.fn.executable is a vimL call).
local _use_fd = vim.fn.executable("fd") == 1 or vim.fn.executable("fdfind") == 1
local _fd_bin = vim.fn.executable("fd") == 1 and "fd" or "fdfind"

-- ── File cache ────────────────────────────────────────────────────────────────
-- Populated at setup() time so the first <leader>ff open is instant.

local _fcache = {
    files   = nil, -- list of file paths
    cwd     = nil, -- cwd the cache was built for
    loading = false, -- guard against concurrent jobs
}

local function _build_fd_cmd(dir)
    if _use_fd then
        return { _fd_bin, "--type", "f", "--color=never", "--hidden",
            "--exclude", ".git", "--exclude", "node_modules", ".", dir }
    else
        return { "find", dir, "-type", "f",
            "-not", "-path", "*/.git/*", "-not", "-path", "*/node_modules/*" }
    end
end

local function _refresh_cache(cwd)
    if _fcache.loading then return end
    _fcache.loading = true
    vim.fn.jobstart(_build_fd_cmd(cwd), {
        stdout_buffered = true,
        on_stdout = function(_, data)
            _fcache.files   = vim.tbl_filter(function(l) return l ~= "" end, data or {})
            _fcache.cwd     = cwd
            _fcache.loading = false
        end,
        on_exit = function(_, code)
            if code ~= 0 then _fcache.loading = false end
        end,
    })
end

--- Called from snipe.setup() to pre-warm the file list before the user opens
--- the picker for the first time.
function M.warm_cache()
    _refresh_cache(vim.fn.getcwd())
end

-- ── Files (fd / find fallback) ────────────────────────────────────────────────

local function files_picker()
    local use_fd = _use_fd
    local fd_bin = _fd_bin
    local cwd = vim.fn.getcwd()

    local function build_cmd(query)
        if use_fd then
            local cmd = { fd_bin, "--type", "f", "--color=never", "--hidden", "--exclude", ".git", "--exclude",
                "node_modules" }
            if query ~= "" then table.insert(cmd, query) end
            table.insert(cmd, ".")
            return cmd
        else
            local cmd = { "find", cwd, "-type", "f", "-not", "-path", "*/.git/*", "-not", "-path", "*/node_modules/*" }
            if query ~= "" then
                table.insert(cmd, "-name"); table.insert(cmd, "*" .. query .. "*")
            end
            return cmd
        end
    end

    -- ── Cache hit: instant open, background refresh for next time ────────────
    if _fcache.files and _fcache.cwd == cwd then
        local snapshot = _fcache.files -- local ref so it's stable for this session
        -- Refresh in background so the cache stays fresh after file changes.
        _refresh_cache(cwd)
        open_picker({
            title = "Files",
            all_items = snapshot,
            filter_items = function(all, q) return filter(all, q) end,
            render_item  = function(item, max_len) return render_file_row(item, nil, nil, max_len) end,
            preview_item = function(item) return file_preview(item, 1) end,
            open_item    = function(item, ow) jump_to(ow, item, 1, 0) end,
        })
        return
    end

    -- ── Cache miss: live mode (first open before warm_cache finished, or cwd changed) ──
    -- Also kick off a cache build so subsequent opens are instant.
    _refresh_cache(cwd)
    open_picker({
        title = "Files",
        live = true,
        get_items    = function(q, cb)
            vim.fn.jobstart(build_cmd(q), {
                stdout_buffered = true,
                on_stdout       = function(_, data) cb(vim.tbl_filter(function(l) return l ~= "" end, data or {})) end,
                on_exit         = function(_, code) if code ~= 0 then cb({}) end end,
            })
        end,
        render_item  = function(item, max_len) return render_file_row(item, nil, nil, max_len) end,
        preview_item = function(item) return file_preview(item, 1) end,
        open_item    = function(item, ow) jump_to(ow, item, 1, 0) end,
    })
end

-- ── Git Files ────────────────────────────────────────────────────────────────

local function git_files_picker()
    local function build_cmd(query)
        local cmd = { "git", "ls-files", "--cached", "--others", "--exclude-standard" }
        if query ~= "" then
            -- filter client-side; git ls-files has no built-in fuzzy flag
        end
        return cmd
    end

    open_picker({
        title = "Git Files",
        live = true,
        get_items    = function(q, cb)
            vim.fn.jobstart(build_cmd(q), {
                stdout_buffered = true,
                on_stdout = function(_, data)
                    local lines = vim.tbl_filter(function(l) return l ~= "" end, data or {})
                    if q ~= "" then
                        local ql = q:lower()
                        lines = vim.tbl_filter(function(l) return l:lower():find(ql, 1, true) end, lines)
                    end
                    cb(lines)
                end,
                on_exit = function(_, code)
                    if code ~= 0 then
                        vim.notify("git ls-files failed – not a git repo?", vim.log.levels.WARN)
                        cb({})
                    end
                end,
            })
        end,
        render_item  = function(item, max_len) return render_file_row(item, nil, nil, max_len) end,
        preview_item = function(item) return file_preview(item, 1) end,
        open_item    = function(item, ow) jump_to(ow, item, 1, 0) end,
    })
end

-- ── Config Files (~/.config/nvim/) ───────────────────────────────────────────

local function config_files_picker()
    local config_dir = vim.fn.expand("~/.config/nvim")
    local use_fd = _use_fd
    local fd_bin = _fd_bin

    local function build_cmd(query)
        if use_fd then
            local cmd = { fd_bin, "--type", "f", "--color=never", "--hidden", "--exclude", ".git", ".", config_dir }
            if query ~= "" then
                -- insert pattern before the path
                table.insert(cmd, #cmd - 1, query)
            end
            return cmd
        else
            local cmd = { "find", config_dir, "-type", "f", "-not", "-path", "*/.git/*" }
            if query ~= "" then
                table.insert(cmd, "-name"); table.insert(cmd, "*" .. query .. "*")
            end
            return cmd
        end
    end

    open_picker({
        title = "Config Files (~/.config/nvim)",
        live = true,
        get_items    = function(q, cb)
            vim.fn.jobstart(build_cmd(q), {
                stdout_buffered = true,
                on_stdout       = function(_, data) cb(vim.tbl_filter(function(l) return l ~= "" end, data or {})) end,
                on_exit         = function(_, code) if code ~= 0 then cb({}) end end,
            })
        end,
        render_item  = function(item, max_len) return render_file_row(item, nil, nil, max_len) end,
        preview_item = function(item) return file_preview(item, 1) end,
        open_item    = function(item, ow) jump_to(ow, item, 1, 0) end,
    })
end

-- ── Buffers ───────────────────────────────────────────────────────────────────

local function buffers_picker()
    local items = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[bufnr].buflisted then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name ~= "" then
                local info = vim.fn.getbufinfo(bufnr)[1]
                items[#items + 1] = { bufnr = bufnr, name = name, modified = vim.bo[bufnr].modified, lnum = info and
                info.lnum or 1 }
            end
        end
    end
    open_picker({
        title = "Buffers",
        all_items = items,
        filter_items = function(all, q) return filter(all, q, function(it) return it.name end) end,
        render_item = function(item, _)
            local rel = vim.fn.fnamemodify(item.name, ":.")
            local icon, icon_hl = get_icon(item.name)
            local prefix = "   " .. icon .. " "
            local mod_part = item.modified and "  [+]" or ""
            local text = prefix .. rel .. mod_part
            local ic_s, ic_e = 3, 3 + #icon
            local rel_s, rel_e = ic_e + 1, ic_e + 1 + #rel
            local hls = { { ic_s, ic_e, icon_hl }, { rel_s, rel_e, "NavFilePath" } }
            if item.modified then hls[#hls + 1] = { rel_e + 2, rel_e + 5, "NavModified" } end
            return { text = text, highlights = hls }
        end,
        preview_item = function(item) return file_preview(item.name, item.lnum) end,
        open_item = function(item, ow)
            vim.api.nvim_set_current_win(ow)
            vim.api.nvim_set_current_buf(item.bufnr)
            vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
            vim.cmd("normal! zz")
        end,
    })
end

-- ── All Buffers (including scratch / unlisted) ────────────────────────────────

local function all_buffers_picker()
    local items = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            local name    = vim.api.nvim_buf_get_name(bufnr)
            local bt      = vim.bo[bufnr].buftype
            local listed  = vim.bo[bufnr].buflisted
            local display = name ~= "" and name or ("[scratch #" .. bufnr .. "]")
            -- include listed files, scratch buffers, and nofile buffers; skip internal neovim windows
            if listed or bt == "" or bt == "nofile" or bt == "acwrite" then
                local info = vim.fn.getbufinfo(bufnr)[1]
                items[#items + 1] = {
                    bufnr    = bufnr,
                    name     = name,
                    display  = display,
                    modified = vim.bo[bufnr].modified,
                    listed   = listed,
                    lnum     = info and info.lnum or 1,
                }
            end
        end
    end
    open_picker({
        title = "All Buffers",
        all_items = items,
        filter_items = function(all, q) return filter(all, q, function(it) return it.display end) end,
        render_item = function(item, _)
            local rel           = item.name ~= "" and vim.fn.fnamemodify(item.name, ":.") or item.display
            local icon, icon_hl = get_icon(item.name)
            local prefix        = "   " .. icon .. " "
            local unlisted      = not item.listed and "  [u]" or ""
            local mod_part      = item.modified and "  [+]" or ""
            local text          = prefix .. rel .. unlisted .. mod_part
            local ic_s, ic_e    = 3, 3 + #icon
            local rel_s, rel_e  = ic_e + 1, ic_e + 1 + #rel
            local hls           = { { ic_s, ic_e, icon_hl }, { rel_s, rel_e, "NavFilePath" } }
            if not item.listed then hls[#hls + 1] = { rel_e + 2, rel_e + 5, "NavLnum" } end
            if item.modified then hls[#hls + 1] = { rel_e + (not item.listed and 7 or 2), rel_e +
                (not item.listed and 10 or 5), "NavModified" } end
            return { text = text, highlights = hls }
        end,
        preview_item = function(item)
            if item.name ~= "" then return file_preview(item.name, item.lnum) end
            -- scratch buffer: grab lines directly
            local lines = vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false)
            return { lines = #lines > 0 and lines or { "(empty scratch buffer)" } }
        end,
        open_item = function(item, ow)
            vim.api.nvim_set_current_win(ow)
            vim.api.nvim_set_current_buf(item.bufnr)
            vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
            vim.cmd("normal! zz")
        end,
    })
end

-- ── Marks ─────────────────────────────────────────────────────────────────────

local function marks_picker()
    local items    = {}
    local cur_buf  = vim.api.nvim_get_current_buf()
    local cur_file = vim.api.nvim_buf_get_name(cur_buf)
    for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
        local pos  = vim.fn.getpos("'" .. c)
        local lnum = pos[2]
        if lnum ~= 0 and cur_file ~= "" then
            local lines = vim.api.nvim_buf_get_lines(cur_buf, lnum - 1, lnum, false)
            items[#items + 1] = { mark = c, file = cur_file, lnum = lnum, col = pos[3], text = lines[1] and
            vim.trim(lines[1]) or "" }
        end
    end
    for _, m in ipairs(vim.fn.getmarklist()) do
        local c = m.mark:sub(2)
        if c:match("[A-Z]") then
            local filepath = vim.fn.expand(m.file or "")
            local lnum, col = m.pos[2], m.pos[3]
            if filepath ~= "" and lnum ~= 0 then
                local text, bnr = "", vim.fn.bufnr(filepath)
                if bnr ~= -1 and vim.api.nvim_buf_is_loaded(bnr) then
                    local ls = vim.api.nvim_buf_get_lines(bnr, lnum - 1, lnum, false)
                    text = ls[1] and vim.trim(ls[1]) or ""
                else
                    local fl = read_file(filepath)
                    if fl and fl[lnum] then text = vim.trim(fl[lnum]) end
                end
                items[#items + 1] = { mark = c, file = filepath, lnum = lnum, col = col, text = text }
            end
        end
    end
    open_picker({
        title = "Marks",
        all_items = items,
        filter_items = function(all, q) return filter(all, q,
                function(it) return it.mark .. " " .. it.file .. " " .. it.text end) end,
        render_item  = function(item, _)
            local rel           = vim.fn.fnamemodify(item.file, ":.")
            local icon, icon_hl = get_icon(item.file)
            local mark_part     = " '" .. item.mark .. "  "
            local lnum_part     = ":" .. item.lnum
            local snippet       = item.text:sub(1, 50)
            local text          = mark_part .. icon .. " " .. rel .. lnum_part .. "  " .. snippet
            local m_e           = #mark_part
            local ic_s, ic_e    = m_e, m_e + #icon
            local rel_s, rel_e  = ic_e + 1, ic_e + 1 + #rel
            local lnum_e        = rel_e + #lnum_part
            return { text = text, highlights = { { 0, m_e, "NavMark" }, { ic_s, ic_e, icon_hl }, { rel_s, rel_e, "NavFilePath" }, { rel_e, lnum_e, "NavLnum" } } }
        end,
        preview_item = function(item) return file_preview(item.file, item.lnum) end,
        open_item    = function(item, ow) jump_to(ow, item.file, item.lnum, math.max(0, item.col - 1)) end,
    })
end

-- ── LSP References ────────────────────────────────────────────────────────────

local function references_picker()
    local word     = vim.fn.expand("<cword>")
    local params   = vim.lsp.util.make_position_params()
    params.context = { includeDeclaration = true }
    vim.lsp.buf_request_all(0, "textDocument/references", params, function(responses)
        local items = {}
        for _, resp in pairs(responses) do
            for _, ref in ipairs((resp and resp.result) or {}) do
                local uri = ref.uri or ref.targetUri
                if uri then
                    local filepath  = vim.uri_to_fname(uri)
                    local lnum      = ref.range.start.line + 1
                    local col       = ref.range.start.character
                    local text, bnr = "", vim.fn.bufnr(filepath)
                    if bnr ~= -1 and vim.api.nvim_buf_is_loaded(bnr) then
                        local ls = vim.api.nvim_buf_get_lines(bnr, lnum - 1, lnum, false)
                        text = ls[1] and vim.trim(ls[1]) or ""
                    else
                        local fl = read_file(filepath)
                        if fl and fl[lnum] then text = vim.trim(fl[lnum]) end
                    end
                    items[#items + 1] = { file = filepath, lnum = lnum, col = col, text = text }
                end
            end
        end
        table.sort(items, function(a, b)
            if a.file ~= b.file then return a.file < b.file end
            return a.lnum < b.lnum
        end)
        vim.schedule(function()
            if #items == 0 then
                vim.notify("No references found for: " .. word, vim.log.levels.WARN); return
            end
            open_picker({
                title = "Refs: " .. word,
                all_items = items,
                filter_items = function(all, q) return filter(all, q, function(it) return it.file .. " " .. it.text end) end,
                render_item  = function(item, max_len) return render_file_row(item.file, tostring(item.lnum),
                        item.text:sub(1, 50), max_len) end,
                preview_item = function(item) return file_preview(item.file, item.lnum) end,
                open_item    = function(item, ow) jump_to(ow, item.file, item.lnum, item.col) end,
            })
        end)
    end)
end

-- ── Recent Files ──────────────────────────────────────────────────────────────

local function oldfiles_picker()
    open_picker({
        title        = "Recent Files",
        build_items  = function(cb)
            local items = {}
            for _, f in ipairs(vim.v.oldfiles or {}) do
                if vim.fn.filereadable(f) == 1 then items[#items + 1] = f end
            end
            cb(items)
        end,
        filter_items = function(all, q) return filter(all, q) end,
        render_item  = function(item, max_len) return render_file_row(item, nil, nil, max_len) end,
        preview_item = function(item) return file_preview(item, 1) end,
        open_item    = function(item, ow) jump_to(ow, item, 1, 0) end,
    })
end

-- ── Projects ──────────────────────────────────────────────────────────────────

local function projects_picker()
    local seen, items = {}, {}
    local session_dir = vim.fn.stdpath("state") .. "/sessions"
    for _, sf in ipairs(vim.fn.glob(session_dir .. "/*.vim", false, true) or {}) do
        local encoded = vim.fn.fnamemodify(sf, ":t:r")
        local path    = encoded:gsub("%%", "/")
        if path:sub(1, 1) ~= "/" then path = "/" .. path end
        if vim.fn.isdirectory(path) == 1 and not seen[path] then
            seen[path] = true; items[#items + 1] = path
        end
    end
    for _, f in ipairs(vim.v.oldfiles or {}) do
        local dir = vim.fn.fnamemodify(f, ":h")
        if dir ~= "" and vim.fn.isdirectory(dir) == 1 and not seen[dir] then
            seen[dir] = true; items[#items + 1] = dir
        end
    end
    open_picker({
        title = "Projects",
        all_items = items,
        filter_items = function(all, q) return filter(all, q) end,
        render_item = function(item, _)
            local rel  = vim.fn.fnamemodify(item, ":~")
            local icon = "󰉋 "
            local text = "   " .. icon .. rel
            local ic_e = 3 + #icon
            return { text = text, highlights = { { 3, ic_e, "NavNormal" }, { ic_e, ic_e + #rel, "NavFilePath" } } }
        end,
        preview_item = function(item)
            local ok, entries = pcall(vim.fn.readdir, item)
            if not ok or not entries then return { lines = { " (empty)" } } end
            table.sort(entries)
            local lines = {}
            for _, e in ipairs(entries) do
                local full = item .. "/" .. e
                lines[#lines + 1] = " " .. (vim.fn.isdirectory(full) == 1 and "  " or "  ") .. e
            end
            return { lines = lines }
        end,
        open_item = function(item, ow)
            vim.api.nvim_set_current_win(ow)
            vim.cmd("cd " .. vim.fn.fnameescape(item))
            vim.notify("  cwd → " .. item, vim.log.levels.INFO)
            vim.defer_fn(files_picker, 60)
        end,
    })
end

-- ── Diagnostics ───────────────────────────────────────────────────────────────

local SEV_ICONS = { "󰅚 ", "󰀪 ", "󰋽 ", "󰌵 " }
local SEV_HLS   = { "NavDiagE", "NavDiagW", "NavDiagI", "NavDiagH" }

local function diagnostics_picker(workspace)
    local raw   = workspace and vim.diagnostic.get(nil) or vim.diagnostic.get(0)
    local items = {}
    for _, d in ipairs(raw) do
        local filepath = vim.api.nvim_buf_get_name(d.bufnr)
        if filepath ~= "" then
            items[#items + 1] = { file = filepath, lnum = d.lnum + 1, col = d.col, message = d.message:gsub("\n", " "), severity =
            d.severity or 1 }
        end
    end
    table.sort(items, function(a, b)
        if a.severity ~= b.severity then return a.severity < b.severity end
        if a.file ~= b.file then return a.file < b.file end
        return a.lnum < b.lnum
    end)
    open_picker({
        title        = workspace and "Diagnostics (workspace)" or "Diagnostics (buffer)",
        all_items    = items,
        filter_items = function(all, q) return filter(all, q, function(it) return it.file .. " " .. it.message end) end,
        render_item  = function(item, _)
            local sev          = item.severity or 1
            local sev_icon     = SEV_ICONS[sev] or "  "
            local sev_hl       = SEV_HLS[sev] or "NavNormal"
            local rel          = vim.fn.fnamemodify(item.file, ":.")
            local lnum_part    = ":" .. item.lnum
            local msg          = item.message:sub(1, 60)
            local text         = "   " .. sev_icon .. rel .. lnum_part .. "  " .. msg
            local sev_s, sev_e = 3, 3 + #sev_icon
            local rel_s, rel_e = sev_e, sev_e + #rel
            local lnum_e       = rel_e + #lnum_part
            return { text = text, highlights = { { sev_s, sev_e, sev_hl }, { rel_s, rel_e, "NavFilePath" }, { rel_e, lnum_e, "NavLnum" } } }
        end,
        preview_item = function(item) return file_preview(item.file, item.lnum) end,
        open_item    = function(item, ow) jump_to(ow, item.file, item.lnum, item.col) end,
    })
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.files() files_picker() end

function M.buffers() buffers_picker() end

function M.all_buffers() all_buffers_picker() end

function M.git_files() git_files_picker() end

function M.config_files() config_files_picker() end

function M.marks() marks_picker() end

function M.references() references_picker() end

function M.oldfiles() oldfiles_picker() end

function M.projects() projects_picker() end

function M.diagnostics(workspace) diagnostics_picker(workspace) end

return M
