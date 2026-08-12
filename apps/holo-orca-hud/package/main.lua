local APP_KEY = "HOLO_ORCA_HUD_APP"
local previous = rawget(_G, APP_KEY)
if previous and previous.stop then pcall(function() previous.stop("reload") end) end

local app_api = rawget(_G, "app")
local key_api = rawget(_G, "key")
local tmr_api = rawget(_G, "tmr")
local http_api = rawget(_G, "http")
local file_api = rawget(_G, "file")
local time_api = rawget(_G, "time")
local sys_api = rawget(_G, "sys")
local wifi_api = rawget(_G, "wifi")
local JSON = rawget(_G, "sjson") or rawget(_G, "json")
local hud = dofile("/sd/apps/holo-orca-hud/hud_model.lua")

local canvas_create = rawget(_G, "lv_canvas_create")
local canvas_begin = rawget(_G, "lv_canvas_frame_begin") or rawget(_G, "lv_canvas_begin")
local canvas_end = rawget(_G, "lv_canvas_frame_end") or rawget(_G, "lv_canvas_end")
local canvas_fill = rawget(_G, "lv_canvas_fill_bg") or rawget(_G, "lv_canvas_fill")
local canvas_rect = rawget(_G, "lv_canvas_draw_rect")
local canvas_text = rawget(_G, "lv_canvas_draw_text")
local canvas_img = rawget(_G, "lv_canvas_draw_img")
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR")
local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local LIFECYCLE_PATH = "/sd/apps/holo-orca-hud/lifecycle.txt"
local L = hud.canvas_layout()
local TRANSCRIPT = hud.transcript_layout()
local CHAT_HISTORY_LIMIT = 8
local CHAT_VISIBLE_LINES = TRANSCRIPT.visible_lines
local CHAT_TEXT_WIDTH = 42
local C = {
  base = 0x3A3C3F,
  glass_bottom = 0x484D53,
  glass_mid = 0x575C60,
  glass_top = 0x66696D,
  glass_edge = 0x717274,
  glass_shadow = 0x191D22,
  glass_highlight = 0x757678,
  white = 0xF4F7FB,
  muted = 0xC1C9D4,
  dim = 0x929CAA,
  blue = 0x78A7FF,
  green = 0x65D6A2,
  amber = 0xFFC776,
  red = 0xFF9298,
  purple = 0xC6A4FF,
}

local function call(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function decode_json(raw)
  if not JSON or not JSON.decode then return nil end
  local ok, doc = pcall(JSON.decode, raw)
  if ok and type(doc) == "table" then return doc end
  return nil
end

local function encode_json(value)
  if not JSON or not JSON.encode then return nil end
  local ok, raw = pcall(JSON.encode, value)
  if ok and type(raw) == "string" then return raw end
  return nil
end

local function trim(value, limit)
  local text = tostring(value or ""):gsub("[%c]+", " "):gsub("%s+", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if #text > limit then return text:sub(1, math.max(1, limit - 1)) .. "." end
  return text
end

local function url_encode(value)
  return tostring(value or ""):gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)
end

local function read_settings()
  if not file_api or not file_api.getcontents then return {} end
  local ok, raw = pcall(file_api.getcontents, "/sd/apps/settings.json")
  return ok and decode_json(raw) or {}
end

local settings = read_settings()
if time_api and time_api.settimezone and settings.timezone then pcall(time_api.settimezone, settings.timezone) end

local connection = {}
local loaded, value = pcall(dofile, "/sd/apps/holo-orca-hud/connection.lua")
if loaded and type(value) == "table" then connection = value end

local APP = {
  poll_ms = 5000,
  transcript_poll_ms = 5000,
  native_http_timeout_ms = 5000,
  transcript_timeout_ms = 7000,
  tick_ms = 75,
  system_poll_ms = 1000,
  horizontal_threshold = 36,
  horizontal_release_threshold = 18,
  vertical_flick_degrees = 10,
  vertical_sudden_degrees = 3,
  vertical_rearm_degrees = 3,
  vertical_action_cooldown_ms = 1000,
  neutral_pitch = nil,
  raw_roll = 0,
  raw_pitch = 0,
  vertical_previous_roll = nil,
  vertical_anchor_roll = nil,
  vertical_latched = false,
  vertical_pulse = 0,
  vertical_action_ready_at = 0,
  page = 1,
  page_latched = false,
  selected = 1,
  sessions = {},
  orca = { running = false, reachable = false, state = "waiting" },
  network = "NET WAIT",
  firmware = "FW --",
  base_url = tostring(connection.base_url or ""),
  token = tostring(connection.token or ""),
  status_inflight = false,
  status_started = 0,
  status_task = nil,
  transcript_inflight = false,
  request_seq = 0,
  transcript_seq = 0,
  last_status_body = nil,
  last_poll = 0,
  last_transcript_poll = 0,
  transcript_started = 0,
  last_system_poll = 0,
  clock_value = "--:--",
  render_dirty = true,
  notice = "STARTING",
  notice_until = 0,
  active = true,
  timer = nil,
  root = nil,
  canvas = nil,
  transcript_scroll = 0,
  transcript = { session_id = nil, lines = {}, history = {}, loading = false, error = nil },
}
_G[APP_KEY] = APP

local function clock_ms()
  if tmr_api and tmr_api.now then return math.floor((tonumber(tmr_api.now()) or 0) / 1000) end
  return 0
end

local function mark_dirty()
  APP.render_dirty = true
end

local function record_lifecycle(event)
  if file_api and file_api.putcontents then
    call(file_api.putcontents, LIFECYCLE_PATH, trim(event, 180))
  end
end

local function record_runtime_error(err)
  local detail = trim(tostring(err or "runtime error"), 180)
  if file_api and file_api.putcontents then
    call(file_api.putcontents, "/sd/apps/holo-orca-hud/runtime-error.txt", detail)
    record_lifecycle("error: " .. detail)
  end
  APP.notice = "UI ERROR"
  APP.notice_until = clock_ms() + 60000
end

local function guard_callback(name, fn)
  return function(...)
    local args = { ... }
    local count = select("#", ...)
    local unpack_args = table.unpack or unpack
    local ok, err = xpcall(function()
      return fn(unpack_args(args, 1, count))
    end, function(value) return tostring(value) end)
    if not ok then record_runtime_error(tostring(name or "callback") .. ": " .. tostring(err)) end
  end
end

local function set_notice(text, duration)
  APP.notice = trim(text, 48)
  APP.notice_until = clock_ms() + (duration or 2200)
  mark_dirty()
end

local function asset(name)
  return "/sd/apps/holo-orca-hud/assets/" .. name
end

local function canvas_frame_begin(canvas)
  if not canvas then return false end
  if canvas_begin and canvas_end then
    local ok = call(canvas_begin, canvas)
    return ok and true or false
  end
  return false
end

local function canvas_frame_end(canvas, explicit_frame)
  if explicit_frame and canvas_end then
    call(canvas_end, canvas)
    return
  end
  call(rawget(_G, "lv_obj_invalidate"), canvas)
end

local function draw_rect(x, y, width, height, color, opa)
  if width <= 0 or height <= 0 then return end
  call(canvas_rect, APP.canvas, x, y, width, height, color, opa or 255)
end

local function draw_panel_rect(x, y, width, height, descriptor)
  if width <= 0 or height <= 0 then return end
  call(canvas_rect, APP.canvas, x, y, width, height, descriptor)
end

local function draw_glass_panel(x, y, width, height, selected)
  local radius = math.max(4, math.min(9, math.floor(math.min(width, height) / 3)))
  if selected then
    draw_panel_rect(x - 2, y - 2, width + 4, height + 4, {
      bg_color = C.blue, bg_opa = 24, radius = radius + 2,
      border_width = 1, border_color = C.blue, border_opa = 112,
    })
  end
  draw_panel_rect(x + 1, y + 2, width, height, {
    bg_color = C.glass_shadow, bg_opa = 28, radius = radius,
  })
  draw_panel_rect(x, y, width, height, {
    bg_color = C.glass_bottom, bg_opa = 178, radius = radius,
    border_width = 1, border_color = selected and C.blue or C.glass_edge,
    border_opa = selected and 235 or 168,
  })
  local inner_x, inner_y = x + 3, y + 3
  local inner_w, inner_h = width - 6, height - 6
  draw_rect(inner_x, inner_y, inner_w, math.max(1, math.floor(inner_h * 0.30)), C.glass_top, 90)
  draw_rect(inner_x, inner_y + math.max(1, math.floor(inner_h * 0.30)), inner_w,
    math.max(1, math.floor(inner_h * 0.32)), C.glass_mid, 52)
  draw_rect(x + radius, y + 1, math.max(1, width - radius * 2), 1, C.glass_highlight, 190)
end

local function draw_text(x, y, width, text, color, font_size)
  call(canvas_text, APP.canvas, x, y, width, trim(text, 48), {
    color = color or C.white,
    opa = 255,
    font_size = font_size or 12,
  })
end

local function draw_img(name, x, y)
  call(canvas_img, APP.canvas, x, y, asset(name), { opa = 255 })
end

local function draw_dot(x, y, tone)
  draw_panel_rect(x, y, 7, 7, {
    bg_color = C[tone] or C.muted, bg_opa = 255, radius = 4,
    border_width = 1, border_color = C.glass_highlight, border_opa = 84,
  })
end

local function request_options()
  return {
    headers = {
      ["Authorization"] = "Bearer " .. APP.token,
      ["Accept"] = "application/json",
      ["Content-Type"] = "application/json",
      ["Cache-Control"] = "no-cache",
      ["Connection"] = "close",
    },
    timeout = APP.native_http_timeout_ms,
    bufsz = 4096,
  }
end

local function endpoint(path)
  return APP.base_url:gsub("/$", "") .. path
end

local function valid_connection()
  return APP.base_url:match("^http://") ~= nil and #APP.token >= 16
end

local function clock_text()
  if time_api and time_api.getlocal then
    local ok, local_time = pcall(time_api.getlocal)
    if ok and type(local_time) == "table" and local_time.hour then
      return string.format("%02d:%02d", tonumber(local_time.hour) or 0, tonumber(local_time.min) or 0)
    end
  end
  return "--:--"
end

local function refresh_clock()
  local next_clock = clock_text()
  if next_clock == APP.clock_value then return false end
  APP.clock_value = next_clock
  mark_dirty()
  return true
end

local function refresh_device_status()
  local previous_network, previous_firmware = APP.network, APP.firmware
  APP.network = "NET DOWN"
  if wifi_api and wifi_api.sta and wifi_api.sta.getip then
    local ok, ip = pcall(wifi_api.sta.getip)
    if ok and ip then APP.network = "NET LINK" end
  end
  APP.firmware = "FW --"
  if sys_api and sys_api.version then
    local ok, version = pcall(sys_api.version)
    if ok and version then APP.firmware = "FW " .. trim(version, 12) end
  end
  return APP.network ~= previous_network or APP.firmware ~= previous_firmware
end

local function working_count()
  local total = 0
  for _, session in ipairs(APP.sessions) do
    if session.status == "working" or session.agentState == "working" then total = total + 1 end
  end
  return total
end

local function focused_session()
  for _, session in ipairs(APP.sessions) do
    if session.focused then return session end
  end
  return nil
end

local function selected_session()
  return APP.sessions[APP.selected]
end

local function bridge_tone()
  if APP.orca.reachable then return "green" end
  if APP.orca.running then return "amber" end
  return "red"
end

local function session_meta(session)
  return hud.compact_session_meta(session)
end

local function draw_header()
  draw_glass_panel(12, 5, 296, 25, false)
  draw_img("orca-logo.png", 12, L.header_y)
  draw_text(47, 10, 88, "ORCA", C.white, 14)
  draw_dot(256, 15, bridge_tone())
  draw_text(270, 13, 40, APP.clock_value, C.muted, 10)
end

local function draw_tile(index, icon_name, value, label)
  local x = 12 + (index - 1) * 102
  draw_glass_panel(x, 35, 92, 31, false)
  draw_img(icon_name, x + 6, 42)
  draw_text(x + 31, 37, 55, trim(value, 5), C.white, 14)
  draw_text(x + 31, 53, 55, trim(label, 9), C.muted, 8)
end

local function draw_row(y, height, icon_name, title, meta, tone, selected, chevron)
  draw_glass_panel(12, y, 296, height, selected)
  draw_img(icon_name, 18, y + math.floor((height - 18) / 2))
  draw_text(45, y + 3, 204, trim(title, 28), C.white, 12)
  if meta and meta ~= "" then draw_text(45, y + 19, 204, trim(meta, 24), C.muted, 10) end
  draw_dot(260, y + math.floor((height - 6) / 2), tone)
  if chevron then draw_img("chevron-right.png", 281, y + math.floor((height - 18) / 2)) end
end

local function draw_system_row()
  local text = trim(APP.network .. " / " .. APP.firmware, 34)
  draw_glass_panel(12, L.home.system_row_y, 296, L.home.system_row_h, false)
  draw_img("monitor.png", 18, L.home.system_row_y + 4)
  draw_text(45, L.home.system_row_y + 8, 208, text, C.muted, 10)
  draw_dot(260, L.home.system_row_y + 10, APP.network == "NET LINK" and "green" or "amber")
end

local function draw_footer()
  draw_glass_panel(12, L.footer_y + 1, 296, 20, false)
  local now = clock_ms()
  local hint
  if now < APP.notice_until then
    hint = APP.notice
  elseif APP.page == 1 then
    hint = "RIGHT: SESSIONS  PRESS: REFRESH"
  elseif APP.page == 2 then
    hint = "FLICK UP/DOWN  RIGHT: CHAT  LEFT: HOME"
  else
    hint = "FLICK UP/DOWN SCROLL  LEFT: BACK"
  end
  draw_text(18, 220, 284, trim(hint, 42), C.muted, 8)
end

local function draw_home()
  local focused = focused_session()
  draw_tile(1, "terminal.png", tostring(working_count()), "WORKING")
  draw_tile(2, "monitor.png", tostring(#APP.sessions), "SESSIONS")
  draw_tile(3, "terminal.png", focused and "1" or "0", "FOCUSED")
  draw_text(12, L.home.host_label_y, 120, "HOST", C.muted, 10)
  draw_text(12, L.home.resume_label_y, 160, "RESUME", C.muted, 10)
  draw_text(12, L.home.system_label_y, 160, "SYSTEM", C.muted, 10)

  local host_meta = APP.orca.reachable
    and ("CONNECTED / " .. tostring(#APP.sessions) .. " SESSIONS")
    or "BRIDGE OFFLINE"
  draw_row(L.home.host_row_y, 34, "monitor.png", "Mac", host_meta, bridge_tone(), false, true)

  if focused then
    local tone, meta = session_meta(focused)
    draw_row(L.home.resume_row_y, 34, "terminal.png", focused.label, meta, tone, false, true)
  else
    draw_row(L.home.resume_row_y, 34, "terminal.png", "No focused session", "SELECT IN SESSIONS", "muted", false, true)
  end
  draw_system_row()
end

local function draw_sessions()
  draw_text(12, 39, 148, "SESSIONS", C.muted, 10)
  draw_text(168, 39, 140, tostring(working_count()) .. " WORKING / " .. tostring(#APP.sessions) .. " ALL", C.muted, 10)
  if #APP.sessions == 0 then
    draw_row(L.sessions.first_row_y, L.sessions.row_h, "terminal.png", "No sessions found", "PRESS TO REFRESH", "muted", true, false)
    return
  end
  local first = math.max(1, APP.selected - 1)
  if first > math.max(1, #APP.sessions - 3) then first = math.max(1, #APP.sessions - 3) end
  for row = 1, 4 do
    local session = APP.sessions[first + row - 1]
    if session then
      local tone, meta = session_meta(session)
      draw_row(L.sessions.first_row_y + (row - 1) * L.sessions.row_step, L.sessions.row_h,
        "terminal.png", session.label, meta, tone, first + row - 1 == APP.selected, true)
    end
  end
end

local function draw_transcript()
  draw_text(12, TRANSCRIPT.section_label_y, 148, "TRANSCRIPT", C.muted, 10)
  local session = APP.sessions[APP.selected]
  if not session then
    draw_row(55, 35, "terminal.png", "No session selected", "BACK TO SESSIONS", "muted", true, false)
    return
  end

  local tone, meta = session_meta(session)
  draw_glass_panel(12, TRANSCRIPT.session_y, 296, TRANSCRIPT.session_h, true)
  draw_img("terminal.png", 18, TRANSCRIPT.session_icon_y)
  draw_text(45, TRANSCRIPT.session_title_y, 204, trim(session.label, 28), C.white, 12)
  draw_text(45, TRANSCRIPT.session_meta_y, 204, trim(meta, 24), C.muted, 8)
  draw_dot(260, TRANSCRIPT.session_dot_y, tone)
  draw_glass_panel(12, TRANSCRIPT.panel_y, 296, TRANSCRIPT.panel_h, false)
  draw_text(20, TRANSCRIPT.history_label_y, 170, "RECENT OUTPUT", C.dim, 8)

  if not session.canActivate then
    draw_text(TRANSCRIPT.text_x, TRANSCRIPT.notice_y, TRANSCRIPT.text_w, "NO CONNECTED TERMINAL", C.muted, TRANSCRIPT.font_size)
    return
  end
  if APP.transcript.error and APP.transcript.error ~= "" then
    draw_text(TRANSCRIPT.text_x, TRANSCRIPT.notice_y, TRANSCRIPT.text_w, APP.transcript.error, C.muted, TRANSCRIPT.font_size)
    return
  end
  if APP.transcript.loading and #APP.transcript.lines == 0 then
    draw_text(TRANSCRIPT.text_x, TRANSCRIPT.notice_y, TRANSCRIPT.text_w, "LOADING TRANSCRIPT", C.muted, TRANSCRIPT.font_size)
    return
  end
  if APP.transcript.session_id ~= session.id or #APP.transcript.lines == 0 then
    draw_text(TRANSCRIPT.text_x, TRANSCRIPT.notice_y, TRANSCRIPT.text_w, "NO RECENT OUTPUT", C.muted, TRANSCRIPT.font_size)
    return
  end
  local window, scroll, max_scroll = hud.transcript_window(APP.transcript.lines, APP.transcript_scroll, CHAT_VISIBLE_LINES)
  APP.transcript_scroll = scroll
  for index, line in ipairs(window) do
    draw_text(TRANSCRIPT.text_x, TRANSCRIPT.text_y + (index - 1) * TRANSCRIPT.line_step,
      TRANSCRIPT.text_w, line, C.white, TRANSCRIPT.font_size)
  end
end

local function render()
  if not APP.active or not APP.canvas then return end
  local explicit_frame = canvas_frame_begin(APP.canvas)
  call(canvas_fill, APP.canvas, C.base, 255)
  draw_header()
  if APP.page == 1 then
    draw_home()
  elseif APP.page == 2 then
    draw_sessions()
  else
    draw_transcript()
  end
  draw_footer()
  canvas_frame_end(APP.canvas, explicit_frame)
end

local function build_canvas()
  local screen = rawget(_G, "lv_scr_act")
  APP.root = screen and screen() or nil
  if not APP.root or not canvas_create or not canvas_fill or not canvas_rect or not canvas_text or not canvas_img then
    APP.notice = "CANVAS UNAVAILABLE"
    return false
  end
  call(rawget(_G, "lv_obj_clean"), APP.root)
  call(rawget(_G, "lv_obj_set_style_bg_color"), APP.root, C.base, MAIN)
  call(rawget(_G, "lv_obj_set_style_bg_opa"), APP.root, 255, MAIN)
  if CANVAS_FMT then
    APP.canvas = canvas_create(APP.root, L.width, L.height, CANVAS_FMT)
  else
    APP.canvas = canvas_create(APP.root, L.width, L.height)
  end
  if not APP.canvas then
    APP.notice = "CANVAS ALLOC FAILED"
    return false
  end
  call(rawget(_G, "lv_obj_set_pos"), APP.canvas, 0, 0)
  return true
end

local function apply_status(doc, changed)
  if type(doc) ~= "table" or type(doc.sessions) ~= "table" or type(doc.orca) ~= "table" then
    set_notice("BAD BRIDGE DATA", 4000)
    return false
  end
  APP.sessions = doc.sessions
  APP.orca = doc.orca
  APP.selected = math.max(1, math.min(APP.selected, math.max(1, #APP.sessions)))
  local selected = selected_session()
  if not selected or APP.transcript.session_id ~= selected.id then
    APP.transcript_scroll = 0
    APP.transcript = { session_id = selected and selected.id or nil, lines = {}, history = {}, loading = false, error = nil }
  end
  if changed then mark_dirty() end
  return true
end

local function fetch_status()
  if not hud.request_allowed(APP.status_inflight, false, APP.transcript_inflight) then return false end
  if not valid_connection() then set_notice("CONFIG REQUIRED", 5000); return false end
  if not http_api or not http_api.get then set_notice("HTTP UNAVAILABLE", 5000); return false end
  APP.status_inflight = true
  APP.status_started = clock_ms()
  APP.status_task = "status"
  APP.request_seq = APP.request_seq + 1
  local request_id = APP.request_seq
  http_api.get(endpoint("/v1/status"), request_options(), guard_callback("status", function(code, body)
    if not APP.active or request_id ~= APP.request_seq then return end
    APP.status_inflight = false
    APP.status_started = 0
    APP.status_task = nil
    APP.last_poll = clock_ms()
    if code ~= 200 or type(body) ~= "string" then
      if tonumber(code) == -1 or tonumber(code) == 0 then APP.orca.reachable = false; mark_dirty() end
      set_notice(hud.transport_error_label("status", code) .. " / RETRYING", 4000)
      return
    end
    local changed = body ~= APP.last_status_body
    APP.last_status_body = body
    apply_status(decode_json(body), changed)
  end))
  return true
end

local function fetch_transcript()
  if APP.page ~= 3 then return false end
  local session = selected_session()
  if not session then
    APP.transcript_scroll = 0
    APP.transcript = { session_id = nil, lines = {}, history = {}, loading = false, error = nil }
    APP.last_transcript_poll = clock_ms()
    mark_dirty()
    return false
  end
  if not session.canActivate then
    APP.transcript_scroll = 0
    APP.transcript = { session_id = session.id, lines = {}, history = {}, loading = false, error = "NO CONNECTED TERMINAL" }
    APP.last_transcript_poll = clock_ms()
    mark_dirty()
    return false
  end
  if not hud.request_allowed(APP.status_inflight, false, APP.transcript_inflight) then return false end
  if not valid_connection() then set_notice("CONFIG REQUIRED", 5000); return false end
  if not http_api or not http_api.get then set_notice("HTTP UNAVAILABLE", 5000); return false end
  APP.transcript_inflight = true
  APP.transcript_seq = APP.transcript_seq + 1
  local request_id = APP.transcript_seq
  APP.transcript_started = clock_ms()
  APP.transcript = {
    session_id = session.id,
    lines = APP.transcript.lines or {},
    history = APP.transcript.history or {},
    loading = #(APP.transcript.lines or {}) == 0,
    error = nil,
  }
  mark_dirty()
  http_api.get(endpoint("/v1/transcript?id=" .. url_encode(session.id)), request_options(), guard_callback("transcript", function(code, body)
    if not APP.active or request_id ~= APP.transcript_seq then return end
    APP.transcript_inflight = false
    APP.transcript_started = 0
    APP.last_transcript_poll = clock_ms()
    if code ~= 200 or type(body) ~= "string" then
      APP.transcript.loading = false
      APP.transcript.error = code == 409 and "NO CONNECTED TERMINAL" or hud.transport_error_label("transcript", code)
      set_notice(APP.transcript.error, 3500)
      return
    end
    local doc = decode_json(body)
    local payload = doc and doc.transcript
    if type(payload) ~= "table" or type(payload.session) ~= "table" or payload.session.id ~= session.id then
      APP.transcript.loading = false
      APP.transcript.error = "TRANSCRIPT CHANGED"
      set_notice("BAD TRANSCRIPT DATA", 3500)
      return
    end
    local at_tail = APP.transcript_scroll == 0
    APP.transcript = {
      session_id = session.id,
      lines = hud.transcript_lines(payload, CHAT_HISTORY_LIMIT, CHAT_TEXT_WIDTH),
      history = type(payload.history) == "table" and payload.history or {},
      loading = false,
      error = nil,
    }
    local _, scroll = hud.transcript_window(APP.transcript.lines, APP.transcript_scroll, CHAT_VISIBLE_LINES)
    APP.transcript_scroll = at_tail and 0 or scroll
    mark_dirty()
  end))
  return true
end

local function focus_selected()
  local session = selected_session()
  if not session then set_notice("NO SESSION SELECTED", 3000); return end
  if not session.canActivate then set_notice("NO CONNECTED TERMINAL", 3500); return end
  if not hud.request_allowed(APP.status_inflight, false, APP.transcript_inflight)
      or not valid_connection() or not http_api or not http_api.post then
    set_notice("ORCA BRIDGE UNAVAILABLE", 3500)
    return
  end
  local body = encode_json({ id = session.id })
  if not body then set_notice("JSON UNAVAILABLE", 3500); return end
  APP.status_inflight = true
  APP.status_started = clock_ms()
  APP.status_task = "focus"
  APP.request_seq = APP.request_seq + 1
  local request_id = APP.request_seq
  set_notice("FOCUSING " .. trim(session.label, 18), 3000)
  http_api.post(endpoint("/v1/select"), request_options(), body, guard_callback("focus", function(code, response)
    if not APP.active or request_id ~= APP.request_seq then return end
    APP.status_inflight = false
    APP.status_started = 0
    APP.status_task = nil
    if code == 200 and decode_json(response) then
      APP.page = 1
      APP.transcript_scroll = 0
      APP.transcript = { session_id = nil, lines = {}, history = {}, loading = false, error = nil }
      APP.last_poll = 0
      set_notice("FOCUS SENT: " .. trim(session.label, 19), 4500)
    else
      set_notice(hud.transport_error_label("focus", code), 3500)
    end
  end))
end

function APP.stop(reason)
  if not APP.active then return end
  record_lifecycle("stop: " .. tostring(reason or "unknown"))
  APP.active = false
  if APP.timer then
    call(function() APP.timer:stop() end)
    call(function() APP.timer:unregister() end)
    APP.timer = nil
  end
  if key_api and key_api.off then call(key_api.off) end
  if app_api and app_api.on then call(app_api.on, "imu", nil) end
  if APP.root then call(rawget(_G, "lv_obj_clean"), APP.root) end
  if rawget(_G, APP_KEY) == APP then _G[APP_KEY] = nil end
  print("[orca-hud] stopped", tostring(reason or ""))
end

if app_api and app_api.set_home_exit then call(app_api.set_home_exit, false) end

local function on_imu(_, roll, pitch)
  if not APP.active then return end
  if APP.neutral_pitch == nil then
    APP.neutral_pitch = tonumber(pitch) or 0
  end
  APP.raw_roll, APP.raw_pitch = tonumber(roll) or 0, tonumber(pitch) or 0
  local pulse, previous_roll, anchor_roll, latched = hud.vertical_motion_pulse(
    APP.raw_roll,
    APP.vertical_previous_roll,
    APP.vertical_anchor_roll,
    APP.vertical_latched,
    APP.vertical_flick_degrees,
    APP.vertical_sudden_degrees,
    APP.vertical_rearm_degrees
  )
  APP.vertical_previous_roll, APP.vertical_anchor_roll, APP.vertical_latched = previous_roll, anchor_roll, latched
  if pulse ~= 0 then APP.vertical_pulse = pulse end
end

if app_api and app_api.on then call(app_api.on, "imu", on_imu) end

local function handle_home_event(event_type)
  if not APP.active then return end
  if event_type == key_api.SHORT then
    if APP.page == 1 then
      APP.last_poll = 0
      set_notice("REFRESHING CONTEXT", 1800)
    elseif APP.page == 2 then
      focus_selected()
    else
      APP.last_transcript_poll = 0
      set_notice("REFRESHING TRANSCRIPT", 1800)
      fetch_transcript()
    end
  elseif event_type == key_api.LONG_START or event_type == key_api.LONG_REPEAT then
    APP.stop("long HOME")
    if app_api and app_api.exit then call(app_api.exit) end
  end
end

if key_api and key_api.on and key_api.HOME then call(key_api.on, key_api.HOME, handle_home_event) end

local function tick()
  if not APP.active then return end
  if app_api and app_api.exiting then
    local ok, exiting = pcall(app_api.exiting)
    if ok and exiting then APP.stop("system exit"); return end
  end
  local now = clock_ms()
  if APP.neutral_pitch ~= nil then
    local horizontal = APP.neutral_pitch - APP.raw_pitch
    local vertical_pulse = APP.vertical_pulse
    APP.vertical_pulse = 0
    local page, page_latched, page_changed = hud.move_page(
      APP.page, horizontal, APP.page_latched, APP.horizontal_threshold, APP.horizontal_release_threshold
    )
    APP.page, APP.page_latched = page, page_latched
    if page_changed then
      vertical_pulse = 0
      if APP.page == 1 then
        set_notice("OVERVIEW", 1500)
      elseif APP.page == 2 then
        set_notice("SESSIONS", 1500)
      else
        APP.transcript_scroll = 0
        APP.last_transcript_poll = 0
        set_notice("CHAT", 1500)
      end
    end
    if APP.page == 2 or APP.page == 3 then
      vertical_pulse, APP.vertical_action_ready_at = hud.rate_limit_pulse(
        vertical_pulse, now, APP.vertical_action_ready_at, APP.vertical_action_cooldown_ms
      )
    end
    if APP.page == 2 then
      local selected, changed = hud.move_selection_pulse(APP.selected, #APP.sessions, vertical_pulse)
      APP.selected = selected
      if changed then
        set_notice("SELECT " .. trim(APP.sessions[selected].label, 20), 1200)
      end
    elseif APP.page == 3 then
      local max_scroll = math.max(0, #APP.transcript.lines - CHAT_VISIBLE_LINES)
      local scroll, changed = hud.move_scroll_pulse(APP.transcript_scroll, max_scroll, vertical_pulse)
      APP.transcript_scroll = scroll
      if changed then set_notice("CHAT SCROLL", 350) end
    end
  end
  if APP.status_inflight and now - APP.status_started >= APP.transcript_timeout_ms then
    local status_task = APP.status_task
    APP.status_inflight = false
    APP.status_started = 0
    APP.status_task = nil
    APP.request_seq = APP.request_seq + 1
    APP.last_poll = now
    if status_task == "focus" then
      set_notice("FOCUS TIMEOUT", 3500)
    else
      APP.orca.reachable = false
      set_notice("BRIDGE TIMEOUT / RETRYING", 3500)
    end
    mark_dirty()
  end
  if APP.transcript_inflight and now - APP.transcript_started >= APP.transcript_timeout_ms then
    APP.transcript_inflight = false
    APP.transcript_started = 0
    APP.transcript_seq = APP.transcript_seq + 1
    APP.transcript.loading = false
    APP.transcript.error = "BRIDGE TIMEOUT"
    APP.last_transcript_poll = now
    set_notice("TRANSCRIPT TIMEOUT", 3500)
  end
  if APP.notice_until > 0 and now >= APP.notice_until then APP.notice_until = 0; mark_dirty() end
  if now - APP.last_system_poll >= APP.system_poll_ms then
    APP.last_system_poll = now
    if refresh_device_status() then mark_dirty() end
    refresh_clock()
  end
  local next_poll = hud.next_poll(
    APP.page == 3 and "chat" or "context",
    now,
    APP.last_poll,
    APP.last_transcript_poll,
    APP.poll_ms,
    APP.transcript_poll_ms
  )
  if next_poll == "transcript" then
    fetch_transcript()
  elseif next_poll == "status" then
    fetch_status()
  end
  if hud.render_due(now, 0, APP.render_dirty, 0) then
    render()
    APP.render_dirty = false
  end
end

record_lifecycle("started")
if build_canvas() and tmr_api and tmr_api.create then
  APP.timer = tmr_api.create()
  APP.timer:alarm(APP.tick_ms, tmr_api.ALARM_AUTO, function()
    local ok, err = xpcall(tick, function(value) return tostring(value) end)
    if not ok then record_runtime_error(err) end
  end)
  fetch_status()
  refresh_device_status()
  refresh_clock()
  render()
  APP.render_dirty = false
else
  APP.notice = "CANVAS OR TIMER UNAVAILABLE"
end
