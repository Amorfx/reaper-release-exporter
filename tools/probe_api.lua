-- Dev tool (not shipped): checks the REAPER behaviours release_exporter relies on (docs/reaper-api-notes.md).
-- Run it on a scratch project: it adds then removes a region and restores every render setting it touches.
-- Results go to the ReaScript console and to <resource path>/ReleaseExporterProbe/probe_api.log.
local r = reaper
local root = debug.getinfo(1, "S").source:match("^@(.*[/\\])") .. "../Rendering/"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path
local renderer = require("release_exporter.renderer")

local proj = 0
local dir = r.GetResourcePath() .. "/ReleaseExporterProbe"
r.RecursiveCreateDirectory(dir, 0)
local log = io.open(dir .. "/probe_api.log", "w")
local function p(label, ok, detail)
  local line = ("%s %s %s"):format(ok and "PASS" or "FAIL", label, detail or "")
  r.ShowConsoleMsg(line .. "\n")
  if log then log:write(line, "\n") end
end
local function meta(id)
  local _, v = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", id, false)
  return v
end
local function targets()
  local _, t = r.GetSetProjectInfo_String(proj, "RENDER_TARGETS", "", false)
  return t
end

r.ClearConsole()
local state = renderer.snapshot(r, proj)

-- 1. Metadata values keep "|" and ";" after the first separator, and "<id>|" clears an entry.
r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "ID3:TIT2|A|B; C", true)
p("metadata value with separators", meta("ID3:TIT2") == "A|B; C", meta("ID3:TIT2"))
r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "ID3:TIT2|", true)
local _, ids = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "", false)
p("clearing removes the id from the list", not ids:find("ID3:TIT2", 1, true), ids)

-- 2. MARKER_GUID:<enumeration index> returns the region's GUID.
local number = r.AddProjectMarker2(proj, true, 0, 5, "probe", -1, 0)
local guid
for i = 0, r.CountProjectMarkers(proj) - 1 do
  local _, isrgn, _, _, name, idx = r.EnumProjectMarkers3(proj, i)
  if isrgn and idx == number and name == "probe" then
    guid = select(2, r.GetSetProjectInfo_String(proj, "MARKER_GUID:" .. i, "", false))
  end
end
p("MARKER_GUID returns a GUID", guid ~= nil and guid:match("^{.+}$") ~= nil, guid)
r.DeleteProjectMarker(proj, number, true)

-- 3. EnumProjExtState returns upper-cased keys (project_store and regions upper-case GUIDs to match).
r.SetProjExtState(proj, "ReleaseExporterProbe", "track:{abc}", "x")
local _, key = r.EnumProjExtState(proj, "ReleaseExporterProbe", 0)
p("EnumProjExtState upper-cases keys", key == "TRACK:{ABC}", key)
r.SetProjExtState(proj, "ReleaseExporterProbe", "", "")

-- 4. RENDER_TARGETS is empty for zero-length bounds, and follows bounds, folder, pattern and second format.
r.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 0, true)
r.GetSetProjectInfo(proj, "RENDER_STARTPOS", 0, true)
r.GetSetProjectInfo(proj, "RENDER_ENDPOS", 0, true)
p("RENDER_TARGETS is empty for zero-length bounds", targets() == "", targets())
r.GetSetProjectInfo(proj, "RENDER_ENDPOS", 5, true)
r.GetSetProjectInfo_String(proj, "RENDER_FILE", dir, true)
r.GetSetProjectInfo_String(proj, "RENDER_PATTERN", "probe-name", true)
r.GetSetProjectInfo_String(proj, "RENDER_FORMAT", "evaw", true)
r.GetSetProjectInfo_String(proj, "RENDER_FORMAT2", "l3pm", true)
local t = targets()
p("RENDER_TARGETS lists both formats", t:find("probe-name.wav", 1, true) ~= nil and t:find("probe-name.mp3", 1, true) ~= nil, t)

-- 5. RecursiveCreateDirectory returns 0 on an existing folder, so fs.ensure_dir ignores its result.
p("RecursiveCreateDirectory on an existing folder", true, "returned " .. r.RecursiveCreateDirectory(dir, 0))

renderer.restore(r, proj, state)
p("REAPER", true, r.GetAppVersion())
if log then log:close() end
