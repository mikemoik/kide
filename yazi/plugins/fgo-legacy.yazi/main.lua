--- @since 26.1.22
-- fgo-legacy.yazi: fgo.yazi for yazi 26.1.22 (pre-26.8.15 plugin API).
-- Same behavior; the differences to fgo.yazi are:
--   - the list directory is created with an fs.create loop (no `fs.unique`);
--   - visual mode is `mode.is_select or mode.is_unset` (no `mode.is_normal`;
--     `is_visual` is deprecated on newer yazi);
--   - the plugin name in `setup` and the usage message.
-- Keep the two files in sync otherwise.
--
-- Browse a list of file positions (`path:line[:col]`) in yazi.
--
-- `$FGO_LIST` names a text file with one position per line,
-- `abs-path<TAB>line<TAB>col` (col may be empty). `setup` (init.lua) starts
-- the list when the variable is set; nothing happens without it.
--
-- yazi's folders are keyed by URL, so one file cannot be listed twice (at
-- different lines) in a virtual list. The list is therefore a directory of
-- numbered symlinks in $TMPDIR (default /tmp), one per position, in list
-- order, each named `<n> <path>:<line>[:<col>]` (path relative to $PWD where
-- possible, `/` shown as `∕`). The position is read back from the name, so
-- the previewer keeps no list state.
--
-- In the list:
--   - peek shows the real file scrolled to the line (a quarter of the preview
--     height as context above), the line highlighted and the token at the
--     column in its own color (rendered by `bat`; without it the built-in
--     code preview, unhighlighted). J/K scroll, the position is remembered
--     per row;
--   - `plugin fgo -- open` runs the editor at line:col (`shell --block`);
--   - `plugin fgo -- leave` reveals the real file in its parent directory.
-- Outside the list, open falls back to `open` (or `plugin <name> -- open`
-- with `--else=<name>`, e.g. search-jump-legacy) and leave to `escape`.
--
-- State (sync context): st.dir = the list directory of this instance;
-- st.files[path of the row] = { mtime, h, pos, max }.

local M = {}

local HL_LINE = "\27[48;5;238m" -- the position's line: dark grey background
local HL_CUR = "\27[1;30;43m" -- token at the column: bold black on yellow
local RESET = "\27[0m"
local MARGIN = 8 -- columns kept left of the column when scrolling sideways (at most 1/4 width)
local CUT_LEFT = "\27[2m«\27[0m" -- line cut off on the left (view scrolled sideways)
local SLASH = "∕" -- U+2215, stands in for `/` in row names
local NAME_MAX = 250 -- bytes; file names are limited to 255

local function notify(content, level)
	ya.notify { title = "fgo", content = content, timeout = 5, level = level or "error" }
end

-- `<n> <label>:<line>[:<col>]` -> line, col (col defaults to 1)
local function position(name)
	local l, c = name:match(":(%d+):(%d+)$")
	if not l then
		l = name:match(":(%d+)$")
	end
	if l and name:match("^%d+ ") then
		return tonumber(l), tonumber(c) or 1
	end
end

local get = ya.sync(function(st, key) return st.files and st.files[key] end)

local put = ya.sync(function(st, key, rec)
	st.files = st.files or {}
	st.files[key] = rec
end)

local set_pos = ya.sync(function(st, key, pos, max)
	local rec = st.files and st.files[key]
	if rec then
		rec.pos, rec.max = pos, max or rec.max
	end
end)

local set_dir = ya.sync(function(st, dir) st.dir = dir end)

-- The hovered row, when the active tab shows this instance's list.
local hovered = ya.sync(function(st)
	local h = cx.active.current.hovered
	if not st.dir or tostring(cx.active.current.cwd) ~= st.dir or not h or cx.active.mode.is_select or cx.active.mode.is_unset then
		return nil
	end
	return { name = h.name, link = h.link_to and tostring(h.link_to) }
end)

local function target(rec, line)
	local t = math.max(0, line - 1 - rec.h // 4)
	return rec.max and math.min(t, rec.max) or t
end

-- Wrap the byte ranges `spans` ({ from, to, sgr }, columns of the uncolored
-- line, `to` exclusive, adjacent and ascending) of the ANSI string `s` in
-- their SGR codes. bat resets after every token, so the code is re-applied
-- after each escape inside a range, and the token's own escapes are replayed
-- after a range ends. (Same as in search-jump.)
local function mark(s, spans)
	if #spans == 0 then
		return s
	end
	local out, i, col, k, inside, active = {}, 1, 0, 1, false, ""
	while i <= #s do
		local esc = s:match("^\27%[[%d;]*m", i)
		if esc then
			active = (esc == RESET or esc == "\27[m") and "" or active .. esc
			out[#out + 1] = inside and esc .. spans[k][3] or esc
			i = i + #esc
		else
			col = col + 1
			if inside and col == spans[k][2] then
				out[#out + 1], inside, k = RESET .. active, false, k + 1
			end
			if not inside and spans[k] and col == spans[k][1] then
				out[#out + 1], inside = spans[k][3], true
			end
			out[#out + 1] = s:sub(i, i)
			i = i + 1
		end
	end
	if inside then
		out[#out + 1] = RESET
	end
	return table.concat(out)
end

-- Spans for the position's line: the token at byte column `col` (a word, else
-- one UTF-8 character) in HL_CUR, the rest of the line in HL_LINE. Returns
-- the spans and the byte range of the token (nil when col is past the end).
local function spans_of(plain, col)
	local n = #plain
	if n == 0 then
		return {}
	elseif col > n then
		return { { 1, n + 1, HL_LINE } }
	end
	local e = plain:find("[^%w_]", col) or n + 1
	if e == col then
		e = col + 1
		while e <= n and plain:byte(e) >= 0x80 and plain:byte(e) < 0xC0 do
			e = e + 1
		end
	end
	local spans = {}
	for _, sp in ipairs { { 1, col, HL_LINE }, { col, e, HL_CUR }, { e, n + 1, HL_LINE } } do
		if sp[1] < sp[2] then
			spans[#spans + 1] = sp
		end
	end
	return spans, col, e
end

-- Render lines skip+1 .. skip+h of the file with bat and highlight the
-- position. Returns true when rendered, false when bat is unavailable.
local function render(job, key, line, col)
	local skip, h = job.skip, job.area.h
	local out = Command("bat")
		:arg({ "--color=always", "--style=plain", "--paging=never", "--wrap=never", "--tabs=0" })
		:arg({ "--line-range", string.format("%d:%d", skip + 1, skip + h), "--", tostring(job.file.url.path) })
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:output()
	if not out or not out.status.success then
		return false
	end

	local tab = string.rep(" ", rt.preview.tab_size)
	local function expand(s) return (s:gsub("\r", ""):gsub("\t", tab)) end

	local lines, widths, cur_from, cur_to = {}, {}, nil, nil
	for raw in out.stdout:gmatch("([^\n]*)\n") do
		local n, s = skip + #lines + 1, raw
		local plain = s:gsub("\27%[[%d;]*m", "")
		if n == line then
			local spans, from, to = spans_of(plain, col)
			s = mark(s, spans)
			if from then
				cur_from = ui.width(expand(plain:sub(1, from - 1)))
				cur_to = cur_from + ui.width(expand(plain:sub(from, to - 1)))
			end
		end
		lines[#lines + 1] = expand(s)
		widths[#lines] = ui.width(expand(plain))
	end

	if skip > 0 and #lines < h then
		local bound = math.max(0, skip + #lines - h)
		set_pos(key, bound, bound)
		ya.emit("peek", { bound, only_if = job.file.url, upper_bound = true })
		return true
	end

	-- Scroll the whole view sideways when the token ends past the right edge.
	local area, x = job.area, 0
	if cur_to and cur_to > area.w then
		x = math.max(0, cur_from - math.min(MARGIN, area.w // 4))
	end

	local widgets = { ui.Text.parse(table.concat(lines, "\n")):area(area):scroll(x, 0) }
	if x > 0 then
		for r = 1, #lines do
			if widths[r] > 0 then
				widgets[#widgets + 1] =
					ui.Text.parse(CUT_LEFT):area(ui.Rect { x = area.x, y = area.y + r - 1, w = 1, h = 1 })
			end
		end
	end
	ya.preview_widget(job, widgets)
	return true
end

function M:peek(job)
	local url = job.file.url
	local line, col = position(job.file.name)
	if not line then
		return require("code"):peek(job)
	end

	local key, mtime = tostring(url), job.file.cha.mtime or 0
	local rec = get(key)
	if not rec or rec.mtime ~= mtime or rec.h ~= job.area.h then
		local old = rec
		rec = { mtime = mtime, h = job.area.h }
		-- a changed file (e.g. after editing it) keeps its position
		rec.pos = old and old.pos or target(rec, line)
		put(key, rec)
	end

	if job.skip ~= rec.pos then
		return ya.emit("peek", { rec.pos, only_if = url })
	end

	if render(job, key, line, col) then
		return
	end
	local err, bound = ya.preview_code(job)
	if bound then
		set_pos(key, bound, bound)
		ya.emit("peek", { bound, only_if = url, upper_bound = true })
	elseif err and not err:find("cancelled", 1, true) then
		require("empty").msg(job, err)
	end
end

function M:seek(job)
	local h = cx.active.current.hovered
	if not h or h.url ~= job.file.url then
		return
	elseif not position(h.name) then
		return require("code"):seek(job)
	end

	local step = math.floor(job.units * job.area.h / 10)
	step = step == 0 and ya.clamp(-1, job.units, 1) or step

	local skip = math.max(0, cx.active.preview.skip + step)
	local rec = self.files and self.files[tostring(h.url)]
	if rec then
		skip = rec.max and math.min(skip, rec.max) or skip
		rec.pos = skip
	end
	ya.emit("peek", { skip, only_if = job.file.url })
end

-- Read $FGO_LIST into { { path, line, col|nil }, ... }, in file order.
local function read_list(file)
	local f, err = io.open(file, "r")
	if not f then
		return nil, err
	end
	local rows = {}
	for s in f:lines() do
		local path, l, c = s:match("^([^\t]+)\t(%d+)\t?(%d*)\r?$")
		if path then
			rows[#rows + 1] = { path, tonumber(l), tonumber(c) }
		end
	end
	f:close()
	return rows
end

-- Row name `<n> <label>:<line>[:<col>]`, at most NAME_MAX bytes (the label
-- is cut on the left, at a UTF-8 boundary, behind `…`).
local function row_name(i, width, row, base)
	local label = row[1]
	if base and label:sub(1, #base + 1) == base .. "/" then
		label = label:sub(#base + 2)
	end
	label = label:gsub("/", SLASH)
	local prefix = string.format("%0" .. width .. "d ", i)
	local suffix = ":" .. row[2] .. (row[3] and ":" .. row[3] or "")
	local room = NAME_MAX - #prefix - #suffix
	if #label > room then
		local s = #label - room + 4 -- 3 bytes for `…`
		while s <= #label and label:byte(s) >= 0x80 and label:byte(s) < 0xC0 do
			s = s + 1
		end
		label = "…" .. label:sub(s)
	end
	return prefix .. label .. suffix
end

local function start()
	local file = os.getenv("FGO_LIST")
	local rows, err = read_list(file)
	if not rows then
		return notify("Cannot read FGO_LIST: " .. tostring(err))
	elseif #rows == 0 then
		return notify("No positions in " .. file, "warn")
	end

	local tmp = os.getenv("TMPDIR")
	local root, dir, err = (tmp and tmp ~= "" and tmp or "/tmp") .. "/fgo", nil, "fgo … fgo_99 all exist"
	for i = 0, 99 do
		local u = Url(i == 0 and root or root .. "_" .. i)
		local ok, e = fs.create("dir", u)
		if ok then
			dir = u
			break
		elseif not fs.cha(u) then
			err = e -- a real failure, not an existing directory
			break
		end
	end
	if not dir then
		return notify("Cannot create the list directory: " .. tostring(err))
	end

	local base = os.getenv("PWD")
	base = base and base ~= "/" and base:gsub("/+$", "") or nil
	local width, script = #tostring(#rows), {}
	for i, row in ipairs(rows) do
		script[i] = string.format("ln -s -- %s %s", ya.quote(row[1]), ya.quote(row_name(i, width, row, base)))
	end
	local out, err = Command("sh")
		:arg({ "-c", table.concat(script, "\n") })
		:cwd(tostring(dir))
		:stdout(Command.NULL)
		:stderr(Command.PIPED)
		:output()
	if not out then
		return notify("Cannot run sh: " .. tostring(err))
	elseif not out.status.success then
		notify("Some rows could not be linked: " .. out.stderr, "warn")
	end

	set_dir(tostring(dir))
	ya.emit("cd", { dir, raw = true })
end

-- Open $VISUAL/$EDITOR at line:col of the real file. yazi waits for the
-- editor (`shell --block`), so quitting it returns to the list.
local function edit(path, line, col)
	local editor = os.getenv("VISUAL") or os.getenv("EDITOR") or "vi"
	if editor == "" then
		editor = "vi"
	end
	local name, quoted = editor:match("([^/%s]+)%s*$") or editor, ya.quote(path)
	local cmd
	if name == "nvim" or name == "vim" or name == "vi" then
		cmd = string.format("%s %s -- %s", editor, ya.quote(string.format("+call cursor(%d,%d)", line, col)), quoted)
	elseif name == "hx" or name == "helix" then
		cmd = string.format("%s %s", editor, ya.quote(string.format("%s:%d:%d", path, line, col)))
	else
		cmd = string.format("%s +%d %s", editor, line, quoted)
	end
	ya.emit("shell", { cmd, block = true })
end

function M:setup()
	local file = os.getenv("FGO_LIST")
	if file and file ~= "" then
		ya.emit("plugin", { "fgo-legacy", "start" })
	end
end

function M:entry(job)
	local action = job.args[1]
	if action == "start" then
		return start()
	elseif action ~= "open" and action ~= "leave" then
		return notify("Usage: plugin fgo-legacy -- open [--else=<plugin>] | leave")
	end

	local h, line, col = hovered(), nil, nil
	if h and h.link then
		line, col = position(h.name)
	end
	if not line then
		if action == "leave" then
			return ya.emit("escape", {})
		elseif job.args["else"] then
			return ya.emit("plugin", { job.args["else"], "open" })
		end
		return ya.emit("open", {})
	end

	if action == "open" then
		edit(h.link, line, col)
	else
		ya.emit("reveal", { Url(h.link), raw = true })
	end
end

return M
