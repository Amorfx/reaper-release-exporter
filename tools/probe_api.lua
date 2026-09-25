-- Dev tool (not shipped): checks the API behaviors release_exporter relies on. Run on a scratch project.
local r = reaper
local proj = 0
local function p(label, ok, detail) r.ShowConsoleMsg(("%s %s %s\n"):format(ok and "PASS" or "FAIL", label, detail or "")) end
local function meta(id) local _, v = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", id, false); return v end

r.ClearConsole()

-- 1. Metadata set / read / clear with "ID|" and values containing "|"
r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "ID3:TIT2|A|B; C", true)
p("metadata value with separators", meta("ID3:TIT2") == "A|B; C", meta("ID3:TIT2"))
r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "ID3:TIT2|", true)
local _, ids = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "", false)
p("clearing removes the id from the list", not ids:find("ID3:TIT2", 1, true), ids)

-- 2. MARKER_GUID on a region
local idx = r.AddProjectMarker2(proj, true, 0, 5, "probe", -1, 0)
local count = r.CountProjectMarkers(proj)
local guid
for i = 0, count - 1 do
  local _, isrgn, _, _, name, number = r.EnumProjectMarkers3(proj, i)
  if isrgn and number == idx and name == "probe" then
    local _, g = r.GetSetProjectInfo_String(proj, "MARKER_GUID:" .. i, "", false)
    guid = g
  end
end
p("MARKER_GUID returns a GUID", guid and guid:match("^{.+}$") ~= nil, guid)

-- 3. ProjExtState key case in EnumProjExtState
r.SetProjExtState(proj, "ReleaseExporterProbe", "track:{abc}", "x")
local _, key = r.EnumProjExtState(proj, "ReleaseExporterProbe", 0)
p("EnumProjExtState key case", true, "returned key = " .. tostring(key))
r.SetProjExtState(proj, "ReleaseExporterProbe", "", "")

-- 4. RENDER_TARGETS follows custom bounds + pattern
r.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 0, true)
r.GetSetProjectInfo_String(proj, "RENDER_PATTERN", "probe-name", true)
local _, targets = r.GetSetProjectInfo_String(proj, "RENDER_TARGETS", "", false)
p("RENDER_TARGETS uses the pattern", targets:find("probe-name", 1, true) ~= nil, targets)

-- 5. RecursiveCreateDirectory return value on an existing folder
local dir = r.GetResourcePath() .. "/ReleaseExporterProbe"
p("RecursiveCreateDirectory (new)", r.RecursiveCreateDirectory(dir, 0) > 0)
p("RecursiveCreateDirectory (existing)", true, "returned " .. r.RecursiveCreateDirectory(dir, 0))
