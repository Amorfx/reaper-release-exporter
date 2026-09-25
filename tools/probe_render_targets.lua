-- Dev tool (not shipped): finds out when RENDER_TARGETS is filled. Run on a saved scratch project.
local r = reaper
local proj = 0
local function targets()
  local _, t = r.GetSetProjectInfo_String(proj, "RENDER_TARGETS", "", false)
  return t == "" and "(empty)" or t
end
local function step(label) r.ShowConsoleMsg(("%-45s %s\n"):format(label, targets())) end

r.ClearConsole()
step("0. current settings")
r.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 0, true)
r.GetSetProjectInfo(proj, "RENDER_STARTPOS", 0, true)
r.GetSetProjectInfo(proj, "RENDER_ENDPOS", 5, true)
step("1. custom bounds 0..5 s")
r.GetSetProjectInfo_String(proj, "RENDER_FILE", r.GetResourcePath() .. "/ReleaseExporterProbe", true)
step("2. + RENDER_FILE")
r.GetSetProjectInfo_String(proj, "RENDER_PATTERN", "probe-name", true)
step("3. + RENDER_PATTERN")
r.GetSetProjectInfo_String(proj, "RENDER_FORMAT", "evaw", true)
step("4. + RENDER_FORMAT evaw")
r.GetSetProjectInfo_String(proj, "RENDER_FORMAT2", "l3pm", true)
step("5. + RENDER_FORMAT2 l3pm")
local settings = math.floor(r.GetSetProjectInfo(proj, "RENDER_SETTINGS", 0, false))
r.GetSetProjectInfo(proj, "RENDER_SETTINGS", settings & ~(1 | 2 | 4 | 8 | 32 | 64 | 128 | 4096), true)
step("6. + master mix only")
r.ShowConsoleMsg("REAPER " .. r.GetAppVersion() .. "\n")
