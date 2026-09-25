-- In-memory stand-in for the subset of the REAPER API that release_exporter uses.
local M = {}

local FORMAT_EXT = { evaw = "wav", l3pm = "mp3", calf = "flac" }

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function M.new()
  local r = {}
  local projects = {}
  local num, str, metadata, global_ext = {}, {}, {}, {}
  local next_id = 0

  local function state(proj)
    projects[proj] = projects[proj] or { markers = {}, ext = {} }
    return projects[proj]
  end

  r.proj = { id = 1 }
  r.projfn = "/music/ep/EP.rpp"
  r.change_count = 0
  r.dirty = 0
  r.undo_points = {}
  r.commands = {}
  r.selected_items = {}
  r.render_behavior = "ok" -- "ok" | "missing" | "error", or function(call_index) returning one of them
  r.os = "OSX64"

  local function touch() r.change_count = r.change_count + 1 end
  local function markers() return state(r.proj).markers end
  local function sort() table.sort(markers(), function(a, b) return a.start < b.start end) end

  local function add(isrgn, start, stop, name)
    next_id = next_id + 1
    local list = markers()
    list[#list + 1] = {
      isrgn = isrgn, start = start, stop = stop, name = name, number = next_id, color = 0,
      guid = string.format("{%08X-0000-0000-0000-000000000000}", next_id),
    }
    sort()
    touch()
    return next_id
  end

  -- Test helpers
  function r.add_region(start, stop, name) return add(true, start, stop, name) end
  function r.add_marker(pos, name) return add(false, pos, pos, name) end
  function r.markers() return markers() end
  function r.metadata() return metadata end
  function r.remove_region(guid)
    for i, m in ipairs(markers()) do
      if m.guid == guid then
        table.remove(markers(), i)
        touch()
        return m
      end
    end
  end
  function r.restore_marker(marker)
    local list = markers()
    list[#list + 1] = marker
    sort()
    touch()
  end
  function r.switch_project()
    r.proj = { id = r.proj.id + 1 }
    r.projfn = "/music/other/Other.rpp"
  end

  -- Projects and markers
  function r.EnumProjects(idx)
    if idx == -1 then return r.proj, r.projfn end
  end
  function r.GetProjectStateChangeCount() return r.change_count end
  function r.CountProjectMarkers(proj)
    local list, regions = state(proj).markers, 0
    for _, m in ipairs(list) do
      if m.isrgn then regions = regions + 1 end
    end
    return #list, #list - regions, regions
  end
  function r.EnumProjectMarkers3(proj, idx)
    local m = state(proj).markers[idx + 1]
    if not m then return 0, false, 0, 0, "", 0, 0 end
    return idx + 1, m.isrgn, m.start, m.stop, m.name, m.number, m.color
  end
  function r.SetProjectMarkerByIndex2(proj, idx, isrgn, pos, stop, number, name, color, flags)
    local m = state(proj).markers[idx + 1]
    if not m then return false end
    m.isrgn, m.start, m.stop, m.number, m.color = isrgn, pos, stop, number, color
    if flags & 1 == 1 then m.name = "" elseif name ~= "" then m.name = name end
    sort()
    touch()
    return true
  end
  function r.AddProjectMarker2(_, isrgn, pos, stop, name) return add(isrgn, pos, stop, name) end

  -- Project info
  function r.GetSetProjectInfo(_, key, value, is_set)
    if is_set then num[key] = value end
    return num[key] or 0
  end
  function r.render_targets()
    local out = {}
    for _, key in ipairs({ "RENDER_FORMAT", "RENDER_FORMAT2" }) do
      -- Base64 configs captured in Task 2 are opaque here: treat any unknown primary as WAV, secondary as MP3.
      local value = str[key] or ""
      local ext = FORMAT_EXT[value] or (value ~= "" and (key == "RENDER_FORMAT" and "wav" or "mp3")) or nil
      if ext then out[#out + 1] = (str.RENDER_FILE or "") .. "/" .. (str.RENDER_PATTERN or "") .. "." .. ext end
    end
    return out
  end
  function r.GetSetProjectInfo_String(proj, key, value, is_set)
    local idx = key:match("^MARKER_GUID:(%d+)$")
    if idx then
      local m = state(proj).markers[tonumber(idx) + 1]
      return m ~= nil, m and m.guid or ""
    end
    if key == "RENDER_METADATA" then
      if is_set then
        local id, v = value:match("^([^|]+)|(.*)$")
        metadata[id] = v ~= "" and v or nil
        return true, value
      elseif value == "" then
        local ids = {}
        for id in pairs(metadata) do ids[#ids + 1] = id end
        table.sort(ids)
        return true, table.concat(ids, ";")
      end
      return true, metadata[value] or ""
    end
    if key == "RENDER_TARGETS" then return true, table.concat(r.render_targets(), ";") end
    if is_set then str[key] = value end
    return true, str[key] or ""
  end

  -- Ext state
  function r.SetProjExtState(proj, section, key, value)
    local ext = state(proj).ext
    ext[section] = ext[section] or {}
    ext[section][key] = value ~= "" and value or nil
    return 0
  end
  function r.GetProjExtState(proj, section, key)
    local v = state(proj).ext[section] and state(proj).ext[section][key]
    return v and 1 or 0, v or ""
  end
  function r.EnumProjExtState(proj, section, idx)
    local values = state(proj).ext[section] or {}
    local keys = {}
    for k in pairs(values) do keys[#keys + 1] = k end
    table.sort(keys)
    local k = keys[idx + 1]
    if not k then return false end
    return true, k, values[k]
  end
  function r.SetExtState(section, key, value) global_ext[section .. "/" .. key] = value end
  function r.GetExtState(section, key) return global_ext[section .. "/" .. key] or "" end

  -- Undo, dirty
  function r.MarkProjectDirty() r.dirty = r.dirty + 1 end
  function r.Undo_BeginBlock2() end
  function r.Undo_EndBlock2(_, desc) r.undo_points[#r.undo_points + 1] = desc end

  -- Rendering and files
  function r.Main_OnCommand(cmd)
    r.commands[#r.commands + 1] = {
      cmd = cmd, pattern = str.RENDER_PATTERN, metadata = copy(metadata),
      bounds = { num.RENDER_STARTPOS, num.RENDER_ENDPOS }, boundsflag = num.RENDER_BOUNDSFLAG,
      settings = num.RENDER_SETTINGS, addtoproj = num.RENDER_ADDTOPROJ,
    }
    local behavior = r.render_behavior
    if type(behavior) == "function" then behavior = behavior(#r.commands) end
    if behavior == "error" then error("render exploded") end
    if behavior == "ok" then
      for _, path in ipairs(r.render_targets()) do
        local f = assert(io.open(path, "wb"))
        f:write("RIFF")
        f:close()
      end
    end
  end
  function r.RecursiveCreateDirectory(path)
    return os.execute('mkdir -p "' .. path .. '" 2>/dev/null') and 1 or 0
  end
  function r.file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
  end
  function r.GetOS() return r.os end

  -- Media items
  function r.CountSelectedMediaItems() return #r.selected_items end
  function r.GetSelectedMediaItem(_, i) return r.selected_items[i + 1] end
  function r.GetMediaItemInfo_Value(item, key)
    if key == "D_POSITION" then return item.pos end
    if key == "D_LENGTH" then return item.len end
    return 0
  end
  function r.GetActiveTake(item) return item.take end
  function r.GetTakeName(take) return take.name end

  return r
end

return M
