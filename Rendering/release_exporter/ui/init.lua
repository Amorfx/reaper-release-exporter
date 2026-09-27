-- @noindex
-- Main window layout: release card, songs table, export bar.
local ep_panel = require("release_exporter.ui.ep_panel")
local tracks_table = require("release_exporter.ui.tracks_table")
local export_bar = require("release_exporter.ui.export_bar")
local widgets = require("release_exporter.ui.widgets")

local M = {}

-- Room kept below the songs table. The bar's height depends on its chips, so it is measured every
-- frame and applied on the next one; this is only the first frame's guess.
local bar_height = 104
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
  tracks_table.draw(ImGui, ctx, app, bar_height)
  local top = ImGui.GetCursorPosY(ctx)
  export_bar.draw(ImGui, ctx, app)
  -- Includes the trailing item spacing, which matches the gap the table leaves above the bar.
  bar_height = ImGui.GetCursorPosY(ctx) - top
end

return M
