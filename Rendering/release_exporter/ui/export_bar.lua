-- @noindex
-- Bottom bar: issues, summary, Settings and Export buttons, and the confirmation modal.
local model = require("release_exporter.model")
local widgets = require("release_exporter.ui.widgets")
local settings_popup = require("release_exporter.ui.settings_popup")
local report_popup = require("release_exporter.ui.report_popup")

local M = {}

local CONFIRM_ID = "Confirm export"
local MAX_LINES = 3
local existing = {}

local function draw_issues(ImGui, ctx, issues, color, prefix)
  for i, issue in ipairs(issues) do
    if i > MAX_LINES then
      ImGui.TextColored(ctx, color, ("... and %d more"):format(#issues - MAX_LINES))
      break
    end
    ImGui.TextColored(ctx, color, prefix .. issue.message)
  end
end

local function draw_confirm(ImGui, ctx, app, jobs)
  if not ImGui.BeginPopupModal(ctx, CONFIRM_ID, true, ImGui.WindowFlags_AlwaysAutoResize) then return end
  local files = 0
  for _, job in ipairs(jobs) do files = files + #job.files end
  ImGui.Text(ctx, ("%d songs -> %d files in"):format(#jobs, files))
  ImGui.TextDisabled(ctx, app:output_dir())
  if #existing > 0 then
    ImGui.TextColored(ctx, widgets.COLOR_WARNING, ("%d files already exist and will be overwritten."):format(#existing))
  end
  ImGui.Separator(ctx)
  if ImGui.Button(ctx, #existing > 0 and "Overwrite and export" or "Export") then
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
  draw_issues(ImGui, ctx, v.errors, widgets.COLOR_ERROR, "Error: ")
  if #v.errors == 0 then draw_issues(ImGui, ctx, v.warnings, widgets.COLOR_WARNING, "Warning: ") end

  local s = app.settings
  local formats = model.FORMAT_LABELS[s.primary]
  if s.secondary ~= "none" then formats = formats .. " + " .. model.FORMAT_LABELS[s.secondary] end
  local example = jobs[1] and jobs[1].basename or "-"
  ImGui.TextDisabled(ctx, ("%s  |  %s  |  e.g. %s"):format(formats, app:output_dir(), example))

  if ImGui.Button(ctx, "Settings...") then ImGui.OpenPopup(ctx, settings_popup.ID) end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, not app:can_export())
  if ImGui.Button(ctx, ("Export EP (%d)"):format(#jobs)) then
    existing = app:existing_files()
    ImGui.OpenPopup(ctx, CONFIRM_ID)
  end
  ImGui.EndDisabled(ctx)

  settings_popup.draw(ImGui, ctx, app)
  draw_confirm(ImGui, ctx, app, jobs)
  report_popup.draw(ImGui, ctx, app)
end

return M
