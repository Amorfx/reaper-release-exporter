-- Shared ReaImGui widgets.
local M = {}

local drafts = {}

-- Text input that reports its value only when editing ends (Enter, Tab or focus loss).
-- A region rename then creates one undo point instead of one per keystroke.
-- Returns the new value, or nil when nothing was committed this frame.
function M.text_field(ImGui, ctx, id, value, opts)
  opts = opts or {}
  local key = opts.key or id
  if opts.width then ImGui.SetNextItemWidth(ctx, opts.width) end
  if opts.error then ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x7A2E2EFF) end
  local changed, new_value = ImGui.InputTextWithHint(ctx, id, opts.hint or "", drafts[key] or value or "")
  if opts.error then
    ImGui.PopStyleColor(ctx)
    ImGui.SetItemTooltip(ctx, opts.error)
  end
  if changed then drafts[key] = new_value end
  if ImGui.IsItemDeactivated(ctx) then
    local draft = drafts[key]
    drafts[key] = nil
    if draft ~= nil and draft ~= (value or "") then return draft end
  end
end

-- options: array of { value = any, label = string }. Returns the picked value or nil.
function M.combo(ImGui, ctx, id, current, options, width)
  local preview = tostring(current)
  for _, option in ipairs(options) do
    if option.value == current then preview = option.label end
  end
  if width then ImGui.SetNextItemWidth(ctx, width) end
  local picked
  if ImGui.BeginCombo(ctx, id, preview) then
    for _, option in ipairs(options) do
      if ImGui.Selectable(ctx, option.label, option.value == current) then picked = option.value end
    end
    ImGui.EndCombo(ctx)
  end
  return picked
end

M.COLOR_ERROR = 0xE06C6CFF
M.COLOR_WARNING = 0xF2B84BFF

return M
