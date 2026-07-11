local M = {}

local function clamp(value, lower, upper)
  if value < lower then return lower end
  if value > upper then return upper end
  return value
end

function M.move_selection(index, count, physical_horizontal, latched, threshold)
  local total = math.max(0, math.floor(tonumber(count) or 0))
  if total == 0 then return 1, false, false end
  local selected = clamp(math.floor(tonumber(index) or 1), 1, total)
  local axis = tonumber(physical_horizontal) or 0
  local limit = math.abs(tonumber(threshold) or 12)
  if math.abs(axis) <= limit then return selected, false, false end
  if latched then return selected, true, false end
  local moved = clamp(selected + (axis > 0 and 1 or -1), 1, total)
  return moved, true, moved ~= selected
end

function M.move_page(index, count, physical_vertical, latched, threshold)
  return M.move_selection(index, count, physical_vertical, latched, threshold)
end

return M
