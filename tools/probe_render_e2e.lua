-- Dev tool (not shipped): renders the first 2 seconds of the current project through the real
-- metadata_mapper + renderer, once as WAV+MP3 and once as WAV+FLAC, into <resource path>/ReleaseExporterProbe.
-- Put any audio item in the first 2 seconds, and a cover.png in that folder, then inspect the files.
local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*[/\\])") .. "../Rendering/"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path

local mapper = require("release_exporter.metadata_mapper")
local renderer = require("release_exporter.renderer")
local fs = require("release_exporter.fs")
local formats = require("release_exporter.formats")

local proj = 0
local dir = r.GetResourcePath() .. "/ReleaseExporterProbe"
local function p(s) r.ShowConsoleMsg(s .. "\n") end

r.ClearConsole()
fs.ensure_dir(r, dir)
local cover = dir .. "/cover.png"
if not fs.exists(cover) then p("WARNING: no cover.png in " .. dir) end

local tags = mapper.build({
  title = "e2e-title", artist = "e2e-artist", album_artist = "e2e-album-artist", album = "e2e-album",
  year = "2026", genre = "e2e-genre", label = "e2e-label", copyright = "e2e-copyright", cover = cover,
  isrc = "FRXXX2600001", composer = "e2e-composer", number = 2, total = 5,
})
-- Alternatives we want to learn about, on top of what the mapper writes today.
for _, extra in ipairs({ "ID3:TDRC|2026-09-25", "VORBIS:LABEL|e2e-vorbis-label", "VORBIS:TOTALTRACKS|5" }) do
  tags[#tags + 1] = extra
end

-- 1. Which identifiers does REAPER keep when we set them?
local state = renderer.snapshot(r, proj)
for _, entry in ipairs(tags) do r.GetSetProjectInfo_String(proj, "RENDER_METADATA", entry, true) end
local _, kept = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "", false)
local kept_set = {}
for id in kept:gmatch("[^;]+") do kept_set[id] = true end
p("=== identifiers ===")
for _, entry in ipairs(tags) do
  local id = entry:match("^([^|]+)")
  p((kept_set[id] and "KEPT     " or "DROPPED  ") .. id)
end
renderer.restore(r, proj, state)

-- 2. Real renders through the renderer (restores the user's settings afterwards).
p("=== renders ===")
-- Uses the shipped presets, so this also verifies formats.lua (bit depth, MP3 bitrate).
for _, run in ipairs({
  { name = "e2e-wav24-mp3", primary = "wav24", secondary = "mp3_320" },
  { name = "e2e-wav16-flac", primary = "wav16", secondary = "flac" },
}) do
  local report = renderer.render(r, proj, { { title = run.name, basename = run.name, start = 0, stop = 2, tags = tags } },
    { output_dir = dir, primary_format = formats.primary(run.primary), secondary_format = formats.secondary(run.secondary),
      srate = 0 })
  local item = report.items[1] or {}
  p(("%s ok=%s %s %s"):format(run.name, tostring(item.ok), item.error or "", report.error or ""))
  for _, path in ipairs(item.files or {}) do p("  " .. path) end
end
