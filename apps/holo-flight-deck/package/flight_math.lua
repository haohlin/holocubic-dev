local M = {}

local function clamp(value, lower, upper)
  if value < lower then return lower end
  if value > upper then return upper end
  return value
end

function M.normalize(raw, neutral, dead_zone, limit)
  local value = (tonumber(raw) or 0) - (tonumber(neutral) or 0)
  local threshold = math.abs(tonumber(dead_zone) or 0)
  local bound = math.abs(tonumber(limit) or 45)
  if math.abs(value) <= threshold then return 0 end
  return clamp(value, -bound, bound)
end

function M.smooth(current, target, alpha)
  local from = tonumber(current) or 0
  local to = tonumber(target) or 0
  local amount = clamp(tonumber(alpha) or 0, 0, 1)
  return from + (to - from) * amount
end

-- The current firmware reports the physical device axes in the opposite
-- screen order: pitch is the left/right (roll) motion and roll is the
-- fore/aft (pitch) motion.
function M.device_attitude(raw_roll, raw_pitch, neutral_roll, neutral_pitch, dead_zone, limit)
  local visual_roll = M.normalize(raw_pitch, neutral_pitch, dead_zone, limit)
  local visual_pitch = M.normalize(raw_roll, neutral_roll, dead_zone, limit)
  return visual_roll, visual_pitch
end

function M.horizon(width, height, pitch, roll)
  local screen_w = tonumber(width) or 320
  local screen_h = tonumber(height) or 240
  local center_x = screen_w / 2
  local center_y = screen_h / 2 + clamp(tonumber(pitch) or 0, -45, 45) / 45 * 75
  local radians = clamp(tonumber(roll) or 0, -35, 35) * math.pi / 180
  local half_length = 135
  local dx = math.cos(radians) * half_length
  local dy = math.sin(radians) * half_length
  return math.floor(center_x - dx + 0.5), math.floor(center_y - dy + 0.5),
         math.floor(center_x + dx + 0.5), math.floor(center_y + dy + 0.5)
end

return M
