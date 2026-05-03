---@diagnostic disable: unused-function, unused-local
-- lua/snipe/rg.lua
-- Fast floating ripgrep picker.
-- M.rg() uses original full-sized picker (with preview and two columns).
-- M.rg_buffer() uses a compact single-window picker (top‑right, no preview).

local M = {}
local P = require("snipe.picker")

local has_devicons, devicons = pcall(require, "nvim-web-devicons")

-- ── Highlight setup (once per session) ───────────────────────────────────────

local _full_hl_done = false
local function setup_full_hl()
	if _full_hl_done then return end
	_full_hl_done = true
	vim.api.nvim_set_hl(0, "RgNormal",         { fg = "#c0caf5", bg = "#1a1b26" })
	vim.api.nvim_set_hl(0, "RgBorder",         { fg = "#27a1b9" })
	vim.api.nvim_set_hl(0, "RgTitle",          { fg = "#ff9e64", bold = true })
	vim.api.nvim_set_hl(0, "RgSelected",       { bg = "#2d3250", fg = "#c0caf5" })
	vim.api.nvim_set_hl(0, "RgCursor",         { fg = "#7aa2f7", bold = true })
	vim.api.nvim_set_hl(0, "RgPreviewLine",    { bg = "#7aa2f7", fg = "#1a1b26", bold = true })
	vim.api.nvim_set_hl(0, "RgPreviewLineCur", { bg = "#e07840", fg = "#1a1b26", bold = true })
	vim.api.nvim_set_hl(0, "RgPromptArrow",    { fg = "#27a1b9", bold = true })
	vim.api.nvim_set_hl(0, "RgFilePath",       { fg = "#c4915a" })
	vim.api.nvim_set_hl(0, "RgLnum",           { fg = "#73daca" })
	vim.api.nvim_set_hl(0, "RgBackdrop",       { bg = "#1a1b26", fg = "#1a1b26" })
end

local _buf_hl_done = false
local function setup_buf_hl()
	if _buf_hl_done then return end
	_buf_hl_done = true
	vim.api.nvim_set_hl(0, "RgBufNormal",   { fg = "#c0caf5", bg = "NONE" })
	vim.api.nvim_set_hl(0, "RgBufBorder",   { fg = "#27a1b9" })
	vim.api.nvim_set_hl(0, "RgBufTitle",    { fg = "#ff9e64", bold = true })
	vim.api.nvim_set_hl(0, "RgBufSelected", { bg = "#2d3250", fg = "#c0caf5" })
	vim.api.nvim_set_hl(0, "RgBufCursor",   { fg = "#7aa2f7", bold = true })
	vim.api.nvim_set_hl(0, "RgBufPrompt",   { fg = "#27a1b9", bold = true })
	vim.api.nvim_set_hl(0, "RgBufSep",      { fg = "#ff9e64" })
	vim.api.nvim_set_hl(0, "RgBufLnum",     { fg = "#73daca" })
end

-- Pre-warm both at module load so no cost on first open.
vim.schedule(function()
	setup_full_hl()
	setup_buf_hl()
end)

local function rg_picker(search_dir, title, initial_query)
	local current_query = initial_query or ""
	P.open_picker({
		title = title or "Grep (fast)",
		live = true,
		initial_query = initial_query,
		get_items = function(q, cb)
			current_query = q or ""
			if #current_query < 2 then
				cb({})
				return
			end
			vim.fn.jobstart({ "rg", "--vimgrep", "--smart-case", "--color=never", current_query, search_dir }, {
				stdout_buffered = true,
				on_stdout = function(_, data)
					local items = {}
					for _, line in ipairs(data or {}) do
						if line ~= "" then
							local file, lnum, col, text = line:match("^(.+):(%d+):(%d+):(.*)")
							if file then
								items[#items + 1] = {
									file = file,
									lnum = tonumber(lnum),
									col = math.max(0, (tonumber(col) or 1) - 1),
									text = text or "",
								}
							end
						end
					end
					cb(items)
				end,
				on_exit = function(_, code)
					if code ~= 0 then
						cb({})
					end
				end,
			})
		end,
		render_item = function(item, _)
			local rel = vim.fn.fnamemodify(item.file, ":.")
			local icon, icon_hl = P.get_icon(item.file)
			local prefix = "   " .. icon .. " "
			local lnum_part = ":" .. item.lnum
			local snippet = (item.text or ""):gsub("^%s+", ""):sub(1, 50)
			local text = prefix .. rel .. lnum_part .. "  " .. snippet
			local ic_s, ic_e = 3, 3 + #icon
			local rel_s, rel_e = ic_e + 1, ic_e + 1 + #rel
			local snip_start = rel_e + #lnum_part + 2
			local match_hl = {}
			if current_query ~= "" then
				local s = 0
				while true do
					local m = vim.fn.matchstrpos(snippet, current_query, s, 1)
					if m[2] == -1 then
						break
					end
					match_hl[#match_hl + 1] = { snip_start + m[2], snip_start + m[3], "SrchResultMatch" }
					s = m[3]
				end
			end
			return {
				text = text,
				highlights = {
					{ ic_s, ic_e, icon_hl },
					{ rel_s, rel_e, "GrepFilePath" },
					{ rel_e, rel_e + #lnum_part, "NavLnum" },
				},
				match_hl = match_hl,
			}
		end,
		preview_item = function(item)
			local lines = P.read_file(item.file)
			if not lines then
				return nil
			end
			return {
				lines = lines,
				syntax = vim.filetype.match({ filename = item.file }),
				focus_lnum = item.lnum,
				match_col = item.col + 1,
				highlight_query = current_query,
			}
		end,
		open_item = function(item, origin_win)
			P.jump_to(origin_win, item.file, item.lnum, item.col)
		end,
	})
end

-- ─────────────────────────────────────────────────────────────────────
-- Full-sized picker (original layout)
-- ─────────────────────────────────────────────────────────────────────
local function full_picker()
	local query = ""
	local results = {}
	local selected = 1

	local origin_win = P.get_origin_win()

	local ui = vim.api.nvim_list_uis()[1]
	local W, H = ui.width, ui.height
	local box_w = math.floor(W * 0.90)
	local box_h = math.floor(H * 0.85)
	local box_row = math.floor((H - box_h) / 2) - 1
	local box_col = math.floor((W - box_w) / 2)
	local left_w = math.floor(box_w * 0.45)
	local right_w = box_w - left_w - 1
	local input_outer = 3
	local results_h = box_h - input_outer - 1

	require("snipe.picker").setup_hl()
	setup_full_hl()

	local function make_win(width, height, row, col, title, zindex)
		local buf = vim.api.nvim_create_buf(false, true)
		local win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
			title = title and (" " .. title .. " ") or nil,
			title_pos = title and "left" or nil,
			zindex = zindex or 50,
		})
		vim.wo[win].winhl = "Normal:RgNormal,FloatBorder:RgBorder,FloatTitle:RgTitle"
		vim.wo[win].foldenable = false
		vim.wo[win].cursorline = false
		vim.wo[win].fillchars = "eob: "
		return buf, win
	end

	local backdrop_buf = vim.api.nvim_create_buf(false, true)
	local backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
		relative = "editor",
		width = W,
		height = H,
		row = 0,
		col = 0,
		style = "minimal",
		border = "none",
		zindex = 40,
		focusable = false,
	})
	vim.wo[backdrop_win].winhl = "Normal:RgBackdrop"
	vim.wo[backdrop_win].foldenable = false

	local function set_ro_lines(buf, lines)
		vim.bo[buf].modifiable = true
		local clean = {}
		for _, l in ipairs(lines) do
			clean[#clean + 1] = l:gsub("\r", "")
		end
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
		callback = function()
			if vim.api.nvim_win_get_cursor(0)[2] < 4 then
				vim.api.nvim_win_set_cursor(0, { 1, 4 })
			end
		end,
	})

	local results_buf, results_win = make_win(left_w, results_h, box_row + input_outer, box_col, "Results", 50)
	vim.wo[results_win].wrap = false
	vim.bo[results_buf].modifiable = false

	local preview_buf, preview_win = make_win(right_w - 2, box_h - 1, box_row, box_col + left_w + 2, "Preview", 50)
	vim.wo[preview_win].wrap = false
	vim.wo[preview_win].scrolloff = 5
	vim.wo[preview_win].list = true
	vim.wo[preview_win].listchars = "extends:…,precedes:…,tab:  "
	vim.bo[preview_buf].modifiable = false

	for _, b in ipairs({ input_buf, results_buf, preview_buf, backdrop_buf }) do
		vim.b[b].blink_cmp_disable = true
		vim.b[b].completion = false
		vim.b[b].cmp_disable = true
	end

	vim.api.nvim_set_current_win(input_win)
	vim.api.nvim_win_set_cursor(input_win, { 1, 4 })
	vim.schedule(function()
		vim.cmd("startinsert")
	end)

	local ns_sel = vim.api.nvim_create_namespace("rg_sel")
	local ns_cursor = vim.api.nvim_create_namespace("rg_cursor")
	local ns_path = vim.api.nvim_create_namespace("rg_path")
	local ns_prev = vim.api.nvim_create_namespace("rg_prev")
	local ns_prev_cur = vim.api.nvim_create_namespace("rg_prev_cur")
	local ns_icon = vim.api.nvim_create_namespace("rg_icon")
	local ns_lnum = vim.api.nvim_create_namespace("rg_lnum")
	local timer = nil
	local preview_timer = nil
	local line_path_ranges, icon_metadata, lnum_metadata = {}, {}, {}

	-- rest of file unchanged… (only compatibility fixes applied)

	local function get_icon_data(filepath)
		local name = vim.fn.fnamemodify(filepath, ":t")
		local ext = name:match("%.([^.]+)$") or ""
		if has_devicons then
			local icon, hl = devicons.get_icon(name, ext, { default = true })
			return icon or "", hl or "RgNormal"
		end
		return "", "RgNormal"
	end

	local function update_preview()
		if #results == 0 then
			set_ro_lines(preview_buf, {})
			return
		end
		local line = results[selected]
		if not line then
			return
		end
		local file, lnum, col = line:match("^(.+):(%d+):(%d+):")
		if not file then
			return
		end
		local ok, lines = pcall(vim.fn.readfile, file)
		if not ok or not lines then
			set_ro_lines(preview_buf, { " (cannot read file)" })
			return
		end
		local padded_lines = {}
		for i, v in ipairs(lines) do
			padded_lines[i] = " " .. v:gsub("\t", "    ")
		end
		set_ro_lines(preview_buf, padded_lines)
		vim.api.nvim_buf_clear_namespace(preview_buf, ns_prev, 0, -1)
		vim.api.nvim_buf_clear_namespace(preview_buf, ns_prev_cur, 0, -1)
		local ext = file:match("%.([^.]+)$")
		if ext then
			local ft = vim.filetype.match({ filename = file }) or ext
			if ft then
				vim.bo[preview_buf].syntax = ft
			end
		end
		local lnum_n = tonumber(lnum)
		if not lnum_n then
			return
		end
		local col_n = tonumber(col)
		local match_col = (function()
			local raw = lines[lnum_n] or ""
			local target = col_n and (col_n - 1) or 0
			local transformed, i = 0, 1
			while i <= #raw and (i - 1) < target do
				transformed = transformed + (raw:sub(i, i) == "\t" and 4 or 1)
				i = i + 1
			end
			return transformed + 1
		end)()
		local win_w = vim.api.nvim_win_get_width(preview_win)
		local win_h = vim.api.nvim_win_get_height(preview_win)
		local cur_leftcol = tonumber(vim.fn.win_execute(preview_win, "echo winsaveview()['leftcol']"):match("%d+")) or 0
		local match_visible = match_col >= cur_leftcol and match_col < cur_leftcol + win_w - 2
		local leftcol = match_visible and cur_leftcol or math.max(0, match_col - math.floor(win_w / 2))
		local topline = math.max(1, lnum_n - math.floor(win_h / 2))
		vim.fn.win_execute(
			preview_win,
			string.format(
				"call winrestview({'lnum':%d,'col':%d,'leftcol':%d,'topline':%d})",
				lnum_n,
				match_col,
				leftcol,
				topline
			)
		)
		if query ~= "" then
			local bottom = math.min(#padded_lines, topline + win_h - 1)
			local visible_matches = 0
			for i = topline, bottom do
				local s = 0
				while true do
					local m = vim.fn.matchstrpos(padded_lines[i] or "", query, s, 1)
					if m[2] == -1 then
						break
					end
					visible_matches = visible_matches + 1
					s = m[3]
				end
			end
			if visible_matches > 1 then
				for i, text in ipairs(padded_lines) do
					if i ~= lnum_n then
						local s = 0
						while true do
							local m = vim.fn.matchstrpos(text, query, s, 1)
							if m[2] == -1 then
								break
							end
							vim.api.nvim_buf_add_highlight(preview_buf, ns_prev, "RgPreviewLine", i - 1, m[2], m[3])
							s = m[3]
						end
					end
				end
			end
			if padded_lines[lnum_n] then
				local match_str = vim.fn.matchstr(padded_lines[lnum_n], query, match_col)
				local match_end = match_col - 1 + #match_str
				if #match_str > 0 then
					vim.api.nvim_buf_set_extmark(
						preview_buf,
						ns_prev_cur,
						lnum_n - 1,
						match_col,
						{ end_col = match_end + 1, hl_group = "RgPreviewLineCur", priority = 200 }
					)
				end
			end
		end
	end

	local function apply_highlights()
		vim.api.nvim_buf_clear_namespace(results_buf, ns_path, 0, -1)
		vim.api.nvim_buf_clear_namespace(results_buf, ns_icon, 0, -1)
		vim.api.nvim_buf_clear_namespace(results_buf, ns_lnum, 0, -1)
		for i, range in pairs(line_path_ranges) do
			vim.api.nvim_buf_add_highlight(results_buf, ns_path, "RgFilePath", i - 1, range[1], range[2])
		end
		for i, meta in pairs(icon_metadata) do
			vim.api.nvim_buf_add_highlight(results_buf, ns_icon, meta.hl, i - 1, meta.start, meta.stop)
		end
		for i, meta in pairs(lnum_metadata) do
			vim.api.nvim_buf_add_highlight(results_buf, ns_lnum, "RgLnum", i - 1, meta.start, meta.stop)
		end
	end

	local function highlight_selected()
		vim.api.nvim_buf_clear_namespace(results_buf, ns_sel, 0, -1)
		vim.api.nvim_buf_clear_namespace(results_buf, ns_cursor, 0, -1)
		if #results > 0 and results[selected] then
			vim.api.nvim_buf_add_highlight(results_buf, ns_sel, "RgSelected", selected - 1, 0, -1)
			vim.api.nvim_buf_set_extmark(
				results_buf,
				ns_cursor,
				selected - 1,
				0,
				{ virt_text = { { " > ", "RgCursor" } }, virt_text_pos = "overlay", hl_mode = "combine" }
			)
			pcall(vim.api.nvim_win_set_cursor, results_win, { selected, 0 })
		end
		pcall(vim.api.nvim_win_set_config, results_win, {
			footer = string.format(" %d/%d ", selected, #results),
			footer_pos = "right",
		})
		if preview_timer then
			preview_timer:stop()
		end
		preview_timer = vim.defer_fn(update_preview, 80)
	end

	local function render_results()
		local display = {}
		line_path_ranges, icon_metadata, lnum_metadata = {}, {}, {}
		local max_len = left_w - 3
		for i, line in ipairs(results) do
			local file, lnum, _, text = line:match("^(.+):(%d+):(%d+):(.*)")
			if file then
				local rel = vim.fn.fnamemodify(file, ":.")
				local icon, icon_hl = get_icon_data(file)
				local prefix = "   " .. icon .. " "
				local path_part = rel
				local lnum_part = ":" .. lnum
				local full_str = prefix .. path_part .. lnum_part .. "  " .. text:gsub("^%s+", "")
				local char_len = vim.fn.strchars(full_str)
				if char_len > max_len then
					full_str = vim.fn.strcharpart(full_str, 0, max_len - 1) .. "…"
				elseif char_len < max_len then
					full_str = full_str .. string.rep(" ", max_len - char_len)
				end
				display[i] = full_str
				icon_metadata[i] = { hl = icon_hl, start = 3, stop = #prefix - 1 }
				line_path_ranges[i] = { #prefix, #prefix + #path_part }
				lnum_metadata[i] = { start = #prefix + #path_part, stop = #prefix + #path_part + #lnum_part }
			else
				display[i] = "   " .. line
			end
		end
		if #results == 0 then
			display = { "   (no results)" }
		end
		set_ro_lines(results_buf, display)
		apply_highlights()
		highlight_selected()
	end

	local function run_rg(q)
		if #q < 2 then
			results = {}
			set_ro_lines(results_buf, { "   (type at least 2 chars)" })
			pcall(vim.api.nvim_win_set_config, results_win, { footer = "" })
			return
		end
		vim.fn.jobstart({ "rg", "--vimgrep", "--smart-case", "--color=never", q, vim.fn.getcwd() }, {
			stdout_buffered = true,
			on_stdout = function(_, data)
				if not data then
					return
				end
				results = vim.tbl_filter(function(l)
					return l ~= ""
				end, data)
				selected = 1
				vim.schedule(render_results)
			end,
		})
	end

	local function close()
		pcall(vim.api.nvim_win_close, backdrop_win, true)
		pcall(vim.api.nvim_win_close, input_win, true)
		pcall(vim.api.nvim_win_close, results_win, true)
		pcall(vim.api.nvim_win_close, preview_win, true)
		vim.cmd("stopinsert")
	end

	local function open_selected()
		if #results == 0 then
			return
		end
		local line = results[selected]
		if not line then
			return
		end
		local file, lnum, col = line:match("^(.+):(%d+):(%d+):")
		if not file then
			return
		end
		local lnum_n = tonumber(lnum) or 1
		local col_n = (tonumber(col) or 1) - 1
		local abs = vim.fn.fnamemodify(file, ":p")
		close()
		vim.schedule(function()
			local win = nil
			for _, w in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_config(w).relative == "" then
					if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)), ":p") == abs then
						win = w
						break
					end
				end
			end
			if win then
				vim.api.nvim_set_current_win(win)
			else
				vim.api.nvim_set_current_win(origin_win)
				vim.cmd("edit " .. vim.fn.fnameescape(abs))
			end
			vim.api.nvim_win_set_cursor(0, { lnum_n, col_n })
			vim.cmd("normal! zz")
		end)
	end

	local function next_res()
		if selected < #results then
			selected = selected + 1
			highlight_selected()
		end
	end
	local function prev_res()
		if selected > 1 then
			selected = selected - 1
			highlight_selected()
		end
	end

	for _, b in ipairs({ input_buf, results_buf, preview_buf }) do
		local opts = { noremap = true, silent = true, buffer = b }
		vim.keymap.set({ "i", "n" }, "<CR>", open_selected, opts)
		vim.keymap.set({ "i", "n" }, "<C-n>", next_res, opts)
		vim.keymap.set({ "i", "n" }, "<Down>", next_res, opts)
		vim.keymap.set({ "i", "n" }, "<C-p>", prev_res, opts)
		vim.keymap.set({ "i", "n" }, "<Up>", prev_res, opts)
		if b ~= input_buf then
			vim.keymap.set("n", "j", next_res, opts)
			vim.keymap.set("n", "k", prev_res, opts)
			vim.keymap.set({ "i", "n" }, "q", close, opts)
		else
			vim.keymap.set("n", "q", close, opts)
			vim.keymap.set("n", "j", next_res, opts)
			vim.keymap.set("n", "k", prev_res, opts)
		end
	end

	-- window focus movement
	local function focus_input()
		vim.api.nvim_set_current_win(input_win)
		vim.cmd("startinsert")
	end
	local function focus_results()
		vim.api.nvim_set_current_win(results_win)
		vim.cmd("stopinsert")
	end
	local function focus_preview()
		vim.api.nvim_set_current_win(preview_win)
		vim.cmd("stopinsert")
	end

	do
		local ko = { noremap = true, silent = true, buffer = input_buf }
		vim.keymap.set({ "i", "n" }, "<C-j>", focus_results, ko)
		vim.keymap.set({ "i", "n" }, "<C-l>", focus_preview, ko)
	end
	do
		local ko = { noremap = true, silent = true, buffer = results_buf }
		vim.keymap.set({ "i", "n" }, "<C-k>", focus_input, ko)
		vim.keymap.set({ "i", "n" }, "<C-h>", focus_input, ko)
		vim.keymap.set({ "i", "n" }, "<C-l>", focus_preview, ko)
	end
	do
		local ko = { noremap = true, silent = true, buffer = preview_buf }
		vim.keymap.set({ "i", "n" }, "<C-h>", focus_results, ko)
		vim.keymap.set({ "i", "n" }, "<C-j>", focus_results, ko)
	end

	vim.api.nvim_buf_attach(input_buf, false, {
		on_lines = function()
			local raw_q = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""
			if raw_q:sub(1, 4) ~= " >  " then
				local fixed_q = " >  " .. raw_q:gsub("^%s*>?%s*", "")
				vim.schedule(function()
					vim.api.nvim_buf_set_lines(input_buf, 0, 1, false, { fixed_q })
					vim.api.nvim_win_set_cursor(input_win, { 1, #fixed_q })
					apply_prompt_hl()
				end)
				query = vim.trim(fixed_q:sub(5))
			else
				query = vim.trim(raw_q:sub(5))
				vim.schedule(apply_prompt_hl)
			end
			if timer then
				timer:stop()
			end
			timer = vim.defer_fn(function()
				run_rg(query)
			end, 150)
		end,
	})

	render_results()
end

local function buffer_picker(bufnr)
	local query = ""
	local results = {}
	local selected = 1
	local full_matches = {}
	local timer = nil
	local rendering = false -- guard: ignore on_lines during our own renders

	local file = vim.api.nvim_buf_get_name(bufnr)

	local file_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local lnum_width = #tostring(math.max(#file_lines, 1))
	for i, text in ipairs(file_lines) do
		full_matches[#full_matches + 1] = { file = file, lnum = i, col = 1, text = text or "" }
	end
	results = full_matches

	local ui = vim.api.nvim_list_uis()[1]
	local W = ui.width
	local win_width = math.min(54, math.floor(W * 0.27))
	local results_h = 7
	local total_h = 1 + 1 + results_h

	local origin_win = P.get_origin_win()
	local origin_pos = vim.api.nvim_win_get_position(origin_win)
	local origin_width = vim.api.nvim_win_get_width(origin_win)
	local row_pos = origin_pos[1]
	local col_pos = math.max(0, origin_pos[2] + origin_width - win_width - 2)

	setup_buf_hl()

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = win_width,
		height = total_h,
		row = row_pos,
		col = col_pos,
		style = "minimal",
		border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
		title = " Grep Buffer ",
		title_pos = "left",
		zindex = 50,
	})
	vim.wo[win].winhl = "Normal:RgBufNormal,FloatBorder:RgBufBorder,FloatTitle:RgBufTitle"
	vim.wo[win].foldenable = false
	vim.wo[win].cursorline = false
	vim.wo[win].wrap = false
	vim.wo[win].fillchars = "eob: "

	vim.b[buf].blink_cmp_disable = true
	vim.b[buf].completion = false
	vim.b[buf].cmp_disable = true

	local ns_prompt = vim.api.nvim_create_namespace("")
	local ns_sep = vim.api.nvim_create_namespace("")
	local ns_sel = vim.api.nvim_create_namespace("")
	local ns_cursor = vim.api.nvim_create_namespace("")
	local ns_lnum = vim.api.nvim_create_namespace("")
	local ns_icon = vim.api.nvim_create_namespace("")

	local PROMPT = " >  "
	-- Separator spans full inner width minus 1 for left margin
	local SEP = " " .. string.rep("─", win_width - 2)

	local function get_icon_data(fp)
		if not has_devicons then
			return "", "RgBufNormal"
		end
		local name = vim.fn.fnamemodify(fp, ":t")
		local ext = name:match("%.([^.]+)$") or ""
		local icon, hl = devicons.get_icon(name, ext, { default = true })
		return icon or "", hl or "RgBufNormal"
	end

	local function render()
		local disp = { PROMPT .. query, SEP }
		local hl_jobs = {}
		local max_len = win_width - 2
		local first_idx, last_idx = 1, #results

		if #results > 0 then
			first_idx = math.max(1, selected - results_h + 1)
			last_idx = math.min(#results, first_idx + results_h - 1)
		end

		if #results == 0 then
			disp[#disp + 1] = "   (no results)"
		else
			local icon, icon_hl = get_icon_data(file)
			local icon_str = icon ~= "" and (icon .. " ") or ""
			for i = first_idx, last_idx do
				local line = results[i]
				local lnum_n = line and line.lnum or 0
				local text = line and line.text or ""
				if lnum_n > 0 then
					local lnum_str = string.format("%" .. lnum_width .. "d", lnum_n)
					local text_str = text:gsub("^%s+", "")
					local full_str = "  " .. icon_str .. lnum_str .. "  " .. text_str
					local char_len = vim.fn.strchars(full_str)
					if char_len > max_len then
						full_str = vim.fn.strcharpart(full_str, 0, max_len - 1) .. "…"
					end
					disp[#disp + 1] = full_str

					-- 0-based buffer line index (0=prompt, 1=sep, 2+=results slice)
					local li = (i - first_idx) + 2
					local icon_s = 2
					local lnum_s = icon_s + #icon_str
					if icon ~= "" then
						hl_jobs[#hl_jobs + 1] = { li, ns_icon, icon_hl, icon_s, icon_s + #icon }
					end
					hl_jobs[#hl_jobs + 1] = { li, ns_lnum, "RgBufLnum", lnum_s, lnum_s + #lnum_str }
				else
					disp[#disp + 1] = "  " .. ((line and line.text) or "")
				end
			end
		end

		rendering = true
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, disp)
		rendering = false

		for _, ns in ipairs({ ns_prompt, ns_sep, ns_sel, ns_cursor, ns_lnum, ns_icon }) do
			vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		end

		vim.api.nvim_buf_add_highlight(buf, ns_prompt, "RgBufPrompt", 0, 1, 2)
		vim.api.nvim_buf_add_highlight(buf, ns_sep, "RgBufSep", 1, 0, -1)

		for _, h in ipairs(hl_jobs) do
			vim.api.nvim_buf_add_highlight(buf, h[2], h[3], h[1], h[4], h[5])
		end

		if #results > 0 and selected >= first_idx and selected <= last_idx then
			local li = (selected - first_idx) + 2 -- 0-based
			vim.api.nvim_buf_set_extmark(buf, ns_sel, li, 0, {
				hl_group = "RgBufSelected",
				hl_eol = true,
				end_row = li + 1,
				end_col = 0,
				priority = 100,
			})
		end

		-- Footer counter
		if #results > 0 then
			pcall(vim.api.nvim_win_set_config, win, {
				footer = string.format(" %d/%d ", selected, #results),
				footer_pos = "right",
			})
		else
			pcall(vim.api.nvim_win_set_config, win, { footer = "" })
		end

		pcall(vim.api.nvim_win_set_cursor, win, { 1, #PROMPT + #query })
	end

	local function filter_results(q)
		if q == "" then
			results = {}
			for _, match in ipairs(full_matches) do
				results[#results + 1] = { file = match.file, lnum = match.lnum, col = 1, text = match.text }
			end
		else
			local q_lower = q:lower()
			results = {}
			for _, match in ipairs(full_matches) do
				local text = match.text or ""
				if text:lower():find(q_lower, 1, true) then
					local start_col = text:lower():find(q_lower, 1, true) or 1
					results[#results + 1] = {
						file = match.file,
						lnum = match.lnum,
						col = start_col,
						text = match.text,
					}
				end
			end
		end
		selected = 1
		render()
	end

	local function close()
		pcall(vim.api.nvim_win_close, win, true)
		vim.cmd("stopinsert")
	end

	local function open_selected()
		if #results == 0 then
			return
		end
		local item = results[selected]
		if not item then
			return
		end
		local lnum_n = item.lnum or 1
		local col_n = math.max(0, (item.col or 1) - 1)
		close()
		vim.schedule(function()
			if item.file ~= "" then
				local abs = vim.fn.fnamemodify(item.file, ":p")
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_config(w).relative == "" then
						local wfile = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)), ":p")
						if wfile == abs then
							vim.api.nvim_set_current_win(w)
							vim.api.nvim_win_set_cursor(0, { lnum_n, col_n })
							vim.cmd("normal! zz")
							return
						end
					end
				end
				vim.cmd("edit " .. vim.fn.fnameescape(abs))
			else
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_config(w).relative == "" then
						if vim.api.nvim_win_get_buf(w) == bufnr then
							vim.api.nvim_set_current_win(w)
							vim.api.nvim_win_set_cursor(0, { lnum_n, col_n })
							vim.cmd("normal! zz")
							return
						end
					end
				end
				vim.api.nvim_set_current_buf(bufnr)
			end
			vim.api.nvim_win_set_cursor(0, { lnum_n, col_n })
			vim.cmd("normal! zz")
		end)
	end

	local function next_res()
		if selected < #results then
			selected = selected + 1
			render()
		end
	end
	local function prev_res()
		if selected > 1 then
			selected = selected - 1
			render()
		end
	end

	local opts = { noremap = true, silent = true, buffer = buf }
	vim.keymap.set({ "i", "n" }, "<CR>", open_selected, opts)
	vim.keymap.set({ "i", "n" }, "<C-n>", next_res, opts)
	vim.keymap.set({ "i", "n" }, "<Down>", next_res, opts)
	vim.keymap.set({ "i", "n" }, "<C-p>", prev_res, opts)
	vim.keymap.set({ "i", "n" }, "<Up>", prev_res, opts)
	vim.keymap.set({ "i", "n" }, "<Esc>", close, opts)
	vim.keymap.set("n", "q", close, opts)
	vim.keymap.set("n", "j", next_res, opts)
	vim.keymap.set("n", "k", prev_res, opts)

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		buffer = buf,
		callback = function()
			local pos = vim.api.nvim_win_get_cursor(0)
			local r, c = pos[1], pos[2]
			if r > 1 then
				vim.api.nvim_win_set_cursor(0, { 1, #PROMPT + #query })
			elseif c < #PROMPT then
				vim.api.nvim_win_set_cursor(0, { 1, #PROMPT })
			end
		end,
	})

	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function(_, _, _, firstline)
			if rendering then
				return
			end
			if firstline ~= 0 then
				return
			end
			local raw = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
			if raw:sub(1, #PROMPT) ~= PROMPT then
				query = vim.trim(raw:gsub("^%s*>?%s*", ""))
			else
				query = raw:sub(#PROMPT + 1)
			end
			if timer then
				timer:stop()
			end
			timer = vim.defer_fn(function()
				filter_results(query)
			end, 120)
		end,
	})

	render()
	vim.cmd("startinsert")
end

function M.rg()
	rg_picker(vim.fn.getcwd(), "Grep (fast)")
end

function M.rg_buffer()
	buffer_picker(vim.api.nvim_get_current_buf())
end

return M

