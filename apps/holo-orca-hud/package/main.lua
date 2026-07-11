local APP_KEY = "HOLO_ORCA_HUD_APP"
local previous = rawget(_G, APP_KEY)
if previous and previous.stop then pcall(function() previous.stop("reload") end) end

local app_api = rawget(_G, "app")
local key_api = rawget(_G, "key")
local tmr_api = rawget(_G, "tmr")
local http_api = rawget(_G, "http")
local JSON = rawget(_G, "sjson") or rawget(_G, "json")
local hud = dofile("/sd/apps/holo-orca-hud/hud_model.lua")
local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local C = { black = 0x000000, cyan = 0x8FE9FF, faint = 0x36515A, white = 0xFFFFFF, amber = 0xFFC857 }

local connection = {}
local loaded, value = pcall(dofile, "/sd/apps/holo-orca-hud/connection.lua")
if loaded and type(value) == "table" then connection = value end

local APP = {
  width = 320,
  height = 240,
  poll_ms = 5000,
  threshold = 12,
  neutral_pitch = nil,
  raw_pitch = 0,
  selected = 1,
  tilt_latched = false,
  sessions = {},
  orca = { running = false, reachable = false, state = "waiting" },
  base_url = tostring(connection.base_url or ""),
  token = tostring(connection.token or ""),
  in_flight = false,
  request_seq = 0,
  last_poll = 0,
  status = "CONNECTING",
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

local function set_text(label, text)
  call(rawget(_G, "lv_label_set_text"), label, text)
end

local function make_label(text, x, y, color)
  local create = rawget(_G, "lv_label_create")
  local label = create and create(APP.root) or nil
  if not label then return nil end
  set_text(label, text)
  call(rawget(_G, "lv_obj_set_pos"), label, x, y)
  call(rawget(_G, "lv_obj_set_style_text_color"), label, color, MAIN)
  call(rawget(_G, "lv_obj_set_style_text_opa"), label, 255, MAIN)
  return label
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

local function build_ui()
  local screen = rawget(_G, "lv_scr_act")
  APP.root = screen and screen() or nil
  if not APP.root then
    APP.status = "LVGL UNAVAILABLE"
    return false
  end
  call(rawget(_G, "lv_obj_clean"), APP.root)
  call(rawget(_G, "lv_obj_set_style_bg_color"), APP.root, C.black, MAIN)
  call(rawget(_G, "lv_obj_set_style_bg_opa"), APP.root, 255, MAIN)
  APP.ui.title = make_label("ORCA HUD", 12, 10, C.cyan)
  APP.ui.runtime = make_label("WAITING", 220, 10, C.faint)
  APP.ui.hint = make_label("TILT L/R   PRESS ACTIVATE", 12, 32, C.faint)
  APP.ui.rows = {}
  for index = 1, 4 do
    APP.ui.rows[index] = make_label("", 12, 56 + (index - 1) * 34, C.white)
  end
  APP.ui.status = make_label(APP.status, 12, 214, C.faint)
  return true
end

local function render()
  if not APP.active then return end
  local connected = APP.orca.running and APP.orca.reachable
  set_text(APP.ui.runtime, connected and "ORCA READY" or "ORCA OFFLINE")
  call(rawget(_G, "lv_obj_set_style_text_color"), APP.ui.runtime, connected and C.cyan or C.amber, MAIN)

  local total = #APP.sessions
  local first = math.max(1, APP.selected - 1)
  if first > math.max(1, total - 3) then first = math.max(1, total - 3) end
  for row = 1, 4 do
    local session = APP.sessions[first + row - 1]
    local label = APP.ui.rows[row]
    if session then
      local selected = first + row - 1 == APP.selected
      local control = session.canActivate and "LINK" or "WAIT"
      local line = string.format("%s %-18s %s", selected and ">" or " ", trim(session.label, 18), control)
      set_text(label, line)
      call(rawget(_G, "lv_obj_set_style_text_color"), label, selected and C.cyan or C.white, MAIN)
    else
      set_text(label, "")
    end
  end
  set_text(APP.ui.status, trim(APP.status, 46))
end

local function apply_status(doc)
  if type(doc) ~= "table" or type(doc.sessions) ~= "table" or type(doc.orca) ~= "table" then
    APP.status = "BAD BRIDGE DATA"
    return false
  end
  APP.sessions = doc.sessions
  APP.orca = doc.orca
  if #APP.sessions == 0 then
    APP.selected = 1
    APP.status = "NO ORCA SESSIONS"
  else
    APP.selected = math.max(1, math.min(APP.selected, #APP.sessions))
    APP.status = tostring(#APP.sessions) .. " SESSIONS"
  end
  return true
end

local function fetch_status()
  if APP.in_flight then return end
  if not valid_connection() then
    APP.status = "CONFIG REQUIRED"
    return
  end
  if not http_api or not http_api.get then
    APP.status = "HTTP UNAVAILABLE"
    return
  end
  APP.in_flight = true
  APP.request_seq = APP.request_seq + 1
  local request_id = APP.request_seq
  http_api.get(endpoint("/v1/status"), headers(), function(code, body)
    if not APP.active or request_id ~= APP.request_seq then return end
    APP.in_flight = false
    APP.last_poll = clock_ms()
    if code ~= 200 or type(body) ~= "string" then
      APP.status = "BRIDGE HTTP " .. tostring(code or 0)
      return
    end
    apply_status(decode_json(body))
  end)
end

local function activate_selected()
  local session = APP.sessions[APP.selected]
  if not session then
    APP.status = "NO SESSION SELECTED"
    return
  end
  if not session.canActivate then
    APP.status = "SESSION HAS NO LINK"
    return
  end
  if APP.in_flight or not valid_connection() or not http_api or not http_api.post then
    APP.status = "BRIDGE UNAVAILABLE"
    return
  end
  local body = encode_json({ id = session.id })
  if not body then
    APP.status = "JSON UNAVAILABLE"
    return
  end
  APP.in_flight = true
  APP.request_seq = APP.request_seq + 1
  local request_id = APP.request_seq
  APP.status = "ACTIVATING " .. trim(session.label, 18)
  http_api.post(endpoint("/v1/select"), headers(), body, function(code, response)
    if not APP.active or request_id ~= APP.request_seq then return end
    APP.in_flight = false
    if code == 200 and decode_json(response) then
      APP.status = "SESSION ACTIVATED"
      APP.last_poll = 0
    else
      APP.status = "ACTIVATE HTTP " .. tostring(code or 0)
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
  call(app_api.on, "imu", function(_, _, pitch)
    if not APP.active then return end
    if APP.neutral_pitch == nil then APP.neutral_pitch = tonumber(pitch) or 0 end
    APP.raw_pitch = tonumber(pitch) or 0
  end)
end

if key_api and key_api.on then
  call(key_api.on, function(code, event_type)
    if not APP.active or code ~= key_api.HOME then return end
    if event_type == key_api.SHORT then activate_selected() end
    if event_type == key_api.LONG_START then
      APP.stop("long HOME")
      if app_api and app_api.exit then call(app_api.exit) end
    end
  end)
end

if build_ui() and tmr_api and tmr_api.create then
  APP.timer = tmr_api.create()
  APP.timer:alarm(50, tmr_api.ALARM_AUTO, function()
    if not APP.active then return end
    if APP.neutral_pitch ~= nil then
      local horizontal = APP.raw_pitch - APP.neutral_pitch
      local selected, latched, changed = hud.move_selection(APP.selected, #APP.sessions, horizontal, APP.tilt_latched, APP.threshold)
      APP.selected, APP.tilt_latched = selected, latched
      if changed then APP.status = "SELECT " .. trim(APP.sessions[selected].label, 18) end
    end
    if clock_ms() - APP.last_poll >= APP.poll_ms then fetch_status() end
    render()
  end)
  fetch_status()
  render()
else
  APP.status = "UI OR TIMER UNAVAILABLE"
end
