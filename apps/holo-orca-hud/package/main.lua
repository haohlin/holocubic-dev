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
local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local C = { black = 0x000000, cyan = 0x8FE9FF, faint = 0x36515A, white = 0xFFFFFF, amber = 0xFFC857 }

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
  weather_poll_ms = 10 * 60000,
  threshold = 12,
  neutral_roll = nil,
  neutral_pitch = nil,
  raw_roll = 0,
  raw_pitch = 0,
  page = 1,
  page_latched = false,
  selected = 1,
  select_latched = false,
  sessions = {},
  orca = { running = false, reachable = false, state = "waiting" },
  location = tostring(settings.weather_city or settings.city or settings.weather_address or "Location unset"),
  weather = { valid = false, temp = "--", text = "WEATHER WAIT" },
  network = "NET WAIT",
  firmware = "FW --",
  base_url = tostring(connection.base_url or ""),
  token = tostring(connection.token or ""),
  status_inflight = false,
  weather_inflight = false,
  request_seq = 0,
  last_poll = 0,
  last_weather_poll = 0,
  notice = "STARTING",
  notice_until = 0,
  active = true,
  timer = nil,
  root = nil,
  ui = {},
}
_G[APP_KEY] = APP

local function call(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function clock_ms()
  if tmr_api and tmr_api.now then return math.floor((tonumber(tmr_api.now()) or 0) / 1000) end
  return 0
end

local function trim(value, limit)
  local text = tostring(value or ""):gsub("[%c]+", " "):gsub("%s+", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if #text > limit then return text:sub(1, limit - 1) .. "." end
  return text
end

local function url_encode(value)
  return tostring(value or ""):gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)
end

local function set_notice(text, duration)
  APP.notice = trim(text, 48)
  APP.notice_until = clock_ms() + (duration or 2200)
end

local function set_text(label, text)
  call(rawget(_G, "lv_label_set_text"), label, text)
end

local function set_color(label, color)
  call(rawget(_G, "lv_obj_set_style_text_color"), label, color, MAIN)
end

local function make_label(text, x, y, color)
  local create = rawget(_G, "lv_label_create")
  local label = create and create(APP.root) or nil
  if not label then return nil end
  set_text(label, text)
  call(rawget(_G, "lv_obj_set_pos"), label, x, y)
  set_color(label, color)
  call(rawget(_G, "lv_obj_set_style_text_opa"), label, 255, MAIN)
  return label
end

local function make_line(color)
  local create = rawget(_G, "lv_line_create")
  local line = create and create(APP.root) or nil
  if not line then return nil end
  call(rawget(_G, "lv_line_set_points"), line, { 0, 0, 0, 0 }, 2)
  call(rawget(_G, "lv_obj_set_style_line_color"), line, color, MAIN)
  call(rawget(_G, "lv_obj_set_style_line_width"), line, 1, MAIN)
  call(rawget(_G, "lv_obj_set_style_line_opa"), line, 255, MAIN)
  return line
end

local function set_line(line, x1, y1, x2, y2)
  if line then call(rawget(_G, "lv_line_set_points"), line, { x1, y1, x2, y2 }, 2) end
end

local function headers()
  return "Authorization: Bearer " .. APP.token .. "\r\n"
    .. "Accept: application/json\r\n"
    .. "Content-Type: application/json\r\n"
    .. "Cache-Control: no-cache\r\n"
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

local function refresh_device_status()
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
end

local function working_count()
  local total = 0
  for _, session in ipairs(APP.sessions) do
    if session.status == "working" or session.agentState == "working" then total = total + 1 end
  end
  return total
end

local function focused_label()
  for _, session in ipairs(APP.sessions) do
    if session.focused then return trim(session.label, 26) end
  end
  return "NONE"
end

local function build_ui()
  local screen = rawget(_G, "lv_scr_act")
  APP.root = screen and screen() or nil
  if not APP.root then
    APP.notice = "LVGL UNAVAILABLE"
    return false
  end
  call(rawget(_G, "lv_obj_clean"), APP.root)
  call(rawget(_G, "lv_obj_set_style_bg_color"), APP.root, C.black, MAIN)
  call(rawget(_G, "lv_obj_set_style_bg_opa"), APP.root, 255, MAIN)
  APP.ui.title = make_label("CONTEXT", 12, 10, C.cyan)
  APP.ui.mode = make_label("LIVE", 250, 10, C.faint)
  APP.ui.primary = make_label("", 12, 45, C.white)
  APP.ui.secondary = make_label("", 12, 68, C.faint)
  APP.ui.metric1 = make_label("", 12, 102, C.white)
  APP.ui.metric2 = make_label("", 12, 126, C.white)
  APP.ui.focus = make_label("", 12, 158, C.cyan)
  APP.ui.rows = {}
  for index = 1, 4 do APP.ui.rows[index] = make_label("", 12, 72 + (index - 1) * 29, C.white) end
  APP.ui.rail1 = make_line(C.faint)
  APP.ui.rail2 = make_line(C.faint)
  APP.ui.status = make_label("", 12, 216, C.faint)
  return true
end

local function render_context()
  set_text(APP.ui.title, "CONTEXT")
  set_text(APP.ui.mode, APP.orca.running and "LIVE" or "OFFLINE")
  set_color(APP.ui.mode, APP.orca.running and C.cyan or C.amber)
  set_text(APP.ui.primary, clock_text() .. "  " .. trim(APP.location, 22))
  local weather_line = APP.weather.valid
    and (trim(APP.weather.text, 16) .. "  " .. tostring(APP.weather.temp) .. "C")
    or "WEATHER WAIT"
  set_text(APP.ui.secondary, weather_line)
  set_text(APP.ui.metric1, APP.network .. "  " .. APP.firmware)
  set_text(APP.ui.metric2, "ORCA " .. (APP.orca.reachable and "READY" or "OFFLINE")
    .. "  " .. tostring(working_count()) .. " WORKING")
  set_text(APP.ui.focus, "FOCUS  " .. focused_label())
  for _, label in ipairs(APP.ui.rows) do set_text(label, "") end
  set_line(APP.ui.rail1, 12, 91, 308, 91)
  set_line(APP.ui.rail2, 12, 184, 308, 184)
end

local function render_sessions()
  set_text(APP.ui.title, "ORCA NAV")
  set_text(APP.ui.mode, APP.orca.reachable and "READY" or "OFFLINE")
  set_color(APP.ui.mode, APP.orca.reachable and C.cyan or C.amber)
  set_text(APP.ui.primary, tostring(working_count()) .. " WORKING / " .. tostring(#APP.sessions) .. " SESSIONS")
  set_text(APP.ui.secondary, "TILT L/R SELECT")
  set_text(APP.ui.metric1, "")
  set_text(APP.ui.metric2, "")
  set_text(APP.ui.focus, "")
  local first = math.max(1, APP.selected - 1)
  if first > math.max(1, #APP.sessions - 3) then first = math.max(1, #APP.sessions - 3) end
  for row = 1, 4 do
    local session = APP.sessions[first + row - 1]
    local label = APP.ui.rows[row]
    if session then
      local selected = first + row - 1 == APP.selected
      local state = session.focused and "FOCUS" or (session.canActivate and trim(session.status, 6):upper() or "WAIT")
      set_text(label, string.format("%s %-18s %s", selected and ">" or " ", trim(session.label, 18), state))
      set_color(label, selected and C.cyan or C.white)
    else
      set_text(label, "")
    end
  end
  set_line(APP.ui.rail1, 12, 62, 308, 62)
  set_line(APP.ui.rail2, 12, 190, 308, 190)
end

local function render()
  if not APP.active then return end
  refresh_device_status()
  if APP.page == 1 then render_context() else render_sessions() end
  local now = clock_ms()
  local hint
  if now < APP.notice_until then
    hint = APP.notice
  elseif APP.page == 1 then
    hint = "TILT FWD: ORCA  PRESS: REFRESH"
  else
    hint = "PRESS: FOCUS ON MAC  TILT BACK: CONTEXT"
  end
  set_text(APP.ui.status, trim(hint, 46))
end

local function apply_status(doc)
  if type(doc) ~= "table" or type(doc.sessions) ~= "table" or type(doc.orca) ~= "table" then
    set_notice("BAD BRIDGE DATA", 4000)
    return false
  end
  APP.sessions = doc.sessions
  APP.orca = doc.orca
  APP.selected = math.max(1, math.min(APP.selected, math.max(1, #APP.sessions)))
  return true
end

local function fetch_status()
  if APP.status_inflight then return end
  if not valid_connection() then
    set_notice("CONFIG REQUIRED", 5000)
    return
  end
  if not http_api or not http_api.get then
    set_notice("HTTP UNAVAILABLE", 5000)
    return
  end
  APP.status_inflight = true
  APP.request_seq = APP.request_seq + 1
  local request_id = APP.request_seq
  http_api.get(endpoint("/v1/status"), headers(), function(code, body)
    if not APP.active or request_id ~= APP.request_seq then return end
    APP.status_inflight = false
    APP.last_poll = clock_ms()
    if code ~= 200 or type(body) ~= "string" then
      set_notice("ORCA HTTP " .. tostring(code or 0), 4000)
      return
    end
    apply_status(decode_json(body))
  end)
end

local function request_weather()
  if APP.weather_inflight or APP.location == "" or APP.location == "Location unset" then return end
  if not http_api or not http_api.cubicserver or not http_api.cubicserver.get then
    set_notice("WEATHER UNAVAILABLE", 4000)
    return
  end
  APP.weather_inflight = true
  local url = "/v1/weather/now?location=" .. url_encode(APP.location) .. "&unit=m"
  http_api.cubicserver.get(url, "Accept: application/json\r\n", function(code, body)
    if not APP.active then return end
    APP.weather_inflight = false
    APP.last_weather_poll = clock_ms()
    local doc = decode_json(body)
    local now = doc and doc.now
    if code ~= 200 or type(now) ~= "table" or tostring(doc.code or "") ~= "200" then
      APP.weather.valid = false
      return
    end
    APP.weather.valid = true
    APP.weather.temp = tostring(now.temp or "--")
    APP.weather.text = trim(now.text or "--", 20)
  end)
end

local function focus_selected()
  local session = APP.sessions[APP.selected]
  if not session then
    set_notice("NO SESSION SELECTED", 3000)
    return
  end
  if not session.canActivate then
    set_notice("NO CONNECTED TERMINAL", 3500)
    return
  end
  if APP.status_inflight or not valid_connection() or not http_api or not http_api.post then
    set_notice("ORCA BRIDGE UNAVAILABLE", 3500)
    return
  end
  local body = encode_json({ id = session.id })
  if not body then
    set_notice("JSON UNAVAILABLE", 3500)
    return
  end
  APP.status_inflight = true
  APP.request_seq = APP.request_seq + 1
  local request_id = APP.request_seq
  set_notice("FOCUSING " .. trim(session.label, 18), 3000)
  http_api.post(endpoint("/v1/select"), headers(), body, function(code, response)
    if not APP.active or request_id ~= APP.request_seq then return end
    APP.status_inflight = false
    if code == 200 and decode_json(response) then
      APP.page = 1
      APP.last_poll = 0
      set_notice("FOCUS SENT: " .. trim(session.label, 19), 4500)
    else
      set_notice("FOCUS HTTP " .. tostring(code or 0), 3500)
    end
  end)
end

function APP.stop(reason)
  if not APP.active then return end
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

if app_api and app_api.on then
  call(app_api.on, "imu", function(_, roll, pitch)
    if not APP.active then return end
    if APP.neutral_roll == nil then
      APP.neutral_roll, APP.neutral_pitch = tonumber(roll) or 0, tonumber(pitch) or 0
    end
    APP.raw_roll, APP.raw_pitch = tonumber(roll) or 0, tonumber(pitch) or 0
  end)
end

if key_api and key_api.on then
  call(key_api.on, function(code, event_type)
    if not APP.active or code ~= key_api.HOME then return end
    if event_type == key_api.SHORT then
      if APP.page == 1 then
        APP.last_poll, APP.last_weather_poll = 0, 0
        set_notice("REFRESHING CONTEXT", 1800)
      else
        focus_selected()
      end
    elseif event_type == key_api.LONG_START then
      APP.stop("long HOME")
      if app_api and app_api.exit then call(app_api.exit) end
    end
  end)
end

if build_ui() and tmr_api and tmr_api.create then
  APP.timer = tmr_api.create()
  APP.timer:alarm(50, tmr_api.ALARM_AUTO, function()
    if not APP.active then return end
    if APP.neutral_roll ~= nil then
      local vertical = APP.raw_roll - APP.neutral_roll
      local page, page_latched, page_changed = hud.move_page(APP.page, 2, vertical, APP.page_latched, APP.threshold)
      APP.page, APP.page_latched = page, page_latched
      if page_changed then set_notice(APP.page == 1 and "CONTEXT MODE" or "ORCA NAV MODE", 1500) end
      if APP.page == 2 then
        local horizontal = APP.raw_pitch - APP.neutral_pitch
        local selected, select_latched, changed = hud.move_selection(APP.selected, #APP.sessions, horizontal, APP.select_latched, APP.threshold)
        APP.selected, APP.select_latched = selected, select_latched
        if changed then set_notice("SELECT " .. trim(APP.sessions[selected].label, 20), 1200) end
      else
        APP.select_latched = false
      end
    end
    local now = clock_ms()
    if now - APP.last_poll >= APP.poll_ms then fetch_status() end
    if now - APP.last_weather_poll >= APP.weather_poll_ms then request_weather() end
    render()
  end)
  fetch_status()
  request_weather()
  render()
else
  APP.notice = "UI OR TIMER UNAVAILABLE"
end
