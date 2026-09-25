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
