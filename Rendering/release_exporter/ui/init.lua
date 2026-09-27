-- @noindex
-- Main window layout: release card, songs table, export bar.
local ep_panel = require("release_exporter.ui.ep_panel")
local tracks_table = require("release_exporter.ui.tracks_table")
local export_bar = require("release_exporter.ui.export_bar")
local widgets = require("release_exporter.ui.widgets")

local M = {}

local EXPORT_BAR_HEIGHT = 104
local generation

function M.reset()
  widgets.reset()
  ep_panel.reset()
end

function M.draw(ImGui, ctx, app)
  -- A reloaded project must never receive drafts typed in the previous one.
  if app.generation ~= generation then
    widgets.reset()
    generation = app.generation
  end
  ep_panel.draw(ImGui, ctx, app)
  ImGui.Dummy(ctx, 0, 4)
  tracks_table.draw(ImGui, ctx, app, EXPORT_BAR_HEIGHT)
  export_bar.draw(ImGui, ctx, app)
end

return M
