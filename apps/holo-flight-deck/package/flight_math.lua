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
