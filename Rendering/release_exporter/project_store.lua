-- @noindex
-- REAPER adapter: persists release (key "ep"), track and settings data in the project (ProjExtState) as JSON.
local json = require("release_exporter.vendor.json")
local model = require("release_exporter.model")

local M = {}

M.EXT = "ReleaseExporter"
M.SCHEMA_VERSION = "1"

local function decode(s)
  if s == nil or s == "" then return nil end
  local ok, value = pcall(json.decode, s)
  if ok and type(value) == "table" then return value end
end

-- Keeps only known keys whose type matches the default, so bad data degrades field by field.
local function merge(defaults, data)
  local out = {}
  for key, default in pairs(defaults) do
    local value = data and data[key]
    if value ~= nil and type(value) == type(default) then out[key] = value else out[key] = default end
  end
  return out
end

-- Values that passed the type check but are not a known choice would crash later (unknown format, blank pattern).
local function sanitize_settings(settings)
  local defaults = model.default_settings()
  if not model.PRIMARY_CHOICES[settings.primary] then settings.primary = defaults.primary end
  if not model.SECONDARY_CHOICES[settings.secondary] then settings.secondary = defaults.secondary end
  if not model.SAMPLE_RATE_CHOICES[settings.srate] then settings.srate = defaults.srate end
  if model.blank(settings.pattern) then settings.pattern = defaults.pattern end
  return settings
end

function M.load(r, proj)
  local _, ep = r.GetProjExtState(proj, M.EXT, "ep")
  local _, settings = r.GetProjExtState(proj, M.EXT, "settings")

  local loaded_settings
  local project_settings = decode(settings)
  if project_settings then
    loaded_settings = merge(model.default_settings(), project_settings)
  else
    loaded_settings = merge(model.default_settings(), decode(r.GetExtState(M.EXT, "default_settings")))
    loaded_settings.output_dir = ""
  end

  sanitize_settings(loaded_settings)

  local tracks = {}
  local idx = 0
  while true do
    local ok, key, value = r.EnumProjExtState(proj, M.EXT, idx)
    if not ok then break end
    if key:lower():sub(1, 6) == "track:" then
      tracks[key:sub(7):upper()] = merge(model.default_track(), decode(value))
    end
    idx = idx + 1
  end

  return { ep = merge(model.new_ep(), decode(ep)), settings = loaded_settings, tracks = tracks }
end

local function save(r, proj, key, value)
  r.SetProjExtState(proj, M.EXT, "schema_version", M.SCHEMA_VERSION)
  r.SetProjExtState(proj, M.EXT, key, json.encode(value))
  r.MarkProjectDirty(proj)
end

function M.save_ep(r, proj, ep)
  save(r, proj, "ep", ep)
end

function M.save_track(r, proj, guid, data)
  save(r, proj, "track:" .. guid, data)
end

function M.save_settings(r, proj, settings)
  save(r, proj, "settings", settings)
  r.SetExtState(M.EXT, "default_settings", json.encode(settings), true)
end

return M
