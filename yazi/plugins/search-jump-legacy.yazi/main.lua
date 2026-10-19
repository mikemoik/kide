--- @since 26.1.22
--- @sync entry
-- search-jump-legacy.yazi: search-jump.yazi for yazi 26.1.22 (pre-26.8.15
-- plugin API). Same behavior; the differences to search-jump.yazi are:
--   - `url.is_search` / `url.domain` instead of `url.spec.is_search` / `.domain`;
--   - seek always delegates to `code` (the 26.1.22 seek job has no `mime`;
--     the built-in `json` seek is `code`'s anyway).
-- Keep the two files in sync otherwise.
--
-- Inside the result list of a content search (`S`, i.e. `search --via=rg`),
-- scroll the preview to the first match, highlight the matches (the current
-- one in its own color), step through them with
-- `plugin search-jump-legacy -- next|prev`, and open the editor at the current
-- match with `plugin search-jump-legacy -- open`. Without matches to act on,
-- next/prev fall back to `find_arrow` (yazi's default `n`/`N`) and open to
-- `open` (default `<Enter>`).
--
-- Wraps the built-in `code` previewer (and `json` for JSON files). Outside a
-- search directory both peek and seek delegate unchanged. Inside one (the
-- hovered URL is a `search://` URL whose domain is the query), the preview
-- position is owned by this plugin, per (query, file):
--   - first peek of a file: run `rg -o --column` on it, start at the first match;
--   - J/K (seek) and next/prev update the stored position;
--   - hovering away and back restores it (yazi itself resets skip to 0).
-- peek re-emits `peek <pos>` when yazi's skip differs from the stored one, so
-- `cx.active.preview.skip` always reflects what is shown.
--
-- The current match is the one next/prev last moved to; when it scrolls out
-- of view (J/K), the first visible match becomes current. next/prev step
-- match by match from a visible current match, otherwise from the view.
-- There is no wrap-around: at the last/first match the current one blinks.
--
-- The visible lines are rendered by `bat` (syntax colors) with the match byte
-- ranges wrapped in SGR codes; without `bat` the built-in code preview is
-- used, unhighlighted. Lines never wrap: when the current match ends past the
-- right edge, the whole view scrolls sideways (`ui.Text:scroll`); `«` marks
-- rows cut on the left, `»` rows with a match past the right edge.
--
-- State (sync context): st.files[key] = { mtime, m, at, cur, ctx, h, pos, max }
--   key = query .. "\0" .. path
--   m   = matches in file order: { { line, from, to }, ... } (1-based byte
--         columns of the uncolored line, `to` exclusive)
--   at  = { [line] = index of the first match on that line }
--   cur = index of the current match
--   ctx = lines of context kept above a match; h = preview height
--   pos = stored skip; max = upper bound (last skip that fills the preview)

local M = {}

local HL = "\27[7m" -- other matches: reverse video
local HL_CUR = "\27[1;30;43m" -- current match: bold black on yellow
local RESET = "\27[0m"
local BLINK = 0.15 -- seconds the current match blinks at the first/last match
local MARGIN = 8 -- columns kept left of a match when scrolling sideways (at most 1/4 width)
local CUT_LEFT = "\27[2m«\27[0m" -- line cut off on the left (view scrolled sideways)
local MORE_RIGHT = HL .. "»" .. RESET -- line has a match past the right edge

local function key_of(url) return url.domain .. "\0" .. tostring(url.path) end

local function fallback(job)
	return (job.mime == "application/json" or job.mime == "application/ndjson") and "json" or "code"
end

local function target(rec, i)
	local t = math.max(0, rec.m[i][1] - 1 - rec.ctx)
	return rec.max and math.min(t, rec.max) or t
end

local function visible(rec, i)
	local l = rec.m[i] and rec.m[i][1]
	return l and l > rec.pos and l <= rec.pos + rec.h
end

local function first_visible(rec)
	for i = 1, #rec.m do
		if visible(rec, i) then
			return i
		elseif rec.m[i][1] > rec.pos + rec.h then
			break
		end
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

-- Matches of `query` in `path`, with the flags yazi uses for
-- `search --via=rg` (extra `--args` given to `search` are unknown here).
local function find(query, path)
	local out, err = Command("rg")
		:arg({ "--color=never", "--line-number", "--column", "--only-matching", "--no-filename", "--smart-case" })
		:arg({ "-e", query, "--", path })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()
	if not out then
		ya.err("search-jump: rg: " .. tostring(err))
		return {}, {}
	end

	local m, at = {}, {}
	for ls, cs, text in out.stdout:gmatch("(%d+):(%d+):([^\n]*)") do
		local l, c = tonumber(ls), tonumber(cs)
		if #text > 0 then
			m[#m + 1] = { l, c, c + #text }
			at[l] = at[l] or #m
		end
	end
	return m, at
end

-- Wrap the byte ranges `spans` ({ from, to, sgr }, columns of the uncolored
-- line) of the ANSI string `s` in their SGR codes. bat resets after every
-- token, so the code is re-applied after each escape inside a range, and the
-- token's own escapes are replayed after a range ends.
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

local function spans_of(rec, line)
	local spans, i = {}, rec.at[line]
	while i and rec.m[i] and rec.m[i][1] == line do
		spans[#spans + 1] = { rec.m[i][2], rec.m[i][3], i == rec.cur and not rec.blink and HL_CUR or HL, i }
		i = i + 1
	end
	return spans
end

-- Render lines skip+1 .. skip+h of the file with bat and highlight the matches.
-- Returns true when rendered, false when bat is unavailable.
local function render(job, rec, path)
	local skip, h = job.skip, job.area.h
	local out = Command("bat")
		:arg({ "--color=always", "--style=plain", "--paging=never", "--wrap=never", "--tabs=0" })
		:arg({ "--line-range", string.format("%d:%d", skip + 1, skip + h), "--", path })
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:output()
	if not out or not out.status.success then
		return false
	end

	local tab = string.rep(" ", rt.preview.tab_size)
	local function expand(s) return (s:gsub("\r", ""):gsub("\t", tab)) end

	-- per row: display width and the rightmost display column of a match;
	-- cur_from/cur_to: display columns of the current match when on screen
	local lines, widths, ends, cur_from, cur_to = {}, {}, {}, nil, nil
	for s in out.stdout:gmatch("([^\n]*)\n") do
		local n, plain = skip + #lines + 1, s:gsub("\27%[[%d;]*m", "")
		local spans = spans_of(rec, n)
		lines[#lines + 1] = expand(mark(s, spans))
		widths[#lines], ends[#lines] = ui.width(expand(plain)), 0
		for _, sp in ipairs(spans) do
			local from = ui.width(expand(plain:sub(1, sp[1] - 1)))
			local to = from + ui.width(expand(plain:sub(sp[1], sp[2] - 1)))
			ends[#lines] = math.max(ends[#lines], to)
			if sp[4] == rec.cur then
				cur_from, cur_to = from, to
			end
		end
	end

	if skip > 0 and #lines < h then
		local bound = math.max(0, skip + #lines - h)
		set_pos(key_of(job.file.url), bound, bound)
		ya.emit("peek", { bound, only_if = job.file.url, upper_bound = true })
		return true
	end

	-- Scroll the whole view sideways when the current match ends past the
	-- right edge, leaving MARGIN columns of context to its left.
	local area, x = job.area, 0
	if cur_to and cur_to > area.w then
		x = math.max(0, cur_from - math.min(MARGIN, area.w // 4))
	end

	local widgets = { ui.Text.parse(table.concat(lines, "\n")):area(area):scroll(x, 0) }
	for r = 1, #lines do
		local y = area.y + r - 1
		if x > 0 and widths[r] > 0 then
			widgets[#widgets + 1] = ui.Text.parse(CUT_LEFT):area(ui.Rect { x = area.x, y = y, w = 1, h = 1 })
		end
		if ends[r] > x + area.w then
			widgets[#widgets + 1] =
				ui.Text.parse(MORE_RIGHT):area(ui.Rect { x = area.x + area.w - 1, y = y, w = 1, h = 1 })
		end
	end
	ya.preview_widget(job, widgets)
	return true
end

function M:peek(job)
	local url = job.file.url
	if not url.is_search then
		return require(fallback(job)):peek(job)
	end

	local key, path = key_of(url), tostring(url.path)
	local mtime = job.file.cha.mtime or 0
	local rec = get(key)
	if not rec or rec.mtime ~= mtime or rec.h ~= job.area.h then
		-- a changed file (e.g. after editing it) keeps its position
		local old = rec
		rec = { mtime = mtime, ctx = job.area.h // 4, h = job.area.h }
		rec.m, rec.at = find(url.domain, path)
		if old then
			rec.pos = old.pos
			rec.cur = first_visible(rec) or 1
		else
			rec.cur = 1
			rec.pos = rec.m[1] and target(rec, 1) or 0
		end
		put(key, rec)
	end

	if job.skip ~= rec.pos then
		return ya.emit("peek", { rec.pos, only_if = url })
	end

	if render(job, rec, path) then
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
	elseif not h.url.is_search then
		return require("code"):seek(job)
	end

	local step = math.floor(job.units * job.area.h / 10)
	step = step == 0 and ya.clamp(-1, job.units, 1) or step

	local skip = math.max(0, cx.active.preview.skip + step)
	local rec = self.files and self.files[key_of(h.url)]
	if rec then
		skip = rec.max and math.min(skip, rec.max) or skip
		rec.pos = skip
		if not visible(rec, rec.cur) then
			rec.cur = first_visible(rec) or rec.cur
		end
	end
	ya.emit("peek", { skip, only_if = job.file.url })
end

-- Show the current match briefly in the plain match color, then restore it:
-- the feedback for next/prev at the last/first match (no wrap-around).
local function blink(rec, url)
	local u = Url(url)
	rec.blink = true
	ya.emit("peek", { rec.pos, only_if = Url(u), force = true })
	ya.async(function()
		ya.sleep(BLINK)
		rec.blink = nil
		ya.emit("peek", { rec.pos, only_if = u, force = true })
	end)
end

local function jump(rec, url, action)
	local n, pick = #rec.m, nil
	if visible(rec, rec.cur) then
		pick = action == "next" and rec.cur + 1 or rec.cur - 1
		if pick < 1 or pick > n then
			return blink(rec, url)
		end
	elseif action == "next" then
		for i = 1, n do
			if target(rec, i) > rec.pos then
				pick = i
				break
			end
		end
	else
		for i = n, 1, -1 do
			if target(rec, i) < rec.pos then
				pick = i
				break
			end
		end
	end
	if not pick then
		return -- scrolled past the last (first) match: nothing further that way
	end

	rec.cur, rec.pos = pick, target(rec, pick)
	-- force: the skip is unchanged when the next match is on the same line
	ya.emit("peek", { rec.pos, only_if = Url(url), force = true })
end

-- Open $VISUAL/$EDITOR at the current match, else at the first line of the
-- preview. yazi waits for the editor (`shell --block`), so quitting it
-- returns to the unchanged search list.
local function edit(rec, url)
	local line, col = rec.pos + 1, 1
	local i = visible(rec, rec.cur) and rec.cur or first_visible(rec)
	if i then
		line, col = rec.m[i][1], rec.m[i][2]
	end

	local editor = os.getenv("VISUAL") or os.getenv("EDITOR") or "vi"
	if editor == "" then
		editor = "vi"
	end
	local name, path = editor:match("([^/%s]+)%s*$") or editor, ya.quote(tostring(url.path))
	local cmd
	if name == "nvim" or name == "vim" or name == "vi" then
		cmd = string.format("%s %s -- %s", editor, ya.quote(string.format("+call cursor(%d,%d)", line, col)), path)
	elseif name == "hx" or name == "helix" then
		cmd = string.format("%s %s", editor, ya.quote(string.format("%s:%d:%d", tostring(url.path), line, col)))
	else
		cmd = string.format("%s +%d %s", editor, line, path)
	end
	ya.emit("shell", { cmd, block = true })
end

function M:entry(job)
	local action = job.args[1]
	if action ~= "next" and action ~= "prev" and action ~= "open" then
		return ya.notify {
			title = "Search jump",
			content = "Usage: plugin search-jump-legacy -- next|prev|open",
			timeout = 5,
			level = "error",
		}
	end

	-- Nothing to act on (not a search, a directory, no match in this file):
	-- behave like yazi's default binding, so the plugin can take those keys.
	local h = cx.active.current.hovered
	local rec = h and h.url.is_search and not h.cha.is_dir and self.files and self.files[key_of(h.url)]
	if not rec or #rec.m == 0 then
		if action == "open" then
			return ya.emit("open", {})
		end
		return ya.emit("find_arrow", { previous = action == "prev" })
	end

	if action == "open" then
		edit(rec, h.url)
	else
		jump(rec, h.url, action)
	end
end

return M
