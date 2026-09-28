-- @description Release Exporter: tag a single, EP or album and export every song in one click
-- @author Clément Décou
-- @link https://github.com/Amorfx/reaper-release-plugin
-- @version 0.1.0
-- @about
--   Fill release-level and per-song metadata (title, artist, ISRC, composer, cover...) in one window,
--   then render every region of the project as WAV + MP3/FLAC with embedded tags.
--   Requires ReaImGui (ReaTeam Extensions).
-- @provides
--   [nomain] release_exporter/*.lua
--   [nomain] release_exporter/ui/*.lua
--   [nomain] release_exporter/vendor/*.lua
local r = reaper

if not r.ImGui_GetBuiltinPath then
  r.ShowMessageBox("Release Exporter needs ReaImGui 0.9 or newer.\n\n"
    .. "Install it with Extensions > ReaPack > Browse packages > \"ReaImGui\", then restart REAPER.",
    "Release Exporter", 0)
  return
end

local script_dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
package.path = r.ImGui_GetBuiltinPath() .. "/?.lua;" .. script_dir .. "?.lua;" .. script_dir .. "?/init.lua;"
  .. package.path

local ImGui = require("imgui")("0.9")
local App = require("release_exporter.app")
local ui = require("release_exporter.ui")
local theme = require("release_exporter.ui.theme")

local app = App.new(r)
local ctx = ImGui.CreateContext("Release Exporter")

local function loop()
  -- Rendering blocks REAPER, so it runs between frames rather than inside Begin/End.
  if app.pending_export then
    app.pending_export = false
    app:export()
    app.show_report = true
    -- ReaImGui frees contexts that miss defer cycles; a long render may have done that.
    if not ImGui.ValidatePtr(ctx, "ImGui_Context*") then
      ctx = ImGui.CreateContext("Release Exporter")
      ui.reset()
    end
  end
  app:refresh()
  ImGui.SetNextWindowSize(ctx, 980, 640, ImGui.Cond_FirstUseEver)
  theme.push(ImGui, ctx)
  local visible, open = ImGui.Begin(ctx, "Release Exporter", true)
  if visible then
    ui.draw(ImGui, ctx, app)
    ImGui.End(ctx)
  end
  theme.pop(ImGui, ctx)
  if open then r.defer(loop) end
end

r.defer(loop)
