-- lua/snipe/search.lua
-- Grep, autocmds, command history, commands, help, highlights, icons,
-- jumps, keymaps, location list, man pages, plugins, quickfix, registers,
-- search history, undo history, noice history.

local M = {}

local P = require("snipe.picker")

local function open_picker(opts)
	P.open_picker(opts)
end
local function get_icon(f)
	return P.get_icon(f)
end
local function filter(...)
	return P.filter(...)
end
local function read_file(p)
	return P.read_file(p)
end
local function jump_to(...)
	P.jump_to(...)
end
local function git_root()
	return P.git_root()
end

local has_devicons, devicons = pcall(require, "nvim-web-devicons")

-- Helper to ensure icon highlight group exists
local function ensure_icon_hl(name, color)
	local hl_name = "DevIcon" .. name
	if vim.fn.hlexists(hl_name) == 0 then
		vim.api.nvim_set_hl(0, hl_name, { fg = color })
	end
end

-- ── Grep ──────────────────────────────────────────────────────────────────────

local function grep_picker(title, search_dir, initial_word)
	local current_query = initial_word or ""
	open_picker({
		title = title,
		live = true,
		initial_query = initial_word,
		get_items = function(q, cb)
			current_query = q
			if #q < 2 then
				cb({})
				return
			end
			vim.fn.jobstart({ "rg", "--vimgrep", "--smart-case", "--color=never", q, search_dir }, {
				stdout_buffered = true,
				on_stdout = function(_, data)
					local items = {}
					for _, line in ipairs(data or {}) do
						if line ~= "" then
							local file, lnum, col, text = line:match("^(.+):(%d+):(%d+):(.*)")
							if file then
								items[#items + 1] =
									{ file = file, lnum = tonumber(lnum), col = tonumber(col) - 1, text = text }
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
			local icon, icon_hl = get_icon(item.file)
			local prefix = "   " .. icon .. " "
			local lnum_part = ":" .. item.lnum
			local snippet = item.text:gsub("^%s+", ""):sub(1, 50)
			local text = prefix .. rel .. lnum_part .. "  " .. snippet
			local ic_s, ic_e = 3, 3 + #icon
			local rel_s, rel_e = ic_e + 1, ic_e + 1 + #rel
			local snip_start = rel_e + #lnum_part + 2
			local match_hl = {}
			local q = current_query
			if q ~= "" then
				local s = 0
				while true do
					local m = vim.fn.matchstrpos(snippet, q, s, 1)
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
					{ rel_s, rel_e, "NavFilePath" },
					{ rel_e, rel_e + #lnum_part, "NavLnum" },
				},
				match_hl = match_hl,
			}
		end,
		preview_item = function(item)
			local lines = read_file(item.file)
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
		open_item = function(item, ow)
			jump_to(ow, item.file, item.lnum, item.col)
		end,
	})
end

-- ── Autocmds ──────────────────────────────────────────────────────────────────

local function autocmds_picker()
	local ok, acs = pcall(vim.api.nvim_get_autocmds, {})
	if not ok then
		return
	end
	local items = {}
	for _, ac in ipairs(acs) do
		items[#items + 1] = {
			event = ac.event or "",
			group = ac.group_name or "",
			pattern = ac.pattern or "*",
			buflocal = ac.buflocal or false,
			desc = ac.desc or (type(ac.callback) == "function" and "<lua fn>" or tostring(ac.command or "")),
		}
	end
	open_picker({
		title = "Autocmds",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.event .. " " .. it.group .. " " .. it.pattern .. " " .. it.desc
			end)
		end,
		render_item = function(item, _)
			local grp = item.group ~= "" and (" [" .. item.group .. "]") or ""
			local pat = "  " .. item.pattern
			local desc = "  " .. item.desc:sub(1, 40)
			local text = "   " .. item.event .. grp .. pat .. desc
			local ev_s, ev_e = 3, 3 + #item.event
			local grp_e = ev_e + #grp
			return {
				text = text,
				highlights = {
					{ ev_s, ev_e, "SrchEvent" },
					{ ev_e, grp_e, "SrchGrp" },
					{ grp_e, grp_e + #pat, "NavLnum" },
				},
			}
		end,
		preview_item = function(item)
			return {
				lines = {
					"  Event    : " .. item.event,
					"  Group    : " .. (item.group ~= "" and item.group or "(none)"),
					"  Pattern  : " .. item.pattern,
					"  BufLocal : " .. tostring(item.buflocal),
					"",
					"  Callback / Command:",
					"  " .. item.desc,
				},
			}
		end,
		open_item = function() end,
	})
end

-- ── Command History ───────────────────────────────────────────────────────────

local function cmdhistory_picker()
	local items = {}
	for i = -1, -200, -1 do
		local h = vim.fn.histget("cmd", i)
		if h == "" then
			break
		end
		items[#items + 1] = h
	end
	open_picker({
		title = "Command History",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q)
		end,
		render_item = function(item, _)
			return { text = "   : " .. item, highlights = { { 3, 4, "SrchKey" } } }
		end,
		preview_item = function(item)
			return { lines = { "", "  :" .. item, "" }, syntax = "vim" }
		end,
		open_item = function(item, ow)
			vim.api.nvim_set_current_win(ow)
			vim.fn.histadd("cmd", item)
			vim.fn.feedkeys(":" .. item, "n")
		end,
	})
end

-- ── Commands ──────────────────────────────────────────────────────────────────

local function commands_picker()
	local items = {}
	local function add(cmds)
		for name, def in pairs(cmds) do
			items[#items + 1] = {
				name = name,
				bang = def.bang,
				nargs = tostring(def.nargs or "0"),
				desc = def.definition or def.desc or "",
				buffer = def.buffer or false,
			}
		end
	end
	add(vim.api.nvim_get_commands({}))
	pcall(function()
		add(vim.api.nvim_buf_get_commands(0, {}))
	end)
	table.sort(items, function(a, b)
		return a.name < b.name
	end)
	open_picker({
		title = "Commands",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.name .. " " .. it.desc
			end)
		end,
		render_item = function(item, _)
			local bang = item.bang and "!" or " "
			local text = "   :" .. item.name .. bang .. "  " .. item.desc:sub(1, 50)
			local name_e = 4 + #item.name + 1
			return { text = text, highlights = { { 3, 4, "SrchKey" }, { 4, name_e, "SrchVal" } } }
		end,
		preview_item = function(item)
			return {
				lines = {
					"  Name   : " .. item.name,
					"  Bang   : " .. tostring(item.bang),
					"  Nargs  : " .. item.nargs,
					"  Buffer : " .. tostring(item.buffer),
					"",
					"  Definition:",
					"  " .. item.desc,
				},
				syntax = "vim",
			}
		end,
		open_item = function(item, ow)
			vim.api.nvim_set_current_win(ow)
			vim.fn.feedkeys(":" .. item.name .. " ", "n")
		end,
	})
end

-- ── Help Pages ────────────────────────────────────────────────────────────────

local function help_picker()
	local items = {}
	for _, t in ipairs(vim.fn.getcompletion("", "help")) do
		if t ~= "" then
			items[#items + 1] = t
		end
	end
	local tag_cache = {}
	local function find_tag(tag)
		if tag_cache[tag] then
			return tag_cache[tag]
		end
		for _, tf in ipairs(vim.fn.globpath(vim.o.runtimepath, "doc/tags", false, true)) do
			local tlines = read_file(tf)
			if tlines then
				for _, tl in ipairs(tlines) do
					local t, f = tl:match("^([^\t]+)\t([^\t]+)\t")
					if t == tag then
						tag_cache[tag] = { file = vim.fn.fnamemodify(tf, ":h") .. "/" .. f }
						return tag_cache[tag]
					end
				end
			end
		end
	end
	open_picker({
		title = "Help Pages",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q)
		end,
		render_item = function(item, _)
			return { text = "   ? " .. item, highlights = { { 3, 5, "SrchKey" } } }
		end,
		preview_item = function(item)
			local info = find_tag(item)
			if not info then
				return { lines = { " (preview unavailable)" } }
			end
			local hlines = read_file(info.file)
			if not hlines then
				return { lines = { " (cannot read help file)" } }
			end
			local focus = 1
			for i, hl in ipairs(hlines) do
				if hl:find(vim.pesc(item), 1, false) then
					focus = i
					break
				end
			end
			return { lines = hlines, syntax = "help", focus_lnum = focus > 1 and focus or nil }
		end,
		open_item = function(item, _)
			vim.cmd("help " .. vim.fn.fnameescape(item))
		end,
	})
end

-- ── Highlights ────────────────────────────────────────────────────────────────

local function highlights_picker()
	local function col_to_hex(n)
		return (n and type(n) == "number") and string.format("#%06x", n) or "none"
	end
	local items = {}
	for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
		items[#items + 1] = {
			name = name,
			fg = col_to_hex(hl.fg),
			bg = col_to_hex(hl.bg),
			bold = hl.bold,
			italic = hl.italic,
			underline = hl.underline,
			link = hl.link,
		}
	end
	table.sort(items, function(a, b)
		return a.name < b.name
	end)
	open_picker({
		title = "Highlights",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.name .. " " .. (it.link or "")
			end)
		end,
		render_item = function(item, _)
			local attrs = {}
			if item.bold then
				attrs[#attrs + 1] = "bold"
			end
			if item.italic then
				attrs[#attrs + 1] = "italic"
			end
			if item.underline then
				attrs[#attrs + 1] = "underline"
			end
			local attr_str = #attrs > 0 and (" [" .. table.concat(attrs, ",") .. "]") or ""
			local link_str = item.link and (" → " .. item.link) or ""
			local color_str = item.fg ~= "none" and ("  fg=" .. item.fg) or ""
			return {
				text = "   " .. item.name .. attr_str .. color_str .. link_str,
				highlights = { { 3, 3 + #item.name, item.name } },
			}
		end,
		preview_item = function(item)
			return {
				lines = {
					"  Name      : " .. item.name,
					"  Foreground: " .. item.fg,
					"  Background: " .. item.bg,
					"  Bold      : " .. tostring(item.bold or false),
					"  Italic    : " .. tostring(item.italic or false),
					"  Underline : " .. tostring(item.underline or false),
					"  Link      : " .. (item.link or "(none)"),
				},
			}
		end,
		open_item = function(item, _)
			vim.fn.setreg("+", item.name)
			vim.notify("Yanked: " .. item.name, vim.log.levels.INFO)
		end,
	})
end

-- ── Icons ─────────────────────────────────────────────────────────────────────

local function icons_picker()
	if not has_devicons then
		vim.notify("nvim-web-devicons not available", vim.log.levels.WARN)
		return
	end
	local items = {}
	for name, data in pairs(devicons.get_icons()) do
		ensure_icon_hl(data.name, data.color) -- Ensure highlight group exists
		items[#items + 1] = {
			name = name,
			icon = data.icon or "",
			color = data.color or "#ffffff",
			hl = data.name and ("DevIcon" .. data.name) or "NavNormal",
		}
	end
	table.sort(items, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
	open_picker({
		title = "Icons",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.name .. " " .. it.icon
			end)
		end,
		render_item = function(item, _)
			return { text = "   " .. item.icon .. "  " .. item.name, highlights = { { 3, 3 + #item.icon, item.hl } } }
		end,
		preview_item = function(item)
			-- Note: snipe.picker does not support custom highlights in preview,
			-- so the icon will not be colored in the preview.
			return {
				lines = {
					"",
					"   " .. item.icon .. "  " .. item.name,
					"",
					"  Extension : " .. item.name,
					"  Color     : " .. item.color,
					"  Highlight : " .. item.hl,
				},
			}
		end,
		open_item = function(item, _)
			vim.fn.setreg("+", item.icon)
			vim.notify("Yanked icon: " .. item.icon, vim.log.levels.INFO)
		end,
	})
end

-- ── Jumps ─────────────────────────────────────────────────────────────────────

local function jumps_picker()
	local jl_result = vim.fn.getjumplist()
	local jumplist, curpos = jl_result[1], jl_result[2]
	local items = {}
	for i = #jumplist, 1, -1 do
		local j = jumplist[i]
		local filepath = vim.api.nvim_buf_get_name(j.bufnr)
		if filepath ~= "" then
			items[#items + 1] = { file = filepath, lnum = j.lnum, col = j.col, is_cur = ((i - 1) == curpos) }
		end
	end
	open_picker({
		title = "Jumps",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.file
			end)
		end,
		render_item = function(item, _)
			local rel = vim.fn.fnamemodify(item.file, ":.")
			local icon, icon_hl = get_icon(item.file)
			local cur = item.is_cur and " ● " or "   "
			local text = cur .. icon .. " " .. rel .. ":" .. item.lnum
			local ic_s, ic_e = #cur, #cur + #icon
			return {
				text = text,
				highlights = {
					{ 0, ic_s, item.is_cur and "NavCursor" or "NavNormal" },
					{ ic_s, ic_e, icon_hl },
					{ ic_e + 1, ic_e + 1 + #rel, "NavFilePath" },
					{ ic_e + 1 + #rel, ic_e + 1 + #rel + 1 + #tostring(item.lnum), "NavLnum" },
				},
			}
		end,
		preview_item = function(item)
			local lines = read_file(item.file)
			if not lines then
				return nil
			end
			return {
				lines = lines,
				syntax = vim.filetype.match({ filename = item.file }),
				focus_lnum = item.lnum > 1 and item.lnum or nil,
			}
		end,
		open_item = function(item, ow)
			jump_to(ow, item.file, item.lnum, item.col)
		end,
	})
end

-- ── Keymaps ───────────────────────────────────────────────────────────────────

local function keymaps_picker()
	local items = {}
	for _, mode in ipairs({ "n", "i", "v", "x", "s", "o", "t", "c" }) do
		for _, km in ipairs(vim.api.nvim_get_keymap(mode)) do
			items[#items + 1] = {
				mode = mode,
				lhs = km.lhs,
				rhs = km.rhs or "",
				desc = km.desc or "",
				noremap = km.noremap == 1,
				silent = km.silent == 1,
				is_buf = false,
			}
		end
		for _, km in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
			items[#items + 1] = {
				mode = mode,
				lhs = km.lhs,
				rhs = km.rhs or "",
				desc = km.desc or "",
				noremap = km.noremap == 1,
				silent = km.silent == 1,
				is_buf = true,
			}
		end
	end
	table.sort(items, function(a, b)
		if a.mode ~= b.mode then
			return a.mode < b.mode
		end
		return a.lhs < b.lhs
	end)
	local mapleader = vim.g.mapleader or "\\"
	local function fmt_lhs(lhs)
		return lhs:gsub(" ", "<leader>"):gsub(mapleader, "<leader>")
	end
	open_picker({
		title = "Keymaps",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.mode .. " " .. it.lhs .. " " .. it.desc .. " " .. it.rhs
			end)
		end,
		render_item = function(item, _)
			local mode_str = "[" .. item.mode .. "]"
			local buf_str = item.is_buf and "B " or "  "
			local lhs_disp = fmt_lhs(item.lhs)
			local desc_str = item.desc ~= "" and item.desc or item.rhs
			local text = "   " .. mode_str .. " " .. buf_str .. lhs_disp .. "  " .. desc_str
			local ms, me = 3, 3 + #mode_str
			local ls, le = me + 1 + #buf_str, me + 1 + #buf_str + #lhs_disp
			return { text = text, highlights = { { ms, me, "SrchMode" }, { ls, le, "SrchKey" } } }
		end,
		preview_item = function(item)
			return {
				lines = {
					"  Mode    : " .. item.mode,
					"  LHS     : " .. fmt_lhs(item.lhs),
					"  RHS     : " .. (item.rhs ~= "" and item.rhs or "(lua callback)"),
					"  Desc    : " .. (item.desc ~= "" and item.desc or "(none)"),
					"  NoRemap : " .. tostring(item.noremap),
					"  Silent  : " .. tostring(item.silent),
					"  Buffer  : " .. tostring(item.is_buf),
				},
			}
		end,
		open_item = function(item, ow)
			vim.api.nvim_set_current_win(ow)
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(item.lhs, true, false, true), item.mode, false)
		end,
	})
end

-- ── Location List ─────────────────────────────────────────────────────────────

local function loclist_picker()
	local raw = vim.fn.getloclist(0)
	if #raw == 0 then
		vim.notify("Location list is empty", vim.log.levels.INFO)
		return
	end
	local items = {}
	local SEV_HL = { E = "NavDiagE", W = "NavDiagW", I = "NavDiagI", N = "NavDiagH" }
	for _, item in ipairs(raw) do
		local filepath = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
		if filepath ~= "" then
			items[#items + 1] = {
				file = filepath,
				lnum = item.lnum,
				col = math.max(0, (item.col or 1) - 1),
				text = vim.trim(item.text or ""),
				type = item.type or "",
			}
		end
	end
	open_picker({
		title = "Location List",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.file .. " " .. it.text
			end)
		end,
		render_item = function(item, _)
			local rel = vim.fn.fnamodify(item.file, ":.")
			local icon, icon_hl = get_icon(item.file)
			local sev = item.type ~= "" and ("[" .. item.type .. "] ") or ""
			local text = "   " .. icon .. " " .. rel .. ":" .. item.lnum .. "  " .. sev .. item.text:sub(1, 40)
			local ic_s, ic_e = 3, 3 + #icon
			local rel_s, rel_e = ic_e + 1, ic_e + 1 + #rel
			local lnum_e = rel_e + 1 + #tostring(item.lnum)
			return {
				text = text,
				highlights = {
					{ ic_s, ic_e, icon_hl },
					{ rel_s, rel_e, "NavFilePath" },
					{ rel_e, lnum_e, "NavLnum" },
					{ lnum_e + 2, lnum_e + 2 + #sev, SEV_HL[item.type] or "NavNormal" },
				},
			}
		end,
		preview_item = function(item)
			local lines = read_file(item.file)
			if not lines then
				return nil
			end
			return {
				lines = lines,
				syntax = vim.filetype.match({ filename = item.file }),
				focus_lnum = item.lnum > 1 and item.lnum or nil,
			}
		end,
		open_item = function(item, ow)
			jump_to(ow, item.file, item.lnum, item.col)
		end,
	})
end

-- ── Man Pages ─────────────────────────────────────────────────────────────────

local function manpages_picker()
	local items = {}
	local function do_open()
		if #items == 0 then
			vim.notify("No man pages found", vim.log.levels.WARN)
			return
		end
		open_picker({
			title = "Man Pages",
			all_items = items,
			filter_items = function(all, q)
				return filter(all, q)
			end,
			render_item = function(item, _)
				return { text = "   " .. item, highlights = { { 3, 3 + #item, "SrchKey" } } }
			end,
			preview_item = function(item)
				local page = vim.trim(item:match("^([^%(]+)") or item)
				local out = vim.fn.system("man -P cat " .. vim.fn.shellescape(page) .. " 2>/dev/null")
				if out == "" then
					return { lines = { " (no man page)" } }
				end
				return { lines = vim.split(out, "\n") }
			end,
			open_item = function(item, _)
				vim.cmd("Man " .. vim.trim(item:match("^([^%(]+)") or item))
			end,
		})
	end
	vim.fn.jobstart({ "bash", "-c", "apropos -l '' 2>/dev/null | awk '{print $1\"(\"$2\")\"}' | sort -u" }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			for _, line in ipairs(data or {}) do
				if line ~= "" then
					items[#items + 1] = line
				end
			end
		end,
		on_exit = function()
			if #items == 0 then
				for _, c in ipairs(vim.fn.getcompletion("", "shellcmd")) do
					items[#items + 1] = c
				end
			end
			vim.schedule(do_open)
		end,
	})
end

-- ── Plugin Spec ───────────────────────────────────────────────────────────────

local function plugins_picker()
	local ok, lazy_cfg = pcall(require, "lazy.core.config")
	if not ok then
		vim.notify("lazy.nvim not available", vim.log.levels.WARN)
		return
	end
	local items = {}
	for name, plug in pairs(lazy_cfg.plugins) do
		items[#items + 1] = {
			name = name,
			url = plug[1] or plug.url or "",
			dir = plug.dir or "",
			version = plug.version or "",
			enabled = plug.enabled ~= false,
			lazy = plug.lazy or false,
		}
	end
	table.sort(items, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	open_picker({
		title = "Plugins",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.name .. " " .. it.url
			end)
		end,
		render_item = function(item, _)
			local status = item.enabled and "  " or "  "
			local lazy_str = item.lazy and "  [lazy]" or ""
			local text = "   " .. status .. item.name .. lazy_str
			local st_s, st_e = 3, 3 + #status
			return {
				text = text,
				highlights = {
					{ st_s, st_e, item.enabled and "SrchVal" or "NavDiagE" },
					{ st_e, st_e + #item.name, "NavFilePath" },
					{ st_e + #item.name, st_e + #item.name + #lazy_str, "NavLnum" },
				},
			}
		end,
		preview_item = function(item)
			local lines = {
				"  Name    : " .. item.name,
				"  Repo    : " .. item.url,
				"  Dir     : " .. item.dir,
				"  Version : " .. (item.version ~= "" and item.version or "latest"),
				"  Enabled : " .. tostring(item.enabled),
				"  Lazy    : " .. tostring(item.lazy),
			}
			if item.dir ~= "" then
				local rlines = read_file(item.dir .. "/README.md")
				if rlines then
					lines[#lines + 1] = ""
					lines[#lines + 1] = "  README:"
					for i = 1, math.min(25, #rlines) do
						lines[#lines + 1] = "  " .. rlines[i]
					end
				end
			end
			return { lines = lines, syntax = "markdown" }
		end,
		open_item = function(item, _)
			if item.url ~= "" then
				pcall(vim.ui.open, "https://github.com/" .. item.url)
			end
		end,
	})
end

-- ── Quickfix ──────────────────────────────────────────────────────────────────

local function quickfix_picker()
	local raw = vim.fn.getqflist()
	if #raw == 0 then
		vim.notify("Quickfix list is empty", vim.log.levels.INFO)
		return
	end
	local items = {}
	local SEV_HL = { E = "NavDiagE", W = "NavDiagW", I = "NavDiagI", N = "NavDiagH" }
	for _, item in ipairs(raw) do
		local filepath = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
		if filepath ~= "" then
			items[#items + 1] = {
				file = filepath,
				lnum = item.lnum,
				col = math.max(0, (item.col or 1) - 1),
				text = vim.trim(item.text or ""),
				type = item.type or "",
			}
		end
	end
	open_picker({
		title = "Quickfix",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.file .. " " .. it.text
			end)
		end,
		render_item = function(item, _)
			local rel = vim.fn.fnamodify(item.file, ":.")
			local icon, icon_hl = get_icon(item.file)
			local sev = item.type ~= "" and ("[" .. item.type .. "] ") or ""
			local text = "   " .. icon .. " " .. rel .. ":" .. item.lnum .. "  " .. sev .. item.text:sub(1, 40)
			local ic_s, ic_e = 3, 3 + #icon
			local rel_s, rel_e = ic_e + 1, ic_e + 1 + #rel
			local ln_e = rel_e + 1 + #tostring(item.lnum)
			return {
				text = text,
				highlights = {
					{ ic_s, ic_e, icon_hl },
					{ rel_s, rel_e, "NavFilePath" },
					{ rel_e, ln_e, "NavLnum" },
					{ ln_e + 2, ln_e + 2 + #sev, SEV_HL[item.type] or "NavNormal" },
				},
			}
		end,
		preview_item = function(item)
			local lines = read_file(item.file)
			if not lines then
				return nil
			end
			return {
				lines = lines,
				syntax = vim.filetype.match({ filename = item.file }),
				focus_lnum = item.lnum > 1 and item.lnum or nil,
			}
		end,
		open_item = function(item, ow)
			jump_to(ow, item.file, item.lnum, item.col)
		end,
	})
end

-- ── Registers ─────────────────────────────────────────────────────────────────

local function registers_picker()
	local names = {
		'"',
		"0",
		"1",
		"2",
		"3",
		"4",
		"5",
		"6",
		"7",
		"8",
		"9",
		"a",
		"b",
		"c",
		"d",
		"e",
		"f",
		"g",
		"h",
		"i",
		"j",
		"k",
		"l",
		"m",
		"n",
		"o",
		"p",
		"q",
		"r",
		"s",
		"t",
		"u",
		"v",
		"w",
		"x",
		"y",
		"z",
		"+",
		"*",
		"-",
		".",
		":",
		"/",
		"%",
		"#",
	}
	local items = {}
	for _, r in ipairs(names) do
		local ok, val = pcall(vim.fn.getreg, r)
		if ok and val ~= "" then
			items[#items + 1] = { reg = r, value = val }
		end
	end
	open_picker({
		title = "Registers",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.reg .. " " .. it.value
			end)
		end,
		render_item = function(item, _)
			return {
				text = '   "' .. item.reg .. "  " .. item.value:gsub("\n", "↵"):sub(1, 60),
				highlights = { { 3, 5, "SrchKey" } },
			}
		end,
		preview_item = function(item)
			local lines = { '  Register "' .. item.reg .. ":", "" }
			for _, l in ipairs(vim.split(item.value, "\n")) do
				lines[#lines + 1] = "  " .. l
			end
			return { lines = lines }
		end,
		open_item = function(item, ow)
			vim.api.nvim_set_current_win(ow)
			vim.fn.setreg('"', item.value)
			vim.cmd("normal! p")
		end,
	})
end

-- ── Search History ────────────────────────────────────────────────────────────

local function searchhistory_picker()
	local items = {}
	for i = -1, -200, -1 do
		local h = vim.fn.histget("search", i)
		if h == "" then
			break
		end
		items[#items + 1] = h
	end
	open_picker({
		title = "Search History",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q)
		end,
		render_item = function(item, _)
			return { text = "   / " .. item, highlights = { { 3, 5, "SrchKey" } } }
		end,
		preview_item = function(item)
			return { lines = { "", "  /" .. item, "" } }
		end,
		open_item = function(item, ow)
			vim.api.nvim_set_current_win(ow)
			vim.fn.histadd("search", item)
			vim.fn.setreg("/", item)
			pcall(vim.cmd, "/" .. item)
		end,
	})
end

-- ── Noice History ─────────────────────────────────────────────────────────────

local function noice_picker()
	local ok, history_mod = pcall(require, "noice.message.history")
	if not ok then
		pcall(vim.cmd, "Noice history")
		return
	end
	local raw = history_mod.get and history_mod.get() or {}
	local items = {}
	for i = #raw, 1, -1 do
		local msg = raw[i]
		local ok2, content = pcall(function()
			return msg:content()
		end)
		if ok2 and content and content ~= "" then
			items[#items + 1] = { text = content, level = msg.level or "info" }
		end
	end
	if #items == 0 then
		vim.notify("No noice history", vim.log.levels.INFO)
		return
	end
	local LVL_HL = { error = "NavDiagE", warn = "NavDiagW", info = "NavDiagI" }
	local LVL_ICON = { error = "󰅚 ", warn = "󰀪 ", info = "󰋽 " }
	open_picker({
		title = "Noice History",
		all_items = items,
		filter_items = function(all, q)
			return filter(all, q, function(it)
				return it.text
			end)
		end,
		render_item = function(item, _)
			local icon = LVL_ICON[item.level] or "   "
			return {
				text = "   " .. icon .. item.text:gsub("\n", " "):sub(1, 60),
				highlights = { { 3, 3 + #icon, LVL_HL[item.level] or "NavDiagI" } },
			}
		end,
		preview_item = function(item)
			return { lines = vim.split(item.text, "\n") }
		end,
		open_item = function(item, _)
			vim.fn.setreg("+", item.text)
			vim.notify("Yanked message", vim.log.levels.INFO)
		end,
	})
end

-- ── Undo History (dual-pane with incremental scroll) ──────────────────────────

local function undotree_picker()
	local target_buf = vim.api.nvim_get_current_buf()
	if vim.bo[target_buf].buftype ~= "" then
		vim.notify("Undo History: not a file buffer", vim.log.levels.WARN)
		return
	end
	local tree = vim.fn.undotree()
	local seq_cur = tree.seq_cur or 0
	if not tree.entries or #tree.entries == 0 then
		vim.notify("Undo History: no undo entries for this buffer", vim.log.levels.INFO)
		return
	end

	local raw_items = {}
	local function flatten(list)
		for i = #list, 1, -1 do
			local e = list[i]
			raw_items[#raw_items + 1] = { seq = e.seq, time = e.time, cur = (e.seq == seq_cur), save = e.save ~= nil }
			if e.alt then
				flatten(e.alt)
			end
		end
	end
	flatten(tree.entries or {})

	local cur_full = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
	local snapshots = {}
	snapshots[seq_cur] = { lines = cur_full, offset = 0, first_changed = nil, fetched_e = #cur_full }

	local function get_snapshot(seq, win_h)
		if snapshots[seq] then
			return snapshots[seq]
		end
		local h = math.max(win_h or 30, 20)
		vim.api.nvim_buf_call(target_buf, function()
			pcall(vim.cmd, "silent! noautocmd undo " .. seq)
		end)
		local total = vim.api.nvim_buf_line_count(target_buf)
		local lines = vim.api.nvim_buf_get_lines(target_buf, 0, math.min(total, h), false)
		local first_changed = nil
		for i = 1, #lines do
			if (lines[i] or "") ~= (cur_full[i] or "") then
				first_changed = i
				break
			end
		end
		snapshots[seq] = { lines = lines, offset = 0, first_changed = first_changed, fetched_e = #lines, total = total }
		vim.api.nvim_buf_call(target_buf, function()
			pcall(vim.cmd, "silent! noautocmd undo " .. seq_cur)
		end)
		return snapshots[seq]
	end

	local function extend_snapshot_down(seq, up_to_1based)
		if seq == seq_cur then
			return
		end
		local snap = snapshots[seq]
		if not snap then
			return
		end
		local already = snap.fetched_e or #snap.lines
		if up_to_1based <= already then
			return
		end
		local cap = snap.total or #cur_full
		local new_e = math.min(cap, up_to_1based)
		if new_e <= already then
			return
		end
		vim.api.nvim_buf_call(target_buf, function()
			pcall(vim.cmd, "silent! noautocmd undo " .. seq)
		end)
		local new_lines = vim.api.nvim_buf_get_lines(target_buf, already, new_e, false)
		vim.api.nvim_buf_call(target_buf, function()
			pcall(vim.cmd, "silent! noautocmd undo " .. seq_cur)
		end)
		for _, l in ipairs(new_lines) do
			snap.lines[#snap.lines + 1] = l
		end
		snap.fetched_e = new_e
	end

	P.setup_hl()
	local filtered = raw_items
	local selected = 1
	local query = ""

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
	local box_w = math.floor(W * 0.90)
	local box_h = math.floor(H * 0.85)
	local box_row = math.floor((H - box_h) / 2) - 1
	local box_col = math.floor((W - box_w) / 2)
	local left_w = math.floor(box_w * 0.45)
	local right_w_val = box_w - left_w - 1 - 3
	local right_col = box_col + left_w + 2
	local input_outer = 3
	local results_h = box_h - input_outer - 1
	local total_right_h = box_h - 1
	local top_h = math.floor((total_right_h - 4) / 2) + 1
	local bot_h = total_right_h - 4 - top_h + 2
	local bot_row = box_row + top_h + 2

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
	vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { " >  " })
	local ns_prompt = vim.api.nvim_create_namespace("undo2_prompt")
	local function apply_prompt_hl()
		vim.api.nvim_buf_clear_namespace(input_buf, ns_prompt, 0, -1)
		vim.api.nvim_buf_add_highlight(input_buf, ns_prompt, "NavPromptArrow", 0, 1, 2)
	end
	apply_prompt_hl()
	vim.api.nvim_win_set_cursor(input_win, { 1, 4 })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		buffer = input_buf,
		callback = function()
			if vim.api.nvim_win_get_cursor(0)[2] < 4 then
				vim.api.nvim_win_set_cursor(0, { 1, 4 })
			end
		end,
	})

	local results_buf, results_win = make_win(left_w, results_h, box_row + input_outer, box_col, "Undo History", 50)
	vim.wo[results_win].wrap = false
	vim.bo[results_buf].modifiable = false
	vim.wo[results_win].winhl = "Normal:NavResultsBg,FloatBorder:NavBorder,FloatTitle:NavTitle"

	local before_buf, before_win = make_win(right_w_val, top_h, box_row, right_col, "󰋢 Selected State", 50)
	vim.wo[before_win].wrap = false
	vim.wo[before_win].scrolloff = 3
	vim.bo[before_buf].modifiable = false

	local after_buf, after_win = make_win(right_w_val, bot_h, bot_row, right_col, "󰋣 Current State", 50)
	vim.wo[after_win].wrap = false
	vim.wo[after_win].scrolloff = 3
	vim.bo[after_buf].modifiable = false

	for _, b in ipairs({ input_buf, results_buf, before_buf, after_buf, backdrop_buf }) do
		vim.b[b].blink_cmp_disable = true
		vim.b[b].completion = false
		vim.b[b].cmp_disable = true
	end

	-- Block all navigation keys in every buffer, then remap only the ones we want.
	local all_keys = { "h", "j", "k", "l", "<C-h>", "<C-j>", "<C-k>", "<C-l>", "<Up>", "<Down>", "<Left>", "<Right>" }
	for _, b in ipairs({ input_buf, results_buf, before_buf, after_buf }) do
		for _, key in ipairs(all_keys) do
			vim.keymap.set({ "n", "i" }, key, "<Nop>", { noremap = true, silent = true, buffer = b })
		end
	end

	vim.api.nvim_set_current_win(input_win)
	vim.cmd("startinsert")

	local ns_sel = vim.api.nvim_create_namespace("undo2_sel")
	local ns_cur = vim.api.nvim_create_namespace("undo2_cur")
	local ns_hl = vim.api.nvim_create_namespace("undo2_hl")
	local ns_bef = vim.api.nvim_create_namespace("undo2_bef")
	local ns_aft = vim.api.nvim_create_namespace("undo2_aft")
	local ns_ext_bef = vim.api.nvim_create_namespace("undo2_ext_bef")
	local ns_ext_aft = vim.api.nvim_create_namespace("undo2_ext_aft")
	local timer = nil
	local preview_timer = nil
	local buf_syntax = vim.bo[target_buf].filetype
	local before_file_end = 0
	local after_file_end = 0
	local scroll_seq = nil
	local full_diff_timer = nil

	-- For debounced focus on first diff
	local first_diff_line = nil
	local scroll_debounce_timer_before = nil
	local scroll_debounce_timer_after = nil

	local function fill_pane(buf, win, ns, ns_ext, snap, compare_slice)
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		vim.api.nvim_buf_clear_namespace(buf, ns_ext, 0, -1)
		if not snap then
			set_ro(buf, { "  (no snapshot)" })
			return
		end
		local padded = {}
		for i, v in ipairs(snap.lines) do
			padded[i] = " " .. v
		end
		set_ro(buf, padded)
		if buf_syntax ~= "" then
			pcall(function()
				vim.bo[buf].syntax = buf_syntax
			end)
		end
		local ok, all_marks = pcall(
			vim.api.nvim_buf_get_extmarks,
			target_buf,
			-1,
			{ 0, 0 },
			{ -1, -1 },
			{ details = true }
		)
		if ok then
			for _, mark in ipairs(all_marks) do
				local row, col, d = mark[2], mark[3], mark[4]
				if d then
					local opts = { priority = 50 }
					local useful = false
					if d.virt_text and #d.virt_text > 0 then
						opts.virt_text = d.virt_text
						opts.virt_text_pos = d.virt_text_pos or "overlay"
						opts.hl_mode = d.hl_mode or "combine"
						useful = true
					end
					if d.hl_group then
						opts.hl_group = d.hl_group
						opts.end_row = d.end_row
						opts.end_col = d.end_col and (d.end_col + 1) or nil
						useful = true
					end
					if useful then
						pcall(vim.api.nvim_buf_set_extmark, buf, ns_ext, row, col + 1, opts)
					end
				end
			end
		end
		local cmp = compare_slice or {}
		local n = math.max(#snap.lines, #cmp)
		for i = 1, n do
			if (snap.lines[i] or "") ~= (cmp[i] or "") then
				if i <= #padded then
					vim.api.nvim_buf_add_highlight(buf, ns, "NavPreviewCur", i - 1, 1, -1)
				end
			end
		end
		local first = snap.first_changed
		local local_focus = first and (first - (snap.offset or 0)) or nil
		if local_focus and local_focus >= 1 and local_focus <= #padded then
			local win_h = vim.api.nvim_win_get_height(win)
			local topline = math.max(1, local_focus - math.floor(win_h / 4))
			vim.fn.win_execute(win, string.format("call winrestview({'lnum':%d,'topline':%d})", local_focus, topline))
		end
	end

	local function update_previews()
		if #filtered == 0 or not filtered[selected] then
			set_ro(before_buf, {})
			set_ro(after_buf, {})
			return
		end
		local item = filtered[selected]
		if not snapshots[item.seq] then
			set_ro(before_buf, { "  (loading…)" })
		end
		local sel_snap = get_snapshot(
			item.seq,
			math.max(vim.api.nvim_win_get_height(before_win), vim.api.nvim_win_get_height(after_win), 20)
		)
		local n = #sel_snap.lines
		local cur_slice = {}
		for i = 1, n do
			cur_slice[i] = cur_full[i] or ""
		end
		local cur_win_snap = { lines = cur_slice, offset = 0, first_changed = sel_snap.first_changed, fetched_e = n }
		fill_pane(before_buf, before_win, ns_bef, ns_ext_bef, sel_snap, cur_slice)
		fill_pane(after_buf, after_win, ns_aft, ns_ext_aft, cur_win_snap, sel_snap.lines)
		before_file_end = sel_snap.fetched_e
		after_file_end = n
		scroll_seq = item.seq
		first_diff_line = sel_snap.first_changed -- store for debounced focus
	end

	local SCROLL_MARGIN = 10
	local function on_pane_scroll(wid)
		if not scroll_seq then
			return
		end
		local snap = snapshots[scroll_seq]
		if not snap then
			return
		end
		local info = vim.fn.getwininfo(wid)
		if not info or not info[1] then
			return
		end
		local botline = info[1].botline
		if wid == before_win then
			local need_e = botline + SCROLL_MARGIN
			if need_e <= before_file_end then
				return
			end
			extend_snapshot_down(scroll_seq, need_e)
			local new_e = snap.fetched_e
			if new_e <= before_file_end then
				return
			end
			local new_padded = {}
			for fl = before_file_end + 1, new_e do
				new_padded[#new_padded + 1] = " " .. (snap.lines[fl] or "")
			end
			local old_len = vim.api.nvim_buf_line_count(before_buf)
			vim.bo[before_buf].modifiable = true
			vim.api.nvim_buf_set_lines(before_buf, old_len, old_len, false, new_padded)
			vim.bo[before_buf].modifiable = false
			for i = 1, #new_padded do
				local fl = before_file_end + i
				if (snap.lines[fl] or "") ~= (cur_full[fl] or "") then
					vim.api.nvim_buf_add_highlight(before_buf, ns_bef, "NavPreviewCur", old_len + i - 1, 1, -1)
				end
			end
			before_file_end = new_e

			-- Debounced focus on first difference
			if scroll_debounce_timer_before then
				scroll_debounce_timer_before:stop()
			end
			scroll_debounce_timer_before = vim.defer_fn(function()
				if first_diff_line and vim.api.nvim_win_is_valid(before_win) then
					local total_lines = vim.api.nvim_buf_line_count(before_buf)
					if first_diff_line <= total_lines then
						vim.api.nvim_win_set_cursor(before_win, { first_diff_line, 0 })
						vim.fn.win_execute(before_win, "normal! zt")
					end
				end
				scroll_debounce_timer_before = nil
			end, 200)
		elseif wid == after_win then
			local need_e = botline + SCROLL_MARGIN
			if need_e <= after_file_end then
				return
			end
			local new_e = math.min(#cur_full, need_e)
			if new_e <= after_file_end then
				return
			end
			extend_snapshot_down(scroll_seq, new_e)
			local new_padded = {}
			for fl = after_file_end + 1, new_e do
				new_padded[#new_padded + 1] = " " .. (cur_full[fl] or "")
			end
			local old_len = vim.api.nvim_buf_line_count(after_buf)
			vim.bo[after_buf].modifiable = true
			vim.api.nvim_buf_set_lines(after_buf, old_len, old_len, false, new_padded)
			vim.bo[after_buf].modifiable = false
			for i = 1, #new_padded do
				local fl = after_file_end + i
				if (cur_full[fl] or "") ~= (snap.lines[fl] or "") then
					vim.api.nvim_buf_add_highlight(after_buf, ns_aft, "NavPreviewCur", old_len + i - 1, 1, -1)
				end
			end
			after_file_end = new_e

			-- Debounced focus on first difference
			if scroll_debounce_timer_after then
				scroll_debounce_timer_after:stop()
			end
			scroll_debounce_timer_after = vim.defer_fn(function()
				if first_diff_line and vim.api.nvim_win_is_valid(after_win) then
					local total_lines = vim.api.nvim_buf_line_count(after_buf)
					if first_diff_line <= total_lines then
						vim.api.nvim_win_set_cursor(after_win, { first_diff_line, 0 })
						vim.fn.win_execute(after_win, "normal! zt")
					end
				end
				scroll_debounce_timer_after = nil
			end, 200)
		end
	end

	local scroll_grp = vim.api.nvim_create_augroup("UndoPickerScroll", { clear = true })
	vim.api.nvim_create_autocmd("WinScrolled", {
		group = scroll_grp,
		callback = function(ev)
			local wid = tonumber(ev.match)
			if not vim.api.nvim_win_is_valid(before_win) then
				return
			end
			if wid == before_win or wid == after_win then
				on_pane_scroll(wid)
			end
		end,
	})

	local function highlight_selected()
		vim.api.nvim_buf_clear_namespace(results_buf, ns_sel, 0, -1)
		vim.api.nvim_buf_clear_namespace(results_buf, ns_cur, 0, -1)
		if #filtered > 0 and filtered[selected] then
			vim.api.nvim_buf_set_extmark(
				results_buf,
				ns_sel,
				selected - 1,
				0,
				{ hl_group = "NavSelected", hl_eol = true, end_row = selected, end_col = 0, priority = 100 }
			)
			vim.api.nvim_buf_set_extmark(
				results_buf,
				ns_cur,
				selected - 1,
				0,
				{ virt_text = { { " > ", "NavCursor" } }, virt_text_pos = "overlay", hl_mode = "combine" }
			)
			pcall(vim.api.nvim_win_set_cursor, results_win, { selected, 0 })
		end
		vim.api.nvim_win_set_config(
			results_win,
			{ footer = string.format(" %d/%d ", selected, #filtered), footer_pos = "right" }
		)
		if preview_timer then
			preview_timer:stop()
		end
		preview_timer = vim.defer_fn(update_previews, 80)
	end

	local function render_results()
		vim.api.nvim_buf_clear_namespace(results_buf, ns_hl, 0, -1)
		local max_len = left_w - 3
		local display = {}
		for i, item in ipairs(filtered) do
			local cur_str = item.cur and " ● " or "   "
			local save_str = item.save and "  [saved]" or ""
			local time_str = os.date("%H:%M:%S", item.time)
			local seq_str = "#" .. item.seq
			local text = cur_str .. seq_str .. "   " .. time_str .. save_str
			local char_len = vim.fn.strchars(text)
			if char_len < max_len then
				text = text .. string.rep(" ", max_len - char_len)
			end
			display[i] = text
			local _i, _seq_e = i, 3 + #seq_str
			local _time, _item = time_str, item
			vim.schedule_wrap(function()
				if not vim.api.nvim_buf_is_valid(results_buf) then
					return
				end
				vim.api.nvim_buf_add_highlight(
					results_buf,
					ns_hl,
					_item.cur and "NavCursor" or "NavNormal",
					_i - 1,
					0,
					3
				)
				vim.api.nvim_buf_add_highlight(results_buf, ns_hl, "SrchKey", _i - 1, 3, _seq_e)
				vim.api.nvim_buf_add_highlight(results_buf, ns_hl, "NavLnum", _i - 1, _seq_e + 3, _seq_e + 3 + #_time)
				if _item.save then
					vim.api.nvim_buf_add_highlight(results_buf, ns_hl, "SrchVal", _i - 1, _seq_e + 3 + #_time, -1)
				end
			end)()
		end
		if #filtered == 0 then
			display = { "   (no results)" }
		end
		set_ro(results_buf, display)
		highlight_selected()
	end

	local function do_filter(q)
		if q == "" then
			return raw_items
		end
		local out = {}
		for _, it in ipairs(raw_items) do
			if tostring(it.seq):find(q, 1, true) then
				out[#out + 1] = it
			end
		end
		return out
	end

	local function close()
		if full_diff_timer then
			full_diff_timer:stop()
			full_diff_timer = nil
		end
		if scroll_debounce_timer_before then
			scroll_debounce_timer_before:stop()
		end
		if scroll_debounce_timer_after then
			scroll_debounce_timer_after:stop()
		end
		pcall(vim.api.nvim_del_augroup_by_name, "UndoPickerScroll")
		pcall(vim.api.nvim_win_close, backdrop_win, true)
		pcall(vim.api.nvim_win_close, input_win, true)
		pcall(vim.api.nvim_win_close, results_win, true)
		pcall(vim.api.nvim_win_close, before_win, true)
		pcall(vim.api.nvim_win_close, after_win, true)
		vim.cmd("stopinsert")
		vim.schedule(function()
			pcall(vim.api.nvim_exec_autocmds, "ColorScheme", { pattern = "*", modeline = false })
			vim.cmd("redraw!")
			local ok, snacks = pcall(require, "snacks")
			if ok and snacks.picker then
				pcall(function()
					local explorers = snacks.picker.get({ source = "explorer" })
					for _, picker in ipairs(explorers) do
						picker:find()
					end
				end)
			end
		end)
	end

	local function open_selected()
		if #filtered == 0 or not filtered[selected] then
			return
		end
		local item = filtered[selected]
		close()
		vim.schedule(function()
			vim.api.nvim_set_current_win(origin_win)
			pcall(vim.cmd, "undo " .. item.seq)
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

	-- Now map the specific keys we want (overriding the <Nop> from earlier)
	for _, b in ipairs({ input_buf, results_buf, before_buf, after_buf }) do
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

	-- ── window focus movement (Ctrl+hjkl) ─────────────────────────────────────
	local function fi()
		vim.api.nvim_set_current_win(input_win)
		vim.cmd("startinsert")
	end
	local function fr()
		vim.api.nvim_set_current_win(results_win)
		vim.cmd("stopinsert")
	end
	local function fb()
		vim.api.nvim_set_current_win(before_win)
		vim.cmd("stopinsert")
	end
	local function fa()
		vim.api.nvim_set_current_win(after_win)
		vim.cmd("stopinsert")
	end

	do
		local ko = { noremap = true, silent = true, buffer = input_buf }
		vim.keymap.set({ "i", "n" }, "<C-j>", fr, ko)
		vim.keymap.set({ "i", "n" }, "<C-l>", fb, ko)
	end
	do
		local ko = { noremap = true, silent = true, buffer = results_buf }
		vim.keymap.set({ "i", "n" }, "<C-k>", fi, ko)
		vim.keymap.set({ "i", "n" }, "<C-h>", fi, ko)
		vim.keymap.set({ "i", "n" }, "<C-l>", fb, ko)
	end
	do
		local ko = { noremap = true, silent = true, buffer = before_buf }
		vim.keymap.set({ "i", "n" }, "<C-h>", fr, ko)
		vim.keymap.set({ "i", "n" }, "<C-j>", fa, ko)
		vim.keymap.set({ "i", "n" }, "<C-k>", fi, ko)
	end
	do
		local ko = { noremap = true, silent = true, buffer = after_buf }
		vim.keymap.set({ "i", "n" }, "<C-h>", fr, ko)
		vim.keymap.set({ "i", "n" }, "<C-k>", fb, ko)
	end

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
				filtered = do_filter(query)
				selected = 1
				render_results()
			end, 120)
		end,
	})

	render_results()
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.grep(dir)
	grep_picker("Grep", dir or git_root())
end
function M.grep_cwd()
	grep_picker("Grep (cwd)", vim.fn.getcwd())
end
function M.grep_word(root)
	local w = vim.fn.expand("<cword>")
	grep_picker("Grep: " .. w, root and git_root() or vim.fn.getcwd(), w)
end
function M.autocmds()
	autocmds_picker()
end
function M.cmdhistory()
	cmdhistory_picker()
end
function M.commands()
	commands_picker()
end
function M.help()
	help_picker()
end
function M.highlights()
	highlights_picker()
end
function M.icons()
	icons_picker()
end
function M.jumps()
	jumps_picker()
end
function M.keymaps()
	keymaps_picker()
end
function M.loclist()
	loclist_picker()
end
function M.manpages()
	manpages_picker()
end
function M.plugins()
	plugins_picker()
end
function M.quickfix()
	quickfix_picker()
end
function M.registers()
	registers_picker()
end
function M.searchhistory()
	searchhistory_picker()
end
function M.undo()
	undotree_picker()
end
function M.noice()
	noice_picker()
end

return M
