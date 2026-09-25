-- Export report modal, opened by the main loop once an export finishes.
local fs = require("release_exporter.fs")
local widgets = require("release_exporter.ui.widgets")

local M = { ID = "Export report" }

function M.draw(ImGui, ctx, app)
  if app.show_report then
    ImGui.OpenPopup(ctx, M.ID)
    app.show_report = false
  end
  if not ImGui.BeginPopupModal(ctx, M.ID, true, ImGui.WindowFlags_AlwaysAutoResize) then return end
  local report = app.last_report
  if report.error then ImGui.TextColored(ctx, widgets.COLOR_ERROR, "Export stopped: " .. report.error) end
  for _, item in ipairs(report.items) do
    if item.ok then
      ImGui.Text(ctx, "OK      " .. item.title)
    else
      ImGui.TextColored(ctx, widgets.COLOR_ERROR, "FAILED  " .. item.title .. " - " .. (item.error or ""))
    end
    for _, path in ipairs(item.files or {}) do ImGui.TextDisabled(ctx, "        " .. path) end
  end
  ImGui.Separator(ctx)
  if ImGui.Button(ctx, "Open folder") then fs.open_folder(app.r, report.output_dir) end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Close") then ImGui.CloseCurrentPopup(ctx) end
  ImGui.EndPopup(ctx)
end

return M
