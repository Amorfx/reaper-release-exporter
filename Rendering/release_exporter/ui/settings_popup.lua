-- @noindex
-- Export settings modal.
local model = require("release_exporter.model")
local widgets = require("release_exporter.ui.widgets")

local M = { ID = "Export settings" }

local PRIMARY = { { value = "wav24", label = model.FORMAT_LABELS.wav24 }, { value = "wav16", label = model.FORMAT_LABELS.wav16 } }
local SECONDARY = {
  { value = "mp3_320", label = model.FORMAT_LABELS.mp3_320 },
  { value = "flac", label = model.FORMAT_LABELS.flac },
  { value = "none", label = model.FORMAT_LABELS.none },
}
local SAMPLE_RATES = { { value = 0, label = "Project rate" }, { value = 44100, label = "44.1 kHz" }, { value = 48000, label = "48 kHz" } }

function M.draw(ImGui, ctx, app)
  if not ImGui.BeginPopupModal(ctx, M.ID, true, ImGui.WindowFlags_AlwaysAutoResize) then return end
  local s = app.settings

  widgets.label(ImGui, ctx, "Output folder (empty = next to the project)")
  local dir = widgets.text_field(ImGui, ctx, "##output_dir", s.output_dir, { width = 420, hint = app:output_dir() })
  if dir then app:set_setting("output_dir", dir) end
  if app.r.JS_Dialog_BrowseForFolder then
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Browse...") then
      local rv, folder = app.r.JS_Dialog_BrowseForFolder("Choose output folder", app:output_dir())
      if rv == 1 then app:set_setting("output_dir", folder) end
    end
  end

  widgets.label(ImGui, ctx, "File name pattern: {nn} {n} {title} {artist} {album} {year}")
  local pattern = widgets.text_field(ImGui, ctx, "##pattern", s.pattern, { width = 420 })
  if pattern then
    app:set_setting("pattern", model.blank(pattern) and model.default_settings().pattern or pattern)
  end

  widgets.label(ImGui, ctx, "Main format")
  local primary = widgets.combo(ImGui, ctx, "##primary", s.primary, PRIMARY, 200)
  if primary then app:set_setting("primary", primary) end

  widgets.label(ImGui, ctx, "Second format")
  local secondary = widgets.combo(ImGui, ctx, "##secondary", s.secondary, SECONDARY, 200)
  if secondary then app:set_setting("secondary", secondary) end

  widgets.label(ImGui, ctx, "Sample rate")
  local srate = widgets.combo(ImGui, ctx, "##srate", s.srate, SAMPLE_RATES, 200)
  if srate then app:set_setting("srate", srate) end

  ImGui.Separator(ctx)
  if ImGui.Button(ctx, "Close") then ImGui.CloseCurrentPopup(ctx) end
  ImGui.EndPopup(ctx)
end

return M
