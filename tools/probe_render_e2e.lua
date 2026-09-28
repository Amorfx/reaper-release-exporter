-- Dev tool (not shipped): renders the first 2 seconds of the current project through the real
-- metadata_mapper, formats and renderer, once as WAV 24 + MP3 and once as WAV 16 + FLAC, with every tag and
-- tools/fixtures/cover.png. Put any audio item in the first 2 seconds of a scratch project, run it, then check
-- the files (bit depth, bitrate, tags, cover) with the exiftool command it prints.
-- Results go to the ReaScript console and to <resource path>/ReleaseExporterProbe/probe_render_e2e.log.
local r = reaper
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local root = here .. "../Rendering/"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path

local mapper = require("release_exporter.metadata_mapper")
local renderer = require("release_exporter.renderer")
local fs = require("release_exporter.fs")
local formats = require("release_exporter.formats")

local proj = 0
local dir = r.GetResourcePath() .. "/ReleaseExporterProbe"
fs.ensure_dir(r, dir)
local log = io.open(dir .. "/probe_render_e2e.log", "w")
local function p(s)
  r.ShowConsoleMsg(s .. "\n")
  if log then log:write(s, "\n") end
end

r.ClearConsole()
local tags = mapper.build({
  title = "e2e-title", artist = "e2e-artist", album_artist = "e2e-album-artist", album = "e2e-album",
  year = "2026-09-25", genre = "e2e-genre", label = "e2e-label", copyright = "e2e-copyright",
  cover = here .. "fixtures/cover.png", isrc = "FRXXX2600001", composer = "e2e-composer", number = 2, total = 5,
})

-- The renderer restores the user's render settings afterwards.
local ok = true
for _, run in ipairs({
  { name = "e2e-wav24-mp3", primary = "wav24", secondary = "mp3_320" },
  { name = "e2e-wav16-flac", primary = "wav16", secondary = "flac" },
}) do
  local report = renderer.render(r, proj, { { title = run.name, basename = run.name, start = 0, stop = 2, tags = tags } },
    { output_dir = dir, primary_format = formats.primary(run.primary), secondary_format = formats.secondary(run.secondary),
      srate = 0 })
  local item = report.items[1] or {}
  ok = ok and item.ok == true
  p(("%s %s %s %s"):format(item.ok and "PASS" or "FAIL", run.name, item.error or "", report.error or ""))
  for _, path in ipairs(item.files or {}) do p("  " .. path) end
end
p(ok and "Rendered. Expected: 24-bit + 320 kbps, 16-bit + 24-bit FLAC, every tag and a front cover." or "Some renders failed.")
p(('exiftool -G1 -a -BitsPerSample -AudioBitrate -Title -Artist -Album -Track -ISRC -ISRCNumber -PictureType "%s"/e2e-*')
  :format(dir))
if log then log:close() end
