-- @noindex
-- Small file-system helpers built on plain Lua io/os plus the REAPER API where needed.
local M = {}

function M.exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

function M.size(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local size = f:seek("end")
  f:close()
  return size or 0
end

function M.remove(path)
  return os.remove(path)
end

-- Files and folders alike, on every platform: renaming a path onto itself fails with ENOENT (2) only when
-- it does not exist. Other errors (permission denied, read-only volume) still mean it is there.
local ENOENT = 2
local function exists_any(path)
  local ok, _, code = os.rename(path, path)
  return ok ~= nil or code ~= ENOENT
end

-- Tells whether ensure_dir would succeed, without creating anything: the nearest existing parent must be a
-- folder we can write to.
function M.can_create_dir(path)
  local dir = path:gsub("[/\\]+$", "")
  while dir ~= "" and not exists_any(dir) do
    local parent = dir:match("^(.*)[/\\][^/\\]*$")
    if not parent or parent == dir then return false end
    dir = parent
  end
  local probe = (dir == "" and "" or dir) .. "/.release_exporter_probe"
  local f = io.open(probe, "wb")
  if not f then return false end
  f:close()
  os.remove(probe)
  return true
end

-- Creates the folder, then proves it is writable with a probe file.
function M.ensure_dir(r, path)
  r.RecursiveCreateDirectory(path, 0)
  local probe = path .. "/.release_exporter_probe"
  local f = io.open(probe, "wb")
  if not f then return false end
  f:close()
  os.remove(probe)
  return true
end

-- Asks for a JPEG or PNG file. REAPER's own dialog only filters on one extension, so without
-- js_ReaScriptAPI it shows every file and the model rejects other formats.
-- Returns the chosen path, or nil when cancelled.
function M.choose_image(r, title)
  if r.JS_Dialog_BrowseForOpenFiles then
    local rv, path = r.JS_Dialog_BrowseForOpenFiles(title, "", "", "Images (JPEG, PNG)\0*.jpg;*.jpeg;*.png\0\0", false)
    if rv == 1 and path ~= "" then return path end
    return nil
  end
  local ok, path = r.GetUserFileNameForRead("", title, "")
  if ok and path ~= "" then return path end
  return nil
end

function M.open_folder(r, path)
  if r.CF_ShellExecute then return r.CF_ShellExecute(path) end
  local os_name = r.GetOS()
  if os_name:match("^Win") then
    os.execute('start "" "' .. path:gsub("/", "\\") .. '"')
  elseif os_name:match("^OSX") or os_name:match("^macOS") then
    os.execute('open "' .. path .. '"')
  else
    os.execute('xdg-open "' .. path .. '"')
  end
end

return M
