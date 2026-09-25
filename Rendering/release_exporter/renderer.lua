-- Drives REAPER's renderer one region at a time, then restores the user's render settings no matter what.
local fs = require("release_exporter.fs")

local M = {}

M.RENDER_COMMAND = 42230 -- File: Render project, using the most recent render settings, auto-close render dialog

M.NUM_KEYS = {
  "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_STARTPOS", "RENDER_ENDPOS", "RENDER_TAILFLAG",
  "RENDER_SRATE", "RENDER_ADDTOPROJ",
}
M.STR_KEYS = { "RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT", "RENDER_FORMAT2" }

-- Bits of RENDER_SETTINGS that select something other than a plain master mix (stems, matrix, items, razor).
local SOURCE_MASK = 1 | 2 | 4 | 8 | 32 | 64 | 128 | 4096
local EMBED_METADATA = 512
local ADD_TO_PROJECT = 1

local function split(s, sep)
  local out = {}
  for part in (s or ""):gmatch("[^" .. sep .. "]+") do out[#out + 1] = part end
  return out
end

local function metadata_ids(r, proj)
  local _, list = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "", false)
  return split(list, ";")
end

local function clear_metadata(r, proj)
  for _, id in ipairs(metadata_ids(r, proj)) do
    r.GetSetProjectInfo_String(proj, "RENDER_METADATA", id .. "|", true)
  end
end

function M.snapshot(r, proj)
  local state = { num = {}, str = {}, metadata = {} }
  for _, key in ipairs(M.NUM_KEYS) do state.num[key] = r.GetSetProjectInfo(proj, key, 0, false) end
  for _, key in ipairs(M.STR_KEYS) do
    local _, value = r.GetSetProjectInfo_String(proj, key, "", false)
    state.str[key] = value
  end
  for _, id in ipairs(metadata_ids(r, proj)) do
    local _, value = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", id, false)
    state.metadata[#state.metadata + 1] = { id = id, value = value }
  end
  return state
end

function M.restore(r, proj, state)
  for key, value in pairs(state.num) do r.GetSetProjectInfo(proj, key, value, true) end
  for key, value in pairs(state.str) do r.GetSetProjectInfo_String(proj, key, value, true) end
  clear_metadata(r, proj)
  for _, entry in ipairs(state.metadata) do
    r.GetSetProjectInfo_String(proj, "RENDER_METADATA", entry.id .. "|" .. entry.value, true)
  end
end

local function render_one(r, proj, job, opts)
  r.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 0, true)
  r.GetSetProjectInfo(proj, "RENDER_STARTPOS", job.start, true)
  r.GetSetProjectInfo(proj, "RENDER_ENDPOS", job.stop, true)
  r.GetSetProjectInfo(proj, "RENDER_TAILFLAG", 0, true)
  r.GetSetProjectInfo_String(proj, "RENDER_FILE", opts.output_dir, true)
  r.GetSetProjectInfo_String(proj, "RENDER_PATTERN", job.basename, true)
  clear_metadata(r, proj)
  for _, entry in ipairs(job.tags) do r.GetSetProjectInfo_String(proj, "RENDER_METADATA", entry, true) end

  local _, targets = r.GetSetProjectInfo_String(proj, "RENDER_TARGETS", "", false)
  local files = split(targets, ";")
  if #files == 0 then return false, files, "REAPER reported no file to render." end
  for _, path in ipairs(files) do
    -- A file we cannot delete would make REAPER show its own overwrite prompt mid-batch.
    if fs.exists(path) and not fs.remove(path) then return false, files, "Cannot overwrite " .. path end
  end

  r.Main_OnCommand(M.RENDER_COMMAND, 0)

  for _, path in ipairs(files) do
    if not fs.exists(path) or fs.size(path) == 0 then return false, files, "Missing or empty file: " .. path, true end
  end
  return true, files
end

function M.render(r, proj, jobs, opts)
  local report = { items = {} }
  local state = M.snapshot(r, proj)
  local ok, err = pcall(function()
    local settings = math.floor(state.num.RENDER_SETTINGS)
    r.GetSetProjectInfo(proj, "RENDER_SETTINGS", (settings & ~SOURCE_MASK) | EMBED_METADATA, true)
    r.GetSetProjectInfo(proj, "RENDER_ADDTOPROJ", math.floor(state.num.RENDER_ADDTOPROJ) & ~ADD_TO_PROJECT, true)
    r.GetSetProjectInfo(proj, "RENDER_SRATE", opts.srate or 0, true)
    r.GetSetProjectInfo_String(proj, "RENDER_FORMAT", opts.primary_format, true)
    r.GetSetProjectInfo_String(proj, "RENDER_FORMAT2", opts.secondary_format or "", true)
    for i, job in ipairs(jobs) do
      local item_ok, files, item_err, rendered = render_one(r, proj, job, opts)
      local item = { title = job.title, ok = item_ok, files = files, error = item_err }
      report.items[#report.items + 1] = item
      -- A render that ran but produced nothing is usually a cancel: ask before starting the next one.
      if rendered and i < #jobs and opts.on_failure and not opts.on_failure(item) then
        for j = i + 1, #jobs do
          report.items[#report.items + 1] = { title = jobs[j].title, ok = false, skipped = true, files = {}, error = "Skipped." }
        end
        break
      end
    end
  end)
  M.restore(r, proj, state)
  if not ok then report.error = tostring(err) end
  return report
end

return M
