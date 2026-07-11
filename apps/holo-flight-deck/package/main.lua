local APP_KEY = "HOLO_FLIGHT_DECK_APP"
local previous = rawget(_G, APP_KEY)
if previous and previous.stop then pcall(function() previous.stop("reload") end) end

local app_api = rawget(_G, "app")
local key_api = rawget(_G, "key")
local tmr_api = rawget(_G, "tmr")
local flight = dofile("/sd/apps/holo-flight-deck/flight_math.lua")
local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local C = { black = 0x000000, cyan = 0x8FE9FF, faint = 0x36515A, white = 0xFFFFFF }

local APP = {
  width = 320,
  height = 240,
  dead_zone = 1.5,
  limit = 45,
  alpha = 0.28,
  neutral_roll = nil,
  neutral_pitch = nil,
  raw_roll = 0,
  raw_pitch = 0,
  roll = 0,
  pitch = 0,
  scan = false,
  sweep = 0,
  last_event = "IMU: waiting",
  imu_seen_at = 0,
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

local function make_line(color, width)
  local create = rawget(_G, "lv_line_create")
  local line = create and create(APP.root) or nil
  if not line then return nil end
  call(rawget(_G, "lv_line_set_points"), line, { 0, 0, 0, 0 }, 2)
  call(rawget(_G, "lv_obj_set_style_line_color"), line, color, MAIN)
  call(rawget(_G, "lv_obj_set_style_line_width"), line, width, MAIN)
  call(rawget(_G, "lv_obj_set_style_line_opa"), line, 255, MAIN)
  return line
end

local function set_line(line, x1, y1, x2, y2)
  if line then call(rawget(_G, "lv_line_set_points"), line, { x1, y1, x2, y2 }, 2) end
end

local function build_ui()
  local screen = rawget(_G, "lv_scr_act")
  APP.root = screen and screen() or nil
  if not APP.root then
    APP.last_event = "LVGL: no root screen"
    return false
  end
  call(rawget(_G, "lv_obj_clean"), APP.root)
  call(rawget(_G, "lv_obj_set_style_bg_color"), APP.root, C.black, MAIN)
  call(rawget(_G, "lv_obj_set_style_bg_opa"), APP.root, 255, MAIN)

  APP.ui.title = make_label("FLIGHT DECK", 12, 10, C.cyan)
  APP.ui.mode = make_label("SCAN OFF", 238, 10, C.faint)
  APP.ui.attitude = make_label("R +00.0  P +00.0", 96, 30, C.white)
  APP.ui.telemetry = make_label(APP.last_event, 12, 218, C.faint)
  APP.ui.horizon = make_line(C.cyan, 2)
  APP.ui.reticle_h = make_line(C.white, 1)
  APP.ui.reticle_v = make_line(C.white, 1)
  APP.ui.scan = make_line(C.faint, 1)
  set_line(APP.ui.reticle_h, 148, 120, 172, 120)
  set_line(APP.ui.reticle_v, 160, 108, 160, 132)
  return APP.ui.horizon ~= nil
end

local function render()
  if not APP.active then return end
  local target_roll, target_pitch = 0, 0
  if APP.neutral_roll ~= nil then
    target_roll, target_pitch = flight.device_attitude(
      APP.raw_roll,
      APP.raw_pitch,
      APP.neutral_roll,
      APP.neutral_pitch,
      APP.dead_zone,
      APP.limit
    )
  end
  APP.roll = flight.smooth(APP.roll, target_roll, APP.alpha)
  APP.pitch = flight.smooth(APP.pitch, target_pitch, APP.alpha)

  local x1, y1, x2, y2 = flight.horizon(APP.width, APP.height, APP.pitch, APP.roll)
  set_line(APP.ui.horizon, x1, y1, x2, y2)
  set_text(APP.ui.attitude, string.format("R %+.1f  P %+.1f", APP.roll, APP.pitch))

  if APP.scan then
    APP.sweep = (APP.sweep + 4) % 101
    set_line(APP.ui.scan, 204, 76, 204, 164)
    call(rawget(_G, "lv_obj_set_x"), APP.ui.scan, math.floor(APP.sweep - 50))
    set_text(APP.ui.mode, "SCAN ON")
    call(rawget(_G, "lv_obj_set_style_text_color"), APP.ui.mode, C.cyan, MAIN)
  else
    set_line(APP.ui.scan, 0, 0, 0, 0)
    set_text(APP.ui.mode, "SCAN OFF")
    call(rawget(_G, "lv_obj_set_style_text_color"), APP.ui.mode, C.faint, MAIN)
  end

  local age = APP.imu_seen_at == 0 and "no sample" or tostring(math.max(0, clock_ms() - APP.imu_seen_at)) .. "ms"
  set_text(APP.ui.telemetry, APP.last_event .. " | IMU " .. age)
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
  print("[flight-deck] stopped", tostring(reason or ""))
end

if app_api and app_api.set_home_exit then call(app_api.set_home_exit, false) end

if app_api and app_api.on then
  call(app_api.on, "imu", function(_, roll, pitch)
    if not APP.active then return end
    if APP.neutral_roll == nil then
      APP.neutral_roll, APP.neutral_pitch = tonumber(roll) or 0, tonumber(pitch) or 0
      APP.last_event = "IMU: neutral locked"
    end
    APP.raw_roll, APP.raw_pitch = tonumber(roll) or 0, tonumber(pitch) or 0
    APP.imu_seen_at = clock_ms()
  end)
else
  APP.last_event = "IMU: API unavailable"
end

if key_api and key_api.on then
  call(key_api.on, function(code, event_type)
    if not APP.active then return end
    APP.last_event = "KEY " .. tostring(code) .. " / " .. tostring(event_type)
    if code == key_api.HOME and event_type == key_api.SHORT then APP.scan = not APP.scan end
    if code == key_api.HOME and event_type == key_api.LONG_START then
      APP.stop("long HOME")
      if app_api and app_api.exit then call(app_api.exit) end
    end
  end)
else
  APP.last_event = "KEY: API unavailable"
end

if build_ui() and tmr_api and tmr_api.create then
  APP.timer = tmr_api.create()
  APP.timer:alarm(25, tmr_api.ALARM_AUTO, function()
    local ok, err = pcall(render)
    if not ok then APP.last_event = "render error: " .. tostring(err) end
  end)
  render()
else
  print("[flight-deck] UI or timer unavailable")
end
