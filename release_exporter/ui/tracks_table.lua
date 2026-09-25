-- Songs table (one row per region) and the empty state for projects without regions.
local model = require("release_exporter.model")
local widgets = require("release_exporter.ui.widgets")

local M = {}

local function duration(seconds)
  local total = math.floor(seconds + 0.5)
  return string.format("%d:%02d", total // 60, total % 60)
end

local function cell(ImGui, ctx, app, row, key, hint)
  ImGui.TableNextColumn(ctx)
  local issue = row.include and model.issue_for(app.validation.errors, row.guid, key) or nil
  local value = widgets.text_field(ImGui, ctx, "##" .. key, row[key], {
    key = row.guid .. ":" .. key, width = -1, hint = hint, error = issue,
  })
  if value then app:set_track_field(row.guid, key, value) end
end

local function draw_empty(ImGui, ctx, app)
  ImGui.Dummy(ctx, 0, 16)
  ImGui.TextWrapped(ctx, "This project has no regions yet. Create one region per song, or select the song items "
    .. "(rendered mixes or subprojects) and click the button below.")
  if ImGui.Button(ctx, "Create one region per selected item") then
    app.flash = app:create_regions_from_items() == 0 and "Select at least one media item first." or nil
  end
  if app.flash then ImGui.TextColored(ctx, widgets.COLOR_WARNING, app.flash) end
end

function M.draw(ImGui, ctx, app, height)
  if #app.rows == 0 then return draw_empty(ImGui, ctx, app) end
  local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_ScrollY
  if not ImGui.BeginTable(ctx, "tracks", 7, flags, 0, height) then return end
  ImGui.TableSetupScrollFreeze(ctx, 0, 1)
  ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthFixed, 24)
  ImGui.TableSetupColumn(ctx, "#", ImGui.TableColumnFlags_WidthFixed, 28)
  ImGui.TableSetupColumn(ctx, "Title", ImGui.TableColumnFlags_WidthStretch, 3)
  ImGui.TableSetupColumn(ctx, "Artist", ImGui.TableColumnFlags_WidthStretch, 2)
  ImGui.TableSetupColumn(ctx, "ISRC", ImGui.TableColumnFlags_WidthStretch, 1.6)
  ImGui.TableSetupColumn(ctx, "Composer", ImGui.TableColumnFlags_WidthStretch, 2)
  ImGui.TableSetupColumn(ctx, "Length", ImGui.TableColumnFlags_WidthFixed, 52)
  ImGui.TableHeadersRow(ctx)
  for _, row in ipairs(app.rows) do
    ImGui.PushID(ctx, row.guid)
    ImGui.TableNextRow(ctx)
    ImGui.TableNextColumn(ctx)
    local changed, include = ImGui.Checkbox(ctx, "##include", row.include)
    if changed then app:set_track_field(row.guid, "include", include) end
    ImGui.TableNextColumn(ctx)
    if row.number then ImGui.Text(ctx, tostring(row.number)) else ImGui.TextDisabled(ctx, "-") end
    cell(ImGui, ctx, app, row, "title", "Title")
    cell(ImGui, ctx, app, row, "artist", app.ep.artist)
    cell(ImGui, ctx, app, row, "isrc", "CCXXXYYNNNNN")
    cell(ImGui, ctx, app, row, "composer", "")
    ImGui.TableNextColumn(ctx)
    ImGui.Text(ctx, duration(row.duration))
    ImGui.PopID(ctx)
  end
  ImGui.EndTable(ctx)
end

return M
