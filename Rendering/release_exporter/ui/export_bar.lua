-- @noindex
-- Bottom bar: issues, summary, Settings and Export buttons, and the confirmation modal.
local model = require("release_exporter.model")
local widgets = require("release_exporter.ui.widgets")
local settings_popup = require("release_exporter.ui.settings_popup")
local report_popup = require("release_exporter.ui.report_popup")

local M = {}

local CONFIRM_ID = "Confirm export"
local MAX_CHIPS = 4
local existing = {}

function M.export_label(count)
  if count == 0 then return "Export" end
  return ("Export %d %s"):format(count, count == 1 and "song" or "songs")
end

local function button_width(ImGui, ctx, label)
  local pad = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
  return ImGui.CalcTextSize(ctx, label) + pad * 2
end

local function draw_confirm(ImGui, ctx, app, jobs)
  if not ImGui.BeginPopupModal(ctx, CONFIRM_ID, true, ImGui.WindowFlags_AlwaysAutoResize) then return end
  local files = 0
  for _, job in ipairs(jobs) do files = files + #job.files end
  ImGui.Text(ctx, ("%d songs -> %d files in"):format(#jobs, files))
  widgets.label(ImGui, ctx, app:output_dir())
  if #existing > 0 then
    ImGui.TextColored(ctx, widgets.COLOR_WARNING, ("%d files already exist and will be overwritten."):format(#existing))
  end
  ImGui.Separator(ctx)
  if widgets.primary_button(ImGui, ctx, #existing > 0 and "Overwrite and export" or "Export") then
    app.pending_export = true
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Cancel") then ImGui.CloseCurrentPopup(ctx) end
  ImGui.EndPopup(ctx)
end

function M.draw(ImGui, ctx, app)
  local v = app.validation
  local jobs = app:jobs()
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)
  local chips = widgets.issue_chips(v.errors, v.warnings, MAX_CHIPS)
  if #chips.visible > 0 then widgets.chip_row(ImGui, ctx, chips) end

  local s = app.settings
  local formats = model.FORMAT_LABELS[s.primary]
  if s.secondary ~= "none" then formats = formats .. " + " .. model.FORMAT_LABELS[s.secondary] end
  local example = jobs[1] and jobs[1].basename or "-"
  local folder = widgets.short_path(app:output_dir(), os.getenv("HOME"))
  ImGui.AlignTextToFramePadding(ctx)
  widgets.label(ImGui, ctx, ("%s  ·  %s  ·  e.g. %s"):format(formats, folder, example))

  local export = M.export_label(#jobs)
  local gap = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local buttons = button_width(ImGui, ctx, "Settings") + gap + button_width(ImGui, ctx, export)
  -- Right-align the buttons, but never over the summary on a narrow window.
  local after_summary = ImGui.GetItemRectMax(ctx) - ImGui.GetWindowPos(ctx) + gap
  local right = ImGui.GetWindowWidth(ctx) - buttons - ImGui.GetStyleVar(ctx, ImGui.StyleVar_WindowPadding)
  ImGui.SameLine(ctx, math.max(after_summary, right))
  if ImGui.Button(ctx, "Settings") then ImGui.OpenPopup(ctx, settings_popup.ID) end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, not app:can_export())
  if widgets.primary_button(ImGui, ctx, export) then
    existing = app:existing_files()
    ImGui.OpenPopup(ctx, CONFIRM_ID)
  end
  ImGui.EndDisabled(ctx)

  settings_popup.draw(ImGui, ctx, app)
  draw_confirm(ImGui, ctx, app, jobs)
  report_popup.draw(ImGui, ctx, app)
end

return M
