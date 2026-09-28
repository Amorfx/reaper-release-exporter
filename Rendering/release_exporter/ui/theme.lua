-- @noindex
-- Near-black theme with a green accent. Pushed around the main window, so popups inherit it.
local M = {}

M.COLORS = {
  bg = 0x0B0B0DFF,
  card = 0x131316FF,
  line = 0x232329FF,
  field = 0x18181CFF,
  field_hover = 0x1F1F24FF,
  field_active = 0x24242AFF,
  text = 0xEDEDEFFF,
  muted = 0x8A8A93FF,
  dim = 0x55555DFF,
  accent = 0x2FB67CFF,
  accent_hover = 0x3CC98BFF,
  accent_active = 0x28A06DFF,
  on_accent = 0x04140CFF,
  error = 0xF08A8AFF,
  error_bg = 0x1E1010FF,
  error_line = 0x6B2A2AFF,
  warning = 0xE5B567FF,
  warning_bg = 0x1C170DFF,
  warning_line = 0x4A3B1EFF,
  transparent = 0x00000000,
}

local C = M.COLORS

local function colors(ImGui)
  return {
    { ImGui.Col_WindowBg, C.bg },
    { ImGui.Col_ChildBg, C.card },
    { ImGui.Col_PopupBg, C.card },
    { ImGui.Col_ModalWindowDimBg, 0x000000A0 },
    { ImGui.Col_TitleBg, C.bg },
    { ImGui.Col_TitleBgActive, C.bg },
    { ImGui.Col_TitleBgCollapsed, C.bg },
    { ImGui.Col_Border, C.line },
    { ImGui.Col_Separator, C.line },
    { ImGui.Col_Text, C.text },
    { ImGui.Col_TextDisabled, C.dim },
    { ImGui.Col_FrameBg, C.field },
    { ImGui.Col_FrameBgHovered, C.field_hover },
    { ImGui.Col_FrameBgActive, C.field_active },
    { ImGui.Col_Button, C.field },
    { ImGui.Col_ButtonHovered, C.field_hover },
    { ImGui.Col_ButtonActive, C.field_active },
    { ImGui.Col_Header, C.field_hover },
    { ImGui.Col_HeaderHovered, C.field_hover },
    { ImGui.Col_HeaderActive, C.field_active },
    { ImGui.Col_CheckMark, C.on_accent },
    { ImGui.Col_TextSelectedBg, 0x2FB67C55 },
    { ImGui.Col_TableHeaderBg, C.card },
    { ImGui.Col_TableBorderLight, C.line },
    { ImGui.Col_TableBorderStrong, C.line },
    { ImGui.Col_TableRowBg, C.transparent },
    { ImGui.Col_TableRowBgAlt, C.transparent },
    { ImGui.Col_ScrollbarBg, C.transparent },
    { ImGui.Col_ScrollbarGrab, C.line },
    { ImGui.Col_ScrollbarGrabHovered, C.dim },
    { ImGui.Col_ScrollbarGrabActive, C.dim },
    { ImGui.Col_ResizeGrip, C.transparent },
    { ImGui.Col_ResizeGripHovered, C.line },
    { ImGui.Col_ResizeGripActive, C.dim },
    { ImGui.Col_DragDropTarget, C.accent },
  }
end

local function vars(ImGui)
  return {
    { ImGui.StyleVar_WindowPadding, 18, 16 },
    { ImGui.StyleVar_FramePadding, 10, 7 },
    { ImGui.StyleVar_ItemSpacing, 12, 10 },
    { ImGui.StyleVar_ItemInnerSpacing, 8, 6 },
    { ImGui.StyleVar_CellPadding, 8, 6 },
    { ImGui.StyleVar_WindowRounding, 10 },
    { ImGui.StyleVar_ChildRounding, 8 },
    { ImGui.StyleVar_FrameRounding, 6 },
    { ImGui.StyleVar_PopupRounding, 8 },
    { ImGui.StyleVar_GrabRounding, 6 },
    { ImGui.StyleVar_ScrollbarRounding, 6 },
    { ImGui.StyleVar_FrameBorderSize, 1 },
    { ImGui.StyleVar_WindowBorderSize, 1 },
    { ImGui.StyleVar_ChildBorderSize, 1 },
    { ImGui.StyleVar_PopupBorderSize, 1 },
  }
end

local pushed = { colors = 0, vars = 0 }

function M.push(ImGui, ctx)
  local cs, vs = colors(ImGui), vars(ImGui)
  for _, c in ipairs(cs) do ImGui.PushStyleColor(ctx, c[1], c[2]) end
  for _, v in ipairs(vs) do ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) end
  pushed.colors, pushed.vars = #cs, #vs
end

function M.pop(ImGui, ctx)
  ImGui.PopStyleVar(ctx, pushed.vars)
  ImGui.PopStyleColor(ctx, pushed.colors)
  pushed.colors, pushed.vars = 0, 0
end

return M
