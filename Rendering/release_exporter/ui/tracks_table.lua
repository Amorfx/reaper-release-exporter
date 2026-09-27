-- @noindex
-- Songs section: title line, table (one row per region) and the empty state for projects without regions.
local model = require("release_exporter.model")
local theme = require("release_exporter.ui.theme")
local widgets = require("release_exporter.ui.widgets")

local M = {}

local C = theme.COLORS
local ROW_HEIGHT = 40

local function duration(seconds)
  local total = math.floor(seconds + 0.5)
  return string.format("%d:%02d", total // 60, total % 60)
end

-- "3 of 4 included · 14:32": the length only counts the songs that will be exported.
function M.summary(rows)
  local included, seconds = 0, 0
  for _, row in ipairs(rows) do
    if row.include then
      included = included + 1
      seconds = seconds + row.duration
    end
  end
  return ("%d of %d included · %s"):format(included, #rows, duration(seconds))
end

local function cell(ImGui, ctx, app, row, key, hint)
  ImGui.TableNextColumn(ctx)
  local issue = row.include and model.issue_for(app.validation.errors, row.guid, key) or nil
  local value = widgets.text_field(ImGui, ctx, "##" .. key, row[key], {
    key = row.guid .. ":" .. key, width = -1, hint = hint, error = issue, ghost = true,
  })
  if value then app:set_track_field(row.guid, key, value) end
end

local function right_aligned(ImGui, ctx, text, color)
  local width = ImGui.CalcTextSize(ctx, text)
  ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + ImGui.GetContentRegionAvail(ctx) - width)
  ImGui.TextColored(ctx, color, text)
end

local function draw_empty(ImGui, ctx, app)
  widgets.card(ImGui, ctx, "##empty", {}, function()
    ImGui.TextWrapped(ctx, "This project has no regions yet. Create one region per song, or select the song items "
      .. "(rendered mixes or subprojects) and click the button below.")
    ImGui.Spacing(ctx)
    if widgets.primary_button(ImGui, ctx, "Create one region per selected item") then
      app.flash = app:create_regions_from_items() == 0 and "Select at least one media item first." or nil
    end
    if app.flash then ImGui.TextColored(ctx, widgets.COLOR_WARNING, app.flash) end
  end)
end

local function draw_include(ImGui, ctx, app, row)
  ImGui.TableNextColumn(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  -- A ticked box is filled with the accent, the check mark drawn on top of it.
  if row.include then
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C.accent)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, C.accent_hover)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, C.accent_active)
  end
  local changed, include = ImGui.Checkbox(ctx, "##include", row.include)
  if row.include then ImGui.PopStyleColor(ctx, 3) end
  if changed then app:set_track_field(row.guid, "include", include) end
end

local function draw_row(ImGui, ctx, app, row)
  ImGui.PushID(ctx, row.guid)
  ImGui.TableNextRow(ctx, 0, ROW_HEIGHT)
  -- An excluded song stays editable but reads as inactive.
  if not row.include then ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.dim) end
  draw_include(ImGui, ctx, app, row)
  ImGui.TableNextColumn(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextColored(ctx, row.include and C.muted or C.dim, row.number and tostring(row.number) or "-")
  cell(ImGui, ctx, app, row, "title", "Title")
  cell(ImGui, ctx, app, row, "artist", app.ep.artist)
  cell(ImGui, ctx, app, row, "isrc", "CCXXXYYNNNNN")
  cell(ImGui, ctx, app, row, "composer", "")
  ImGui.TableNextColumn(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  right_aligned(ImGui, ctx, duration(row.duration), row.include and C.muted or C.dim)
  if not row.include then ImGui.PopStyleColor(ctx) end
  ImGui.PopID(ctx)
end

local function draw_table(ImGui, ctx, app)
  local flags = ImGui.TableFlags_BordersInnerH | ImGui.TableFlags_ScrollY | ImGui.TableFlags_PadOuterX
  local _, height = ImGui.GetContentRegionAvail(ctx)
  if not ImGui.BeginTable(ctx, "tracks", 7, flags, 0, height) then return end
  ImGui.TableSetupScrollFreeze(ctx, 0, 1)
  ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthFixed, 24)
  ImGui.TableSetupColumn(ctx, "#", ImGui.TableColumnFlags_WidthFixed, 24)
  ImGui.TableSetupColumn(ctx, "Title", ImGui.TableColumnFlags_WidthStretch, 3)
  ImGui.TableSetupColumn(ctx, "Artist", ImGui.TableColumnFlags_WidthStretch, 2)
  ImGui.TableSetupColumn(ctx, "ISRC", ImGui.TableColumnFlags_WidthStretch, 1.6)
  ImGui.TableSetupColumn(ctx, "Composer", ImGui.TableColumnFlags_WidthStretch, 2)
  ImGui.TableSetupColumn(ctx, "Length", ImGui.TableColumnFlags_WidthFixed, 52)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.muted)
  ImGui.TableHeadersRow(ctx)
  ImGui.PopStyleColor(ctx)
  for _, row in ipairs(app.rows) do draw_row(ImGui, ctx, app, row) end
  ImGui.EndTable(ctx)
end

-- `reserve`: height kept free below the table for the export bar.
function M.draw(ImGui, ctx, app, reserve)
  ImGui.Text(ctx, "Songs")
  if #app.rows == 0 then return draw_empty(ImGui, ctx, app) end
  ImGui.SameLine(ctx)
  right_aligned(ImGui, ctx, M.summary(app.rows), C.muted)
  local _, avail = ImGui.GetContentRegionAvail(ctx)
  local height = math.max(120, avail - reserve)
  widgets.card(ImGui, ctx, "##songs", { height = height, padding = { 6, 4 } }, function() draw_table(ImGui, ctx, app) end)
end

return M
