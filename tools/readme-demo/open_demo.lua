-- Dev tool (not shipped): opens a README demo project. Run it from the Actions list, or from a terminal with
--   /Applications/REAPER.app/Contents/MacOS/REAPER -nonewinst tools/readme-demo/open_demo.lua
-- The first run opens out/demo.rpp in a new tab. When the active tab already holds a demo project, it is
-- replaced by the next one (demo -> demo-invalid -> demo-empty -> demo), discarding unsaved demo edits.
local r = reaper
local dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])") .. "out/"
local ORDER = { "demo.rpp", "demo-invalid.rpp", "demo-empty.rpp" }

local _, current = r.EnumProjects(-1)
local name = current:match("[/\\](demo[%w%-]*%.rpp)$")
if not name or not current:find("readme-demo/out/", 1, true) then
  r.Main_OnCommand(40859, 0) -- New project tab
  r.Main_openProject(dir .. ORDER[1])
  return
end
for i, candidate in ipairs(ORDER) do
  if candidate == name then
    r.Main_openProject("noprompt:" .. dir .. ORDER[i % #ORDER + 1])
    return
  end
end
