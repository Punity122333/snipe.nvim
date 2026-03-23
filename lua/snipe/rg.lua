-- lua/snipe/rg.lua
-- Fast floating ripgrep picker (standalone, no open_picker dependency).

local M = {}

function M.rg()
  local query   = ""
  local results = {}
  local selected = 1

  local origin_win = (function()
    local best, best_score = nil, -1
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative == "" then
        local buf   = vim.api.nvim_win_get_buf(w)
        local score = 0
        if vim.bo[buf].buftype == "" then score = score + 10 end
        if vim.bo[buf].buflisted  then score = score + 2  end
        if vim.api.nvim_buf_get_name(buf) ~= "" then score = score + 1 end
        if score > best_score then best, best_score = w, score end
      end
    end
    return best or vim.api.nvim_get_current_win()
  end)()

  local ui      = vim.api.nvim_list_uis()[1]
  local W, H    = ui.width, ui.height
  local box_w   = math.floor(W * 0.90)
  local box_h   = math.floor(H * 0.85)
  local box_row = math.floor((H - box_h) / 2) - 1
  local box_col = math.floor((W - box_w) / 2)
  local left_w      = math.floor(box_w * 0.45)
  local right_w     = box_w - left_w - 1
  local input_outer = 3
  local results_h   = box_h - input_outer - 1

  -- ─── Backdrop (Zero Border, Full Edge-to-Edge) ─────────────────────────────
  vim.api.nvim_set_hl(0, "RgBackdrop", { bg = "#1a1b26" })
  local backdrop_buf = vim.api.nvim_create_buf(false, true)
  local backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
    relative = "editor",
    width = W,
    height = H,
    row = 0,
    col = 0,
    style = "minimal",
    border = "none", -- This kills the outer border
    focusable = false,
    zindex = 45,
  })
  vim.wo[backdrop_win].winhl = "Normal:RgBackdrop,FloatBorder:RgBackdrop"
  -- ──────────────────────────────────────────────────────────────────────────

  require("snipe.picker").setup_hl()
  vim.api.nvim_set_hl(0, "RgNormal",       { fg = "#c0caf5" })
  vim.api.nvim_set_hl(0, "RgBorder",       { fg = "#27a1b9" })
  vim.api.nvim_set_hl(0, "RgTitle",        { fg = "#ff9e64", bold = true })
  vim.api.nvim_set_hl(0, "RgSelected",     { bg = "#2d3250", fg = "#c0caf5" })
  vim.api.nvim_set_hl(0, "RgCursor",       { fg = "#7aa2f7", bold = true })
  vim.api.nvim_set_hl(0, "RgPreviewLine",  { bg = "#7aa2f7", fg = "#1a1b26", bold = true })
  vim.api.nvim_set_hl(0, "RgPreviewLineCur",{ bg = "#e07840", fg = "#1a1b26", bold = true })
  vim.api.nvim_set_hl(0, "RgPromptArrow",  { fg = "#27a1b9", bold = true })
  vim.api.nvim_set_hl(0, "RgFilePath",     { fg = "#c4915a" })
  vim.api.nvim_set_hl(0, "RgLnum",         { fg = "#73daca" })

  local function make_win(width, height, row, col, title, zindex)
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor", width = width, height = height, row = row, col = col,
      style = "minimal", border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
      title = title and (" " .. title .. " ") or nil, title_pos = title and "left" or nil, zindex = zindex or 50,
    })
    vim.wo[win].winhl = "Normal:RgNormal,FloatBorder:RgBorder,FloatTitle:RgTitle"
    vim.wo[win].foldenable = false; vim.wo[win].cursorline = false; vim.wo[win].fillchars = "eob: "
    return buf, win
  end

  local function set_ro_lines(buf, lines)
    vim.bo[buf].modifiable = true
    local clean = {}
    for _, l in ipairs(lines) do clean[#clean + 1] = l:gsub("\r", "") end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, clean)
    vim.bo[buf].modifiable = false
  end

  local input_buf, input_win = make_win(left_w, 1, box_row, box_col, nil, 55)
  vim.wo[input_win].winhl = "Normal:RgNormal,FloatBorder:RgPromptArrow,FloatTitle:RgTitle"
  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { " >  " })
  local ns_prompt = vim.api.nvim_create_namespace("rg_prompt")
  local function apply_prompt_hl()
    vim.api.nvim_buf_clear_namespace(input_buf, ns_prompt, 0, -1)
    vim.api.nvim_buf_add_highlight(input_buf, ns_prompt, "RgPromptArrow", 0, 1, 2)
  end
  apply_prompt_hl()
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = input_buf,
    callback = function() if vim.api.nvim_win_get_cursor(0)[2] < 4 then vim.api.nvim_win_set_cursor(0, { 1, 4 }) end end,
  })

  local results_buf, results_win = make_win(left_w, results_h, box_row + input_outer, box_col, "Results", 50)
  vim.wo[results_win].wrap = false; vim.bo[results_buf].modifiable = false

  local preview_buf, preview_win = make_win(right_w - 2, box_h - 1, box_row, box_col + left_w + 2, "Preview", 50)
  vim.wo[preview_win].wrap = false; vim.wo[preview_win].scrolloff = 5
  vim.wo[preview_win].list = true; vim.wo[preview_win].listchars = "extends:…,precedes:…,tab:  "
  vim.bo[preview_buf].modifiable = false

  for _, b in ipairs({ input_buf, results_buf, preview_buf }) do
    vim.b[b].blink_cmp_disable = true; vim.b[b].completion = false; vim.b[b].cmp_disable = true
  end

  vim.api.nvim_set_current_win(input_win)
  vim.api.nvim_win_set_cursor(input_win, { 1, 4 })
  vim.cmd("startinsert")

  local ns_sel     = vim.api.nvim_create_namespace("rg_sel")
  local ns_cursor  = vim.api.nvim_create_namespace("rg_cursor")
  local ns_path    = vim.api.nvim_create_namespace("rg_path")
  local ns_prev    = vim.api.nvim_create_namespace("rg_prev")
  local ns_prev_cur= vim.api.nvim_create_namespace("rg_prev_cur")
  local ns_icon    = vim.api.nvim_create_namespace("rg_icon")
  local ns_lnum    = vim.api.nvim_create_namespace("rg_lnum")
  local timer      = nil
  local preview_timer = nil
  local has_devicons, devicons = pcall(require, "nvim-web-devicons")
  local line_path_ranges, icon_metadata, lnum_metadata = {}, {}, {}

  local function get_icon_data(filepath)
    local name = vim.fn.fnamemodify(filepath, ":t")
    local ext  = name:match("%.([^.]+)$") or ""
    if has_devicons then
      local icon, hl = devicons.get_icon(name, ext, { default = true })
      return icon or "", hl or "RgNormal"
    end
    return "", "RgNormal"
  end

  local function update_preview()
    if #results == 0 then set_ro_lines(preview_buf, {}); return end
    local line = results[selected]
    if not line then return end
    local file, lnum, col = line:match("^(.+):(%d+):(%d+):")
    if not file then return end
    local ok, lines = pcall(vim.fn.readfile, file)
    if not ok or not lines then set_ro_lines(preview_buf, { " (cannot read file)" }); return end
    local padded_lines = {}
    for i, v in ipairs(lines) do padded_lines[i] = " " .. v:gsub("\t", "    ") end
    set_ro_lines(preview_buf, padded_lines)
    vim.api.nvim_buf_clear_namespace(preview_buf, ns_prev,     0, -1)
    vim.api.nvim_buf_clear_namespace(preview_buf, ns_prev_cur, 0, -1)
    local ext = file:match("%.([^.]+)$")
    if ext then local ft = vim.filetype.match({ filename = file }) or ext; if ft then vim.bo[preview_buf].syntax = ft end end
    local lnum_n = tonumber(lnum)
    if not lnum_n then return end
    local col_n = tonumber(col)
    local match_col = (function()
      local raw = lines[lnum_n] or ""
      local target = col_n and (col_n - 1) or 0
      local transformed, i = 0, 1
      while i <= #raw and (i - 1) < target do
        transformed = transformed + (raw:sub(i, i) == "\t" and 4 or 1); i = i + 1
      end
      return transformed + 1
    end)()
    local win_w = vim.api.nvim_win_get_width(preview_win)
    local win_h = vim.api.nvim_win_get_height(preview_win)
    local cur_leftcol = tonumber(vim.fn.win_execute(preview_win, "echo winsaveview()['leftcol']"):match("%d+")) or 0
    local match_visible = match_col >= cur_leftcol and match_col < cur_leftcol + win_w - 2
    local leftcol = match_visible and cur_leftcol or math.max(0, match_col - math.floor(win_w / 2))
    local topline = math.max(1, lnum_n - math.floor(win_h / 2))
    vim.fn.win_execute(preview_win, string.format("call winrestview({'lnum':%d,'col':%d,'leftcol':%d,'topline':%d})", lnum_n, match_col, leftcol, topline))
    if query ~= "" then
      local bottom = math.min(#padded_lines, topline + win_h - 1)
      local visible_matches = 0
      for i = topline, bottom do
        local s = 0
        while true do local m = vim.fn.matchstrpos(padded_lines[i] or "", query, s, 1); if m[2] == -1 then break end; visible_matches = visible_matches + 1; s = m[3] end
      end
      if visible_matches > 1 then
        for i, text in ipairs(padded_lines) do
          if i ~= lnum_n then
            local s = 0
            while true do local m = vim.fn.matchstrpos(text, query, s, 1); if m[2] == -1 then break end; vim.api.nvim_buf_add_highlight(preview_buf, ns_prev, "RgPreviewLine", i - 1, m[2], m[3]); s = m[3] end
          end
        end
      end
      if padded_lines[lnum_n] then
        local match_str = vim.fn.matchstr(padded_lines[lnum_n], query, match_col)
        local match_end = match_col - 1 + #match_str
        if #match_str > 0 then
          vim.api.nvim_buf_set_extmark(preview_buf, ns_prev_cur, lnum_n - 1, match_col, { end_col = match_end + 1, hl_group = "RgPreviewLineCur", priority = 200 })
        end
      end
    end
  end

  local function apply_highlights()
    vim.api.nvim_buf_clear_namespace(results_buf, ns_path, 0, -1)
    vim.api.nvim_buf_clear_namespace(results_buf, ns_icon, 0, -1)
    vim.api.nvim_buf_clear_namespace(results_buf, ns_lnum, 0, -1)
    for i, range in pairs(line_path_ranges) do vim.api.nvim_buf_add_highlight(results_buf, ns_path, "RgFilePath", i - 1, range[1], range[2]) end
    for i, meta  in pairs(icon_metadata)    do vim.api.nvim_buf_add_highlight(results_buf, ns_icon, meta.hl, i - 1, meta.start, meta.stop) end
    for i, meta  in pairs(lnum_metadata)    do vim.api.nvim_buf_add_highlight(results_buf, ns_lnum, "RgLnum", i - 1, meta.start, meta.stop) end
  end

  local function highlight_selected()
    vim.api.nvim_buf_clear_namespace(results_buf, ns_sel,    0, -1)
    vim.api.nvim_buf_clear_namespace(results_buf, ns_cursor, 0, -1)
    if #results > 0 and results[selected] then
      vim.api.nvim_buf_add_highlight(results_buf, ns_sel, "RgSelected", selected - 1, 0, -1)
      vim.api.nvim_buf_set_extmark(results_buf, ns_cursor, selected - 1, 0, { virt_text = { { " > ", "RgCursor" } }, virt_text_pos = "overlay", hl_mode = "combine" })
      pcall(vim.api.nvim_win_set_cursor, results_win, { selected, 0 })
    end
    vim.api.nvim_win_set_config(results_win, { footer = string.format(" %d/%d ", selected, #results), footer_pos = "right" })
    if preview_timer then preview_timer:stop() end
    preview_timer = vim.defer_fn(update_preview, 80)
  end

  local function render_results()
    local display = {}
    line_path_ranges, icon_metadata, lnum_metadata = {}, {}, {}
    local max_len = left_w - 3
    for i, line in ipairs(results) do
      local file, lnum, _, text = line:match("^(.+):(%d+):(%d+):(.*)")
      if file then
        local rel  = vim.fn.fnamemodify(file, ":.")
        local icon, icon_hl = get_icon_data(file)
        local prefix = "   " .. icon .. " "
        local path_part = rel
        local lnum_part = ":" .. lnum
        local full_str  = prefix .. path_part .. lnum_part .. "  " .. text:gsub("^%s+", "")
        local char_len  = vim.fn.strchars(full_str)
        if char_len > max_len then full_str = vim.fn.strcharpart(full_str, 0, max_len - 1) .. "…"
        elseif char_len < max_len then full_str = full_str .. string.rep(" ", max_len - char_len) end
        display[i] = full_str
        icon_metadata[i]     = { hl = icon_hl, start = 3, stop = #prefix - 1 }
        line_path_ranges[i]  = { #prefix, #prefix + #path_part }
        lnum_metadata[i]     = { start = #prefix + #path_part, stop = #prefix + #path_part + #lnum_part }
      else
        display[i] = "   " .. line
      end
    end
    if #results == 0 then display = { "   (no results)" } end
    set_ro_lines(results_buf, display)
    apply_highlights()
    highlight_selected()
  end

  local function run_rg(q)
    if #q < 2 then
      results = {}; set_ro_lines(results_buf, { "   (type at least 2 chars)" })
      vim.api.nvim_win_set_config(results_win, { footer = "" }); return
    end
    vim.fn.jobstart({ "rg", "--vimgrep", "--smart-case", "--color=never", q, vim.fn.getcwd() }, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if not data then return end
        results  = vim.tbl_filter(function(l) return l ~= "" end, data)
        selected = 1
        vim.schedule(render_results)
      end,
    })
  end

  local function close()
    pcall(vim.api.nvim_win_close, backdrop_win, true)
    pcall(vim.api.nvim_win_close, input_win,   true)
    pcall(vim.api.nvim_win_close, results_win, true)
    pcall(vim.api.nvim_win_close, preview_win, true)
    vim.cmd("stopinsert")
  end

  local function open_selected()
    if #results == 0 then return end
    local line = results[selected]
    if not line then return end
    local file, lnum, col = line:match("^(.+):(%d+):(%d+):")
    if not file then return end
    local lnum_n = tonumber(lnum) or 1
    local col_n  = (tonumber(col) or 1) - 2
    local abs    = vim.fn.fnamemodify(file, ":p")
    close()
    vim.schedule(function()
      local win = nil
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative == "" then
          if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)), ":p") == abs then win = w; break end
        end
      end
      if win then vim.api.nvim_set_current_win(win)
      else vim.api.nvim_set_current_win(origin_win); vim.cmd("edit " .. vim.fn.fnameescape(abs)) end
      vim.api.nvim_win_set_cursor(0, { lnum_n, col_n })
      vim.cmd("normal! zz")
    end)
  end

  local function next_res() if selected < #results then selected = selected + 1; highlight_selected() end end
  local function prev_res() if selected > 1        then selected = selected - 1; highlight_selected() end end

  for _, b in ipairs({ input_buf, results_buf, preview_buf }) do
    local opts = { noremap = true, silent = true, buffer = b }
    vim.keymap.set({ "i", "n" }, "<CR>",   open_selected, opts)
    vim.keymap.set({ "i", "n" }, "<C-n>",  next_res,      opts)
    vim.keymap.set({ "i", "n" }, "<Down>", next_res,      opts)
    vim.keymap.set({ "i", "n" }, "<C-p>",  prev_res,      opts)
    vim.keymap.set({ "i", "n" }, "<Up>",   prev_res,      opts)
    if b ~= input_buf then
      vim.keymap.set("n", "j", next_res, opts); vim.keymap.set("n", "k", prev_res, opts)
      vim.keymap.set({ "i", "n" }, "q", close, opts)
    else
      vim.keymap.set("n", "q", close, opts)
    end
  end

  vim.api.nvim_buf_attach(input_buf, false, {
    on_lines = function()
      local raw_q = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""
      if raw_q:sub(1, 4) ~= " >  " then
        local fixed_q = " >  " .. raw_q:gsub("^%s*>?%s*", "")
        vim.schedule(function() vim.api.nvim_buf_set_lines(input_buf, 0, 1, false, { fixed_q }); vim.api.nvim_win_set_cursor(input_win, { 1, #fixed_q }); apply_prompt_hl() end)
        query = vim.trim(fixed_q:sub(5))
      else
        query = vim.trim(raw_q:sub(5)); vim.schedule(apply_prompt_hl)
      end
      if timer then timer:stop() end
      timer = vim.defer_fn(function() run_rg(query) end, 150)
    end,
  })
end

return M
