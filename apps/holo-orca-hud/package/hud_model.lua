local M = {}

local function clamp(value, lower, upper)
  if value < lower then return lower end
  if value > upper then return upper end
  return value
end

function M.axis_delta(raw, center)
  return (tonumber(raw) or 0) - (tonumber(center) or 0)
end

function M.vertical_motion_pulse(raw_roll, previous_roll, anchor_roll, latched, flick_degrees, sudden_degrees, rearm_degrees)
  local current = tonumber(raw_roll) or 0
  local previous = tonumber(previous_roll)
  if previous == nil then return 0, current, current, false end

  local anchor = tonumber(anchor_roll)
  if anchor == nil then anchor = previous end
  local flick = math.max(1, math.abs(tonumber(flick_degrees) or 10))
  local sudden = math.max(1, math.abs(tonumber(sudden_degrees) or 3))
  local rearm = math.min(flick, math.abs(tonumber(rearm_degrees) or math.floor(flick / 3)))

  if latched then
    if math.abs(current - anchor) <= rearm then return 0, current, current, false end
    return 0, current, anchor, true
  end

  local excursion = anchor - current
  local motion = previous - current
  if math.abs(excursion) <= rearm and math.abs(motion) < sudden then
    return 0, current, current, false
  end
  if math.abs(excursion) >= flick and math.abs(motion) >= sudden and excursion * motion > 0 then
    return (excursion > 0 and 1 or -1), current, anchor, true
  end
  return 0, current, anchor, false
end

function M.rate_limit_pulse(pulse, now, next_allowed_at, cooldown_ms)
  local direction = tonumber(pulse) or 0
  local current = math.max(0, math.floor(tonumber(now) or 0))
  local next_allowed = math.max(0, math.floor(tonumber(next_allowed_at) or 0))
  local cooldown = math.max(1, math.floor(tonumber(cooldown_ms) or 1000))
  if direction == 0 or current < next_allowed then return 0, next_allowed end
  return direction, current + cooldown
end

function M.move_selection_pulse(index, count, pulse)
  local total = math.max(0, math.floor(tonumber(count) or 0))
  if total == 0 then return 1, false end
  local selected = clamp(math.floor(tonumber(index) or 1), 1, total)
  local direction = tonumber(pulse) or 0
  if direction == 0 then return selected, false end
  local moved = clamp(selected + (direction > 0 and 1 or -1), 1, total)
  return moved, moved ~= selected
end

function M.move_scroll_pulse(scroll, max_scroll, pulse)
  local maximum = math.max(0, math.floor(tonumber(max_scroll) or 0))
  local offset = clamp(math.max(0, math.floor(tonumber(scroll) or 0)), 0, maximum)
  local direction = tonumber(pulse) or 0
  if direction == 0 then return offset, false end
  local next_offset = clamp(offset + (direction < 0 and 1 or -1), 0, maximum)
  return next_offset, next_offset ~= offset
end

function M.move_selection(index, count, physical_axis, latched, engage_threshold, release_threshold)
  local total = math.max(0, math.floor(tonumber(count) or 0))
  if total == 0 then return 1, false, false end
  local selected = clamp(math.floor(tonumber(index) or 1), 1, total)
  local axis = tonumber(physical_axis) or 0
  local engage = math.max(1, math.abs(tonumber(engage_threshold) or 24))
  local release = math.min(engage, math.abs(tonumber(release_threshold) or math.floor(engage / 2)))
  if math.abs(axis) <= release then return selected, false, false end
  if latched then return selected, true, false end
  if math.abs(axis) < engage then return selected, false, false end
  local moved = clamp(selected + (axis > 0 and 1 or -1), 1, total)
  return moved, true, moved ~= selected
end

function M.move_page(index, physical_horizontal, latched, engage_threshold, release_threshold)
  return M.move_selection(index, 3, physical_horizontal, latched, engage_threshold, release_threshold)
end

function M.move_scroll(scroll, max_scroll, physical_vertical, latched, engage_threshold, release_threshold)
  local total = math.max(0, math.floor(tonumber(max_scroll) or 0)) + 1
  local next_index, next_latched, changed = M.move_selection(
    math.max(0, math.floor(tonumber(scroll) or 0)) + 1,
    total,
    -(tonumber(physical_vertical) or 0),
    latched,
    engage_threshold,
    release_threshold
  )
  return next_index - 1, next_latched, changed
end

function M.move_scroll_repeat(scroll, max_scroll, physical_vertical, now, next_repeat_at, engage_threshold, release_threshold, repeat_ms)
  local maximum = math.max(0, math.floor(tonumber(max_scroll) or 0))
  local offset = clamp(math.max(0, math.floor(tonumber(scroll) or 0)), 0, maximum)
  local axis = tonumber(physical_vertical) or 0
  local current = math.max(0, math.floor(tonumber(now) or 0))
  local engage = math.max(1, math.abs(tonumber(engage_threshold) or 24))
  local release = math.min(engage, math.abs(tonumber(release_threshold) or math.floor(engage / 2)))
  local interval = math.max(1, math.floor(tonumber(repeat_ms) or 200))
  if math.abs(axis) <= release or math.abs(axis) < engage then return offset, 0, false end
  local due = math.max(0, math.floor(tonumber(next_repeat_at) or 0))
  if due > current then return offset, due, false end
  local next_offset = clamp(offset + (axis < 0 and 1 or -1), 0, maximum)
  return next_offset, current + interval, next_offset ~= offset
end

function M.session_indicator(session)
  session = type(session) == "table" and session or {}
  local agent = tostring(session.agentState or session.status or "idle"):lower()
  local status = tostring(session.status or ""):lower()

  if agent == "blocked" or agent == "interrupted" or agent == "error" or status == "blocked" then
    return "red", "ATTENTION"
  end
  if not session.canActivate then return "muted", "OFFLINE" end
  if agent == "working" or status == "working" then return "amber", "WORKING" end
  return "green", "DONE"
end

function M.compact_session_meta(session)
  session = type(session) == "table" and session or {}
  local tone, label = M.session_indicator(session)
  local terminals = math.max(0, math.floor(tonumber(session.terminalCount) or 0))
  local terminal_label = session.canActivate and (tostring(terminals) .. "T") or "NO TERM"
  local focus = session.focused and "FOCUSED / " or ""
  return tone, focus .. label .. " / " .. terminal_label
end

function M.transcript_lines(payload, max_lines, max_width)
  payload = type(payload) == "table" and payload or {}
  local source = type(payload.lines) == "table" and payload.lines or {}
  local line_limit = math.max(1, math.floor(tonumber(max_lines) or 8))
  local width = math.max(1, math.floor(tonumber(max_width) or 42))
  local compact = {}
  for _, line in ipairs(source) do
    local value = type(line) == "table" and (line.text or line.content or line.line) or line
    local clean = tostring(value or ""):gsub("\27%[[%d;?]*[%a]", ""):gsub("[%c]+", " "):gsub("%s+", " ")
    clean = clean:gsub("^%s+", ""):gsub("%s+$", "")
    if clean ~= "" then
      if #clean > width then clean = clean:sub(1, math.max(1, width - 1)) .. "." end
      table.insert(compact, clean)
    end
  end
  local first = math.max(1, #compact - line_limit + 1)
  local tail = {}
  for index = first, #compact do table.insert(tail, compact[index]) end
  return tail
end

local function wrap_terminal_row(value, width)
  local rows = {}
  local indent = value:match("^(%s*)") or ""
  local remaining = value
  while #remaining > width do
    local prefix = remaining:sub(1, width + 1)
    local cut = prefix:match("^.*()%s") or width
    if cut <= #indent then cut = width end
    local row = remaining:sub(1, cut):gsub("%s+$", "")
    if row == "" then row = remaining:sub(1, width) end
    table.insert(rows, row)
    remaining = remaining:sub(cut + 1):gsub("^%s+", "")
    if remaining ~= "" then remaining = indent .. remaining end
  end
  if remaining ~= "" then table.insert(rows, remaining) end
  return rows
end

function M.terminal_lines(payload, max_lines, max_width)
  payload = type(payload) == "table" and payload or {}
  local source = type(payload.lines) == "table" and payload.lines or {}
  local line_limit = math.max(1, math.floor(tonumber(max_lines) or 35))
  local width = math.max(1, math.floor(tonumber(max_width) or 42))
  local visual = {}
  local previous_blank = false
  for _, line in ipairs(source) do
    local value = type(line) == "table" and (line.text or line.content or line.line) or line
    local clean = tostring(value or ""):gsub("\27%[[%d;?]*[%a]", ""):gsub("\r", ""):gsub("\t", "  ")
    clean = clean:gsub("%s+$", "")
    if clean == "" then
      if not previous_blank then table.insert(visual, "") end
      previous_blank = true
    else
      previous_blank = false
      for _, row in ipairs(wrap_terminal_row(clean, width)) do table.insert(visual, row) end
    end
  end
  local first = math.max(1, #visual - line_limit + 1)
  local tail = {}
  for index = first, #visual do table.insert(tail, visual[index]) end
  return tail
end

function M.transcript_tone(line)
  local value = tostring(line or "")
  local lower = value:lower()
  if lower:match("error") or lower:match("failed") or lower:match("exception") or lower:match("fatal") then return "red" end
  if lower:match("warning") or lower:match("caution") then return "amber" end
  if value:match("^%s*[$>%%]") or value:match("^%s*❯") then return "blue" end
  if lower:match("success") or lower:match("passed") or lower:match("complete") or lower:match("deployed") then return "green" end
  if value:match("^%s+") then return "dim" end
  return "white"
end

function M.transcript_window(lines, scroll, visible_lines)
  local source = type(lines) == "table" and lines or {}
  local visible = math.max(1, math.floor(tonumber(visible_lines) or 7))
  local max_scroll = math.max(0, #source - visible)
  local offset = clamp(math.max(0, math.floor(tonumber(scroll) or 0)), 0, max_scroll)
  local first = math.max(1, #source - visible - offset + 1)
  local last = math.min(#source, first + visible - 1)
  local window = {}
  for index = first, last do table.insert(window, source[index]) end
  return window, offset, max_scroll
end

function M.row_layout(row_y)
  local y = math.floor(tonumber(row_y) or 0)
  return {
    title_y = y + 3,
    meta_y = y + 19,
    title_font = 12,
    meta_font = 10,
  }
end

function M.render_due(now, last_render, dirty, interval)
  return dirty == true
end

function M.request_allowed(status_inflight, weather_inflight, transcript_inflight)
  return not status_inflight and not weather_inflight and not transcript_inflight
end

function M.transport_error_label(kind, code)
  local numeric_code = tonumber(code)
  if numeric_code == nil or numeric_code == 0 or numeric_code == -1 then return "BRIDGE OFFLINE" end
  if numeric_code == 502 then return "ORCA DESKTOP OFFLINE" end
  if tostring(kind or "") == "transcript" then return "TRANSCRIPT UNAVAILABLE" end
  return "BRIDGE ERROR"
end

function M.next_poll(page, now, last_status_poll, last_transcript_poll, status_interval, transcript_interval)
  local current = math.max(0, math.floor(tonumber(now) or 0))
  local status_last = math.max(0, math.floor(tonumber(last_status_poll) or 0))
  local transcript_last = math.max(0, math.floor(tonumber(last_transcript_poll) or 0))
  local status_every = math.max(1, math.floor(tonumber(status_interval) or 5000))
  local transcript_every = math.max(1, math.floor(tonumber(transcript_interval) or status_every))
  if tostring(page or "") == "chat" and current - transcript_last >= transcript_every then
    return "transcript"
  end
  if current - status_last >= status_every then return "status" end
  return nil
end

function M.transcript_layout()
  return {
    section_label_y = 39,
    session_y = 48,
    session_h = 32,
    session_icon_y = 55,
    session_title_y = 52,
    session_meta_y = 68,
    session_dot_y = 60,
    panel_y = 87,
    panel_h = 121,
    text_x = 20,
    text_y = 104,
    text_w = 276,
    line_step = 13,
    font_size = 10,
    font_line_h = 10,
    visible_lines = 8,
    bottom_padding = 3,
    history_label_y = 91,
    notice_y = 113,
  }
end

function M.canvas_layout()
  return {
    width = 320,
    height = 240,
    header_y = 9,
    footer_y = 214,
    home = {
      host_label_y = 75,
      host_row_y = 84,
      resume_label_y = 124,
      resume_row_y = 133,
      system_label_y = 173,
      system_row_y = 181,
      system_row_h = 27,
    },
    sessions = {
      first_row_y = 55,
      row_step = 36,
      row_h = 35,
    },
  }
end

return M
