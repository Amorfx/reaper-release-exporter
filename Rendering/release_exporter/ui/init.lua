-- Main window layout: EP card, songs table, export bar.
local ep_panel = require("release_exporter.ui.ep_panel")
local tracks_table = require("release_exporter.ui.tracks_table")
local export_bar = require("release_exporter.ui.export_bar")

local M = {}

local EXPORT_BAR_HEIGHT = 110

function M.draw(ImGui, ctx, app)
  ep_panel.draw(ImGui, ctx, app)
  ImGui.Spacing(ctx)
  local _, height = ImGui.GetContentRegionAvail(ctx)
  tracks_table.draw(ImGui, ctx, app, math.max(120, height - EXPORT_BAR_HEIGHT))
  export_bar.draw(ImGui, ctx, app)
end

return M
