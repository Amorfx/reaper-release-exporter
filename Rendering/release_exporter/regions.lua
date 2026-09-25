-- REAPER adapter for project regions. Takes the API table `r` so it can run against tests/support/fake_reaper.lua.
local M = {}

local function guid_at(r, proj, idx)
  local ok, guid = r.GetSetProjectInfo_String(proj, "MARKER_GUID:" .. idx, "", false)
  if ok and guid ~= "" then return guid:upper() end
end

function M.list(r, proj)
  local out = {}
  local total = r.CountProjectMarkers(proj)
  for idx = 0, total - 1 do
    local rv, isrgn, pos, rgnend, name, number, color = r.EnumProjectMarkers3(proj, idx)
    if rv > 0 and isrgn then
      local guid = guid_at(r, proj, idx)
      if guid then
        out[#out + 1] = { guid = guid, index = idx, number = number, name = name, start = pos, stop = rgnend, color = color }
      end
    end
  end
  return out
end

function M.rename(r, proj, guid, name)
  for _, rgn in ipairs(M.list(r, proj)) do
    if rgn.guid == guid then
      r.Undo_BeginBlock2(proj)
      local flags = name == "" and 1 or 0
      r.SetProjectMarkerByIndex2(proj, rgn.index, true, rgn.start, rgn.stop, rgn.number, name, rgn.color, flags)
      r.Undo_EndBlock2(proj, "Release Exporter: rename region", -1)
      return true
    end
  end
  return false
end

function M.create_from_selected_items(r, proj)
  local count = r.CountSelectedMediaItems(proj)
  if count == 0 then return 0 end
  r.Undo_BeginBlock2(proj)
  for i = 0, count - 1 do
    local item = r.GetSelectedMediaItem(proj, i)
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local take = r.GetActiveTake(item)
    local name = take and r.GetTakeName(take) or ""
    name = name:gsub("%.%w+$", "")
    r.AddProjectMarker2(proj, true, pos, pos + len, name, -1, 0)
  end
  r.Undo_EndBlock2(proj, "Release Exporter: create regions from items", -1)
  return count
end

return M
