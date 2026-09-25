-- Dev tool (not shipped): prints the current project's render state to the REAPER console.
local r = reaper
local proj = 0
local function p(s) r.ShowConsoleMsg(s .. "\n") end

r.ClearConsole()
p("=== RENDER_METADATA ===")
local _, ids = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "", false)
for id in ids:gmatch("[^;]+") do
  local _, value = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", id, false)
  p(id .. " = " .. value)
end
p("=== STRINGS ===")
for _, key in ipairs({ "RENDER_FORMAT", "RENDER_FORMAT2", "RENDER_FILE", "RENDER_PATTERN", "RENDER_TARGETS" }) do
  local _, value = r.GetSetProjectInfo_String(proj, key, "", false)
  p(key .. " = " .. value)
end
p("=== NUMBERS ===")
for _, key in ipairs({ "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_SRATE", "RENDER_ADDTOPROJ", "RENDER_TAILFLAG" }) do
  p(key .. " = " .. tostring(r.GetSetProjectInfo(proj, key, 0, false)))
end
