-- @noindex
-- Shared ReaImGui widgets.
local theme = require("release_exporter.ui.theme")

local M = {}

local C = theme.COLORS

local drafts = {}

-- Forgets half-typed values, e.g. when the active project changes.
function M.reset()
  drafts = {}
end

-- Text input that reports its value only when editing ends (Enter, Tab or focus loss).
-- A region rename then creates one undo point instead of one per keystroke.
-- `ghost` hides the frame until the field is hovered or edited (table cells); `error` wins over it.
-- Returns the new value, or nil when nothing was committed this frame.
function M.text_field(ImGui, ctx, id, value, opts)
  opts = opts or {}
  local key = opts.key or id
  if opts.width then ImGui.SetNextItemWidth(ctx, opts.width) end
  local colors = 0
  if opts.error then
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C.error_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, C.error_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, C.error_line)
    colors = 3
  elseif opts.ghost then
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C.transparent)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, C.transparent)
    colors = 2
  end
  local changed, new_value = ImGui.InputTextWithHint(ctx, id, opts.hint or "", drafts[key] or value or "")
  if colors > 0 then ImGui.PopStyleColor(ctx, colors) end
  if opts.error then ImGui.SetItemTooltip(ctx, opts.error) end
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

-- Small muted caption, e.g. above a field.
function M.label(ImGui, ctx, text)
  ImGui.TextColored(ctx, C.muted, text)
end

-- The one accented button of a view (Export, Create regions...).
function M.primary_button(ImGui, ctx, label, width, height)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.accent)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.accent_hover)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.accent_active)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.on_accent)
  local clicked = ImGui.Button(ctx, label, width, height)
  ImGui.PopStyleColor(ctx, 4)
  return clicked
end

-- Rounded, bordered block. Without `opts.height` it grows with its content; `opts.padding` = { x, y }.
-- `draw` runs only when visible.
function M.card(ImGui, ctx, id, opts, draw)
  local height, padding = opts.height, opts.padding or { 16, 14 }
  -- ReaImGui 0.10 renamed ChildFlags_Border; the 0.9 API may only know the old name.
  local border = rawget(ImGui, "ChildFlags_Borders") or ImGui.ChildFlags_Border
  local flags = border | ImGui.ChildFlags_AlwaysUseWindowPadding
  if not height then flags = flags | ImGui.ChildFlags_AutoResizeY end
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, padding[1], padding[2])
  local visible = ImGui.BeginChild(ctx, id, 0, height or 0, flags)
  ImGui.PopStyleVar(ctx)
  if visible then draw() end
  ImGui.EndChild(ctx)
end

-- ImGui has no dashed outline: draw the four edges as short segments.
function M.dashed_rect(ImGui, draw_list, x1, y1, x2, y2, color)
  local dash, gap = 6, 4
  local function segments(from, to, line)
    local pos = from
    while pos < to do
      line(pos, math.min(pos + dash, to))
      pos = pos + dash + gap
    end
  end
  segments(x1, x2, function(a, b)
    ImGui.DrawList_AddLine(draw_list, a, y1, b, y1, color)
    ImGui.DrawList_AddLine(draw_list, a, y2, b, y2, color)
  end)
  segments(y1, y2, function(a, b)
    ImGui.DrawList_AddLine(draw_list, x1, a, x1, b, color)
    ImGui.DrawList_AddLine(draw_list, x2, a, x2, b, color)
  end)
end

-- Errors first, then warnings; past `max`, the rest folds into one "+n more" chip.
function M.issue_chips(errors, warnings, max)
  local all = {}
  for _, issue in ipairs(errors) do all[#all + 1] = { text = issue.message, kind = "error" } end
  for _, issue in ipairs(warnings) do all[#all + 1] = { text = issue.message, kind = "warning" } end
  local chips = { visible = {} }
  for i, chip in ipairs(all) do
    if i <= max then
      chips.visible[i] = chip
    else
      chips.overflow = chips.overflow or { lines = {} }
      chips.overflow.lines[#chips.overflow.lines + 1] = chip.text
    end
  end
  if chips.overflow then chips.overflow.text = ("+%d more"):format(#chips.overflow.lines) end
  return chips
end

local CHIP_COLORS = {
  error = { C.error, C.error_bg, C.error_line },
  warning = { C.warning, C.warning_bg, C.warning_line },
  neutral = { C.muted, C.field, C.line },
}
local CHIP_PAD_X, CHIP_PAD_Y, CHIP_GAP = 9, 4, 8

local function chip_size(ImGui, ctx, text)
  local w, h = ImGui.CalcTextSize(ctx, text)
  return w + CHIP_PAD_X * 2, h + CHIP_PAD_Y * 2
end

local function chip(ImGui, ctx, text, kind)
  local fg, bg, line = table.unpack(CHIP_COLORS[kind])
  local w, h = chip_size(ImGui, ctx, text)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.Dummy(ctx, w, h)
  local draw_list = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, bg, h / 2)
  ImGui.DrawList_AddRect(draw_list, x, y, x + w, y + h, line, h / 2)
  ImGui.DrawList_AddText(draw_list, x + CHIP_PAD_X, y + CHIP_PAD_Y, fg, text)
end

-- Draws the chips from issue_chips, wrapping to a new line when the row is full.
function M.chip_row(ImGui, ctx, chips)
  local list = {}
  for i, c in ipairs(chips.visible) do list[i] = c end
  if chips.overflow then list[#list + 1] = { text = chips.overflow.text, kind = "neutral" } end
  local avail = ImGui.GetContentRegionAvail(ctx)
  local used = 0
  for i, c in ipairs(list) do
    local w = chip_size(ImGui, ctx, c.text)
    if i > 1 and used + CHIP_GAP + w <= avail then
      ImGui.SameLine(ctx, 0, CHIP_GAP)
      used = used + CHIP_GAP + w
    else
      used = w
    end
    chip(ImGui, ctx, c.text, c.kind)
  end
  if chips.overflow and ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, table.concat(chips.overflow.lines, "\n"))
  end
end

-- "/Users/me/Music" -> "~/Music", only for the home folder itself.
function M.short_path(path, home)
  if not home or home == "" then return path end
  if path == home or path:sub(1, #home + 1) == home .. "/" then return "~" .. path:sub(#home + 1) end
  return path
end

M.COLOR_ERROR = C.error
M.COLOR_WARNING = C.warning
M.COLOR_OK = C.accent

return M
