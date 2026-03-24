-- lua/snipe/picker.lua
-- Shared open_picker factory, highlight setup, and utility helpers.
-- Required by snipe.nav, snipe.search, and snipe.rg.

local M = {}

local has_devicons, devicons = pcall(require, "nvim-web-devicons")

-- ─── highlights ───────────────────────────────────────────────────────────────

function M.setup_hl()
	vim.api.nvim_set_hl(0, "NavNormal", { fg = "#c0caf5" })
	vim.api.nvim_set_hl(0, "NavBorder", { fg = "#27a1b9" })
	vim.api.nvim_set_hl(0, "NavTitle", { fg = "#ff9e64" })
	vim.api.nvim_set_hl(0, "NavSelected", { bg = "#2d3250", fg = "#c0caf5" })
	vim.api.nvim_set_hl(0, "NavCursor", { fg = "#7aa2f7" })
	vim.api.nvim_set_hl(0, "NavPreviewCur", { bg = "#e07840", fg = "#1a1b26" })
	vim.api.nvim_set_hl(0, "NavPreviewLine", { bg = "#1e2a3a", fg = "#c0caf5" })
	vim.api.nvim_set_hl(0, "NavPromptArrow", { fg = "#27a1b9" })
	vim.api.nvim_set_hl(0, "NavFilePath", { fg = "#c0caf5" })
	vim.api.nvim_set_hl(0, "NavLnum", { fg = "#73daca" })
	vim.api.nvim_set_hl(0, "NavResultsBg", { bg = "#1a1b26", fg = "#c0caf5" })
	vim.api.nvim_set_hl(0, "NavBackdrop", { bg = "#1a1b26", fg = "#1a1b26" })
	vim.api.nvim_set_hl(0, "NavMark", { fg = "#bb9af7" })
	vim.api.nvim_set_hl(0, "NavModified", { fg = "#e0af68" })
	vim.api.nvim_set_hl(0, "NavDiagE", { fg = "#f7768e" })
	vim.api.nvim_set_hl(0, "NavDiagW", { fg = "#e0af68" })
	vim.api.nvim_set_hl(0, "NavDiagI", { fg = "#73daca" })
	vim.api.nvim_set_hl(0, "NavDiagH", { fg = "#9ece6a" })
	vim.api.nvim_set_hl(0, "SrchKey", { fg = "#7aa2f7" })
	vim.api.nvim_set_hl(0, "SrchVal", { fg = "#9ece6a" })
	vim.api.nvim_set_hl(0, "SrchMode", { fg = "#bb9af7" })
	vim.api.nvim_set_hl(0, "SrchEvent", { fg = "#ff9e64" })
	vim.api.nvim_set_hl(0, "SrchGrp", { fg = "#73daca" })
	vim.api.nvim_set_hl(0, "SrchMatchCur", { bg = "#e07840", fg = "#1a1b26" })
	vim.api.nvim_set_hl(0, "SrchMatch", { bg = "#28344a", fg = "#c0caf5" })
	vim.api.nvim_set_hl(0, "SrchResultMatch", { bg = NONE, fg = "#7aa2f7" })
end

-- ─── utilities ────────────────────────────────────────────────────────────────

function M.get_icon(filepath)
	local name = vim.fn.fnamemodify(filepath, ":t")
	local ext = name:match("%.([^.]+)$") or ""
	if has_devicons then
		local icon, hl = devicons.get_icon(name, ext, { default = true })
		return icon or "", hl or "NavNormal"
	end
	return "", "NavNormal"
end

function M.filter(items, query, get_text)
	if query == "" then
		return items
	end
	local q = query:lower()
	local out = {}
	for _, item in ipairs(items) do
		if (get_text and get_text(item) or tostring(item)):lower():find(q, 1, true) then
			out[#out + 1] = item
		end
	end
	return out
end

function M.read_file(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	return ok and lines or nil
end

function M.jump_to(origin_win, filepath, lnum, col)
	local abs = vim.fn.fnamemodify(filepath, ":p")
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_config(w).relative == "" then
			local wb = vim.api.nvim_win_get_buf(w)
			if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(wb), ":p") == abs then
				vim.api.nvim_set_current_win(w)
				vim.api.nvim_win_set_cursor(0, { lnum or 1, col or 0 })
				vim.cmd("normal! zz")
				return
			end
		end
	end
	vim.api.nvim_set_current_win(origin_win)
	vim.cmd("edit " .. vim.fn.fnameescape(abs))
	vim.api.nvim_win_set_cursor(0, { lnum or 1, col or 0 })
	vim.cmd("normal! zz")
end

function M.git_root()
	local out = vim.trim(vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"))
	return (vim.v.shell_error == 0 and out ~= "") and out or vim.fn.getcwd()
end

function M.file_preview(path, focus_lnum)
	local lines = M.read_file(path)
	if not lines then
		return nil
	end
	local focus = (focus_lnum and focus_lnum > 1) and focus_lnum or nil
	return { lines = lines, syntax = vim.filetype.match({ filename = path }), focus_lnum = focus }
end

function M.render_file_row(filepath, lnum_str, extra, _max_len)
	local rel = vim.fn.fnamemodify(filepath, ":.")
	local icon, icon_hl = M.get_icon(filepath)
	local prefix = "   " .. icon .. " "
	local lnum_part = lnum_str and (":" .. lnum_str) or ""
	local extra_part = extra and ("  " .. extra) or ""
	local text = prefix .. rel .. lnum_part .. extra_part
	local icon_s = 3
	local icon_e = icon_s + #icon
	local rel_s = icon_e + 1
	local rel_e = rel_s + #rel
	local lnum_e = rel_e + #lnum_part
	return {
		text = text,
		highlights = {
			{ icon_s, icon_e, icon_hl },
			{ rel_s, rel_e, "NavFilePath" },
			{ rel_e, lnum_e, "NavLnum" },
		},
	}
end

-- ─── open_picker factory ──────────────────────────────────────────────────────
--
-- opts:
--   title         string
--   all_items     list
--   filter_items  fn(all, query) -> list
--   get_items     fn(query, cb)      (async; live=true)
--   live          bool
--   initial_query string
--   render_item   fn(item, max_len) -> { text, highlights, match_hl? }
--   preview_item  fn(item) -> { lines, syntax?, focus_lnum?, highlight_query?, match_col? }
--   open_item     fn(item, origin_win)

function M.open_picker(opts)
	M.setup_hl()

	local all_items = opts.all_items or {}
	local filtered = all_items
	local selected = 1
	local query = opts.initial_query or ""

	local origin_win = (function()
		local best, best_score = nil, -1
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_config(w).relative == "" then
				local buf = vim.api.nvim_win_get_buf(w)
				local score = 0
				if vim.bo[buf].buftype == "" then
					score = score + 10
				end
				if vim.bo[buf].buflisted then
					score = score + 2
				end
				if vim.api.nvim_buf_get_name(buf) ~= "" then
					score = score + 1
				end
				if score > best_score then
					best, best_score = w, score
				end
			end
		end
		return best or vim.api.nvim_get_current_win()
	end)()

	local ui = vim.api.nvim_list_uis()[1]
	local W, H = ui.width, ui.height

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
	vim.wo[backdrop_win].winhl = "Normal:NavBackdrop"
	vim.wo[backdrop_win].foldenable = false
	vim.b[backdrop_buf].blink_cmp_disable = true

	local box_w = math.floor(W * 0.90)
	local box_h = math.floor(H * 0.85)
	local box_row = math.floor((H - box_h) / 2) - 1
	local box_col = math.floor((W - box_w) / 2)

	local left_w = math.floor(box_w * 0.45)
	local right_w = box_w - left_w - 1
	local input_outer = 3
	local results_h = box_h - input_outer - 1

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
		vim.wo[win].winhl = "Normal:NavNormal,FloatBorder:NavBorder,FloatTitle:NavTitle"
		vim.wo[win].foldenable = false
		vim.wo[win].cursorline = false
		vim.wo[win].fillchars = "eob: "
		return buf, win
	end

	local function set_ro(buf, lines)
		vim.bo[buf].modifiable = true
		local clean = {}
		for _, l in ipairs(lines) do
			clean[#clean + 1] = l:gsub("\r", "")
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, clean)
		vim.bo[buf].modifiable = false
	end

	local input_buf, input_win = make_win(left_w, 1, box_row, box_col, nil, 55)
	vim.wo[input_win].winhl = "Normal:NavNormal,FloatBorder:NavPromptArrow,FloatTitle:NavTitle"
	local prompt_text = " >  " .. query
	vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { prompt_text })

	local ns_prompt = vim.api.nvim_create_namespace("snipe_prompt")
	local function apply_prompt_hl()
		vim.api.nvim_buf_clear_namespace(input_buf, ns_prompt, 0, -1)
		vim.api.nvim_buf_add_highlight(input_buf, ns_prompt, "NavPromptArrow", 0, 1, 2)
	end
	apply_prompt_hl()
	vim.api.nvim_win_set_cursor(input_win, { 1, #prompt_text })

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		buffer = input_buf,
		callback = function()
			if vim.api.nvim_win_get_cursor(0)[2] < 4 then
				vim.api.nvim_win_set_cursor(0, { 1, 4 })
			end
		end,
	})

	local results_buf, results_win =
		make_win(left_w, results_h, box_row + input_outer, box_col, opts.title or "Results", 50)
	vim.wo[results_win].wrap = false
	vim.bo[results_buf].modifiable = false
	vim.wo[results_win].winhl = "Normal:NavResultsBg,FloatBorder:NavBorder,FloatTitle:NavTitle"

	local preview_buf, preview_win = make_win(right_w - 3, box_h - 1, box_row, box_col + left_w + 2, "Preview", 50)
	vim.wo[preview_win].wrap = false
	vim.wo[preview_win].scrolloff = 5
	vim.wo[preview_win].sidescrolloff = 0
	vim.wo[preview_win].list = true
	vim.wo[preview_win].listchars = "extends:…,precedes:…,tab:  "
	vim.bo[preview_buf].modifiable = false

	for _, b in ipairs({ input_buf, results_buf, preview_buf, backdrop_buf }) do
		vim.b[b].blink_cmp_disable = true
		vim.b[b].completion = false
		vim.b[b].cmp_disable = true
	end

	vim.api.nvim_set_current_win(input_win)
	vim.cmd("startinsert")

	local ns_sel = vim.api.nvim_create_namespace("snipe_sel")
	local ns_cur = vim.api.nvim_create_namespace("snipe_cur")
	local ns_hl = vim.api.nvim_create_namespace("snipe_hl")
	local ns_match = vim.api.nvim_create_namespace("snipe_match")
	local ns_prev = vim.api.nvim_create_namespace("snipe_prev")
	local ns_prev_cur = vim.api.nvim_create_namespace("snipe_prev_cur")

	local timer = nil
	local preview_timer = nil
	local row_hls = {}

	-- ── preview ──────────────────────────────────────────────────────────────────

	local function update_preview()
		vim.api.nvim_buf_clear_namespace(preview_buf, ns_prev, 0, -1)
		vim.api.nvim_buf_clear_namespace(preview_buf, ns_prev_cur, 0, -1)

		if #filtered == 0 or not filtered[selected] then
			set_ro(preview_buf, {})
			return
		end

		local pdata = opts.preview_item and opts.preview_item(filtered[selected])
		if not pdata then
			set_ro(preview_buf, { " (no preview)" })
			return
		end

		local raw_lines = pdata.lines or {}
		local padded = {}
		for i, v in ipairs(raw_lines) do
			padded[i] = " " .. v:gsub("\t", "    ")
		end
		set_ro(preview_buf, padded)

		if pdata.syntax and pdata.syntax ~= "" then
			pcall(function()
				vim.bo[preview_buf].syntax = pdata.syntax
			end)
		end

		local focus = pdata.focus_lnum
		local hq = pdata.highlight_query

		if focus and focus >= 1 and focus <= #padded then
			local win_w = vim.api.nvim_win_get_width(preview_win)
			local win_h = vim.api.nvim_win_get_height(preview_win)

			if hq and hq ~= "" then
				local raw = raw_lines[focus] or ""
				local col_n = pdata.match_col or 0
				local target = col_n > 0 and (col_n - 1) or 0
				local transformed, bi = 0, 1
				while bi <= #raw and (bi - 1) < target do
					transformed = transformed + (raw:sub(bi, bi) == "\t" and 4 or 1)
					bi = bi + 1
				end
				local match_col = transformed + 1
				local cur_leftcol = tonumber(
					vim.fn.win_execute(preview_win, "echo winsaveview()['leftcol']"):match("%d+")
				) or 0
				local match_visible = match_col >= cur_leftcol and match_col < cur_leftcol + win_w - 2
				local leftcol = match_visible and cur_leftcol or math.max(0, match_col - math.floor(win_w / 2))
				local topline = math.max(1, focus - math.floor(win_h / 2))
				vim.fn.win_execute(
					preview_win,
					string.format(
						"call winrestview({'lnum':%d,'col':%d,'leftcol':%d,'topline':%d})",
						focus,
						match_col,
						leftcol,
						topline
					)
				)
				local topline_eff = math.max(1, focus - math.floor(win_h / 2))
				local bottom = math.min(#padded, topline_eff + win_h - 1)
				local visible_matches = 0
				for i = topline_eff, bottom do
					local s = 0
					while true do
						local m = vim.fn.matchstrpos(padded[i] or "", hq, s, 1)
						if m[2] == -1 then
							break
						end
						visible_matches = visible_matches + 1
						s = m[3]
					end
				end
				if visible_matches > 1 then
					for i = topline_eff, bottom do
						if i ~= focus then
							local s = 0
							while true do
								local m = vim.fn.matchstrpos(padded[i] or "", hq, s, 1)
								if m[2] == -1 then
									break
								end
								vim.api.nvim_buf_add_highlight(preview_buf, ns_prev, "SrchMatch", i - 1, m[2], m[3])
								s = m[3]
							end
						end
					end
				end
				if padded[focus] then
					local match_str = vim.fn.matchstr(padded[focus], hq, match_col)
					local match_end = match_col - 1 + #match_str
					if #match_str > 0 then
						vim.api.nvim_buf_set_extmark(preview_buf, ns_prev_cur, focus - 1, match_col, {
							end_col = match_end + 1,
							hl_group = "SrchMatchCur",
							priority = 200,
						})
					end
				end
			else
				local topline = math.max(1, focus - math.floor(win_h / 2))
				vim.fn.win_execute(
					preview_win,
					string.format("call winrestview({'lnum':%d,'topline':%d})", focus, topline)
				)
				for _, offset in ipairs({ -2, -1, 1, 2 }) do
					local ln = focus + offset - 1
					if ln >= 0 and ln < #padded then
						vim.api.nvim_buf_add_highlight(preview_buf, ns_prev, "NavPreviewLine", ln, 1, -1)
					end
				end
				vim.api.nvim_buf_add_highlight(preview_buf, ns_prev, "NavPreviewCur", focus - 1, 1, -1)
			end
		end
	end

	-- ── results ──────────────────────────────────────────────────────────────────

	local function highlight_selected()
		vim.api.nvim_buf_clear_namespace(results_buf, ns_sel, 0, -1)
		vim.api.nvim_buf_clear_namespace(results_buf, ns_cur, 0, -1)
		if #filtered > 0 and filtered[selected] then
			vim.api.nvim_buf_set_extmark(results_buf, ns_sel, selected - 1, 0, {
				hl_group = "NavSelected",
				hl_eol = true,
				end_row = selected,
				end_col = 0,
				priority = 100,
			})
			vim.api.nvim_buf_set_extmark(results_buf, ns_cur, selected - 1, 0, {
				virt_text = { { " > ", "NavCursor" } },
				virt_text_pos = "overlay",
				hl_mode = "combine",
			})
			pcall(vim.api.nvim_win_set_cursor, results_win, { selected, 0 })
		end
		vim.api.nvim_win_set_config(results_win, {
			footer = string.format(" %d/%d ", selected, #filtered),
			footer_pos = "right",
		})
		if preview_timer then
			preview_timer:stop()
		end
		preview_timer = vim.defer_fn(update_preview, 80)
	end

	local function render_results()
		vim.api.nvim_buf_clear_namespace(results_buf, ns_hl, 0, -1)
		vim.api.nvim_buf_clear_namespace(results_buf, ns_match, 0, -1)
		row_hls = {}
		local max_len = left_w - 3
		local display = {}
		for i, item in ipairs(filtered) do
			local rdata = opts.render_item and opts.render_item(item, max_len) or { text = tostring(item) }
			local text = rdata.text or ""
			local char_len = vim.fn.strchars(text)
			if char_len > max_len then
				text = vim.fn.strcharpart(text, 0, max_len - 1) .. "…"
			elseif char_len < max_len then
				text = text .. string.rep(" ", max_len - char_len)
			end
			display[i] = text
			row_hls[i] = rdata.highlights or {}
		end
		if #filtered == 0 then
			display = { "   (no results)" }
		end
		set_ro(results_buf, display)
		for i, hls in pairs(row_hls) do
			for _, h in ipairs(hls) do
				vim.api.nvim_buf_add_highlight(results_buf, ns_hl, h[3], i - 1, h[1], h[2])
			end
		end
		for i, item in ipairs(filtered) do
			local rdata = opts.render_item and opts.render_item(item, max_len) or {}
			if rdata.match_hl then
				for _, mh in ipairs(rdata.match_hl) do
					vim.api.nvim_buf_add_highlight(results_buf, ns_match, mh[3], i - 1, mh[1], mh[2])
				end
			end
		end
		highlight_selected()
	end

	-- ── actions ───────────────────────────────────────────────────────────────────

	local function close()
		pcall(vim.api.nvim_win_close, backdrop_win, true)
		pcall(vim.api.nvim_win_close, input_win, true)
		pcall(vim.api.nvim_win_close, results_win, true)
		pcall(vim.api.nvim_win_close, preview_win, true)
		vim.cmd("stopinsert")
	end

	local function open_selected()
		if #filtered == 0 or not filtered[selected] then
			return
		end
		local item = filtered[selected]
		close()
		vim.schedule(function()
			if opts.open_item then
				opts.open_item(item, origin_win)
			end
		end)
	end

	local function next_res()
		if selected < #filtered then
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
		local ko = { noremap = true, silent = true, buffer = b }
		vim.keymap.set({ "i", "n" }, "<CR>", open_selected, ko)
		vim.keymap.set({ "i", "n" }, "<C-n>", next_res, ko)
		vim.keymap.set({ "i", "n" }, "<Down>", next_res, ko)
		vim.keymap.set({ "i", "n" }, "<C-p>", prev_res, ko)
		vim.keymap.set({ "i", "n" }, "<Up>", prev_res, ko)
		if b ~= input_buf then
			vim.keymap.set("n", "j", next_res, ko)
			vim.keymap.set("n", "k", prev_res, ko)
			vim.keymap.set({ "i", "n" }, "q", close, ko)
		else
			vim.keymap.set("n", "q", close, ko)
			vim.keymap.set("n", "j", next_res, ko)
			vim.keymap.set("n", "k", prev_res, ko)
		end
	end

	-- ── window focus movement (Ctrl+hjkl) ────────────────────────────────────────
	local function focus(win)
		return function()
			vim.api.nvim_set_current_win(win)
			if win == input_win then
				vim.cmd("startinsert")
			else
				vim.cmd("stopinsert")
			end
		end
	end
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

	-- from input
	do
		local ko = { noremap = true, silent = true, buffer = input_buf }
		vim.keymap.set({ "i", "n" }, "<C-j>", focus_results, ko)
		vim.keymap.set({ "i", "n" }, "<C-l>", focus_preview, ko)
		-- Prevent fallback for <C-h> and <C-k>
		vim.keymap.set({ "i", "n" }, "<C-h>", function() end, ko)
		vim.keymap.set({ "i", "n" }, "<C-k>", function() end, ko)
	end
	-- from results
	do
		local ko = { noremap = true, silent = true, buffer = results_buf }
		vim.keymap.set({ "i", "n" }, "<C-k>", focus_input, ko)
		vim.keymap.set({ "i", "n" }, "<C-h>", focus_input, ko)
		vim.keymap.set({ "i", "n" }, "<C-l>", focus_preview, ko)
		-- Prevent fallback for <C-j>
		vim.keymap.set({ "i", "n" }, "<C-j>", function() end, ko)
	end
	-- from preview
	do
		local ko = { noremap = true, silent = true, buffer = preview_buf }
		vim.keymap.set({ "i", "n" }, "<C-h>", focus_results, ko)
		vim.keymap.set({ "i", "n" }, "<C-j>", focus_results, ko)
		-- Prevent fallback for <C-k> and <C-l>
		vim.keymap.set({ "i", "n" }, "<C-k>", function() end, ko)
		vim.keymap.set({ "i", "n" }, "<C-l>", function() end, ko)
	end

	-- ── preview window scrolling with arrow keys ─────────────────────────────────
	local function scroll_preview(delta)
		local view = vim.fn.winsaveview()
		local new_top = view.topline + delta
		new_top = math.max(1, math.min(new_top, vim.fn.line("$")))
		view.topline = new_top
		vim.fn.winrestview(view)
	end
	local ko_preview = { noremap = true, silent = true, buffer = preview_buf }
	vim.keymap.set("n", "<Up>", function()
		scroll_preview(-1)
	end, ko_preview)
	vim.keymap.set("n", "<Down>", function()
		scroll_preview(1)
	end, ko_preview)
	local win_height = vim.api.nvim_win_get_height(preview_win)
	vim.keymap.set("n", "<PageUp>", function()
		scroll_preview(-win_height)
	end, ko_preview)
	vim.keymap.set("n", "<PageDown>", function()
		scroll_preview(win_height)
	end, ko_preview)

	vim.api.nvim_buf_attach(input_buf, false, {
		on_lines = function()
			local raw = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""
			if raw:sub(1, 4) ~= " >  " then
				local fixed = " >  " .. raw:gsub("^%s*>?%s*", "")
				vim.schedule(function()
					vim.api.nvim_buf_set_lines(input_buf, 0, 1, false, { fixed })
					vim.api.nvim_win_set_cursor(input_win, { 1, #fixed })
					apply_prompt_hl()
				end)
				query = vim.trim(fixed:sub(5))
			else
				query = vim.trim(raw:sub(5))
				vim.schedule(apply_prompt_hl)
			end
			if timer then
				timer:stop()
			end
			timer = vim.defer_fn(function()
				if opts.live and opts.get_items then
					opts.get_items(query, function(items)
						filtered = items
						selected = 1
						vim.schedule(render_results)
					end)
				else
					filtered = opts.filter_items and opts.filter_items(all_items, query) or all_items
					selected = 1
					render_results()
				end
			end, 120)
		end,
	})

	if opts.live and opts.get_items then
		set_ro(results_buf, { "   (loading…)" })
		opts.get_items(query, function(items)
			filtered = items
			selected = 1
			vim.schedule(render_results)
		end)
	else
		filtered = all_items
		render_results()
	end
end

return M
