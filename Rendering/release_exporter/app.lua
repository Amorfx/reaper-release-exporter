-- @noindex
-- Controller between the ReaImGui views and the model/adapters. Holds the state of the active project.
local model = require("release_exporter.model")
local mapper = require("release_exporter.metadata_mapper")
local formats = require("release_exporter.formats")
local regions = require("release_exporter.regions")
local store = require("release_exporter.project_store")
local renderer = require("release_exporter.renderer")
local fs = require("release_exporter.fs")

local App = {}
App.__index = App

function App.new(r)
  local self = setmetatable({ r = r, change_count = -1, generation = 0 }, App)
  self:refresh(true)
  return self
end

-- Deep equality for the plain tables loaded from the project.
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function App:refresh(force)
  local proj, projfn = self.r.EnumProjects(-1)
  local count = self.r.GetProjectStateChangeCount(proj)
  -- REAPER keeps the same ReaProject pointer when a project is opened in the current tab, so the path counts too.
  -- A Save As only changes the path; reloading is harmless because every edit is already stored.
  local switched = proj ~= self.proj or (projfn or "") ~= self.projfn
  if not force and not switched and count == self.change_count then return false end
  -- Reopening the same file in the same tab (File > Revert) keeps both the pointer and the path, so the stored
  -- data is re-read on every state change. Only a real difference drops the open drafts.
  local data = store.load(self.r, proj)
  if force or switched or not same(data, { ep = self.ep, tracks = self.tracks, settings = self.settings }) then
    self.ep, self.tracks, self.settings = data.ep, data.tracks, data.settings
    self.generation = self.generation + 1
  end
  self.proj, self.projfn, self.change_count = proj, projfn or "", count
  self:rebuild()
  return true
end

function App:rebuild()
  self.rows = model.build_rows(regions.list(self.r, self.proj), self.tracks)
  self.validation = model.validate(self.ep, self.rows, self.settings, self:output_dir(),
    { file_exists = self.r.file_exists, folder_writable = function(dir) return self:folder_writable(dir) end })
end

-- Cached per path: the check touches the disk, and rebuild runs on every change.
function App:folder_writable(dir)
  if self.folder_check and self.folder_check.dir == dir then return self.folder_check.ok end
  local ok = fs.can_create_dir(dir)
  self.folder_check = { dir = dir, ok = ok }
  return ok
end

function App:project_dir()
  return self.projfn:match("^(.*)[/\\][^/\\]*$") or ""
end

function App:output_dir()
  if not model.blank(self.settings.output_dir) then
    return model.expand_home(self.settings.output_dir, os.getenv("HOME") or os.getenv("USERPROFILE"))
  end
  return model.default_output_dir(self:project_dir(), self.ep.album)
end

function App:set_ep_field(field, value)
  self.ep[field] = value
  store.save_ep(self.r, self.proj, self.ep)
  self:rebuild()
end

function App:set_track_field(guid, field, value)
  if field == "title" then
    regions.rename(self.r, self.proj, guid, value)
  else
    if field == "isrc" then value = model.normalize_isrc(value) end
    local data = self.tracks[guid] or model.default_track()
    data[field] = value
    self.tracks[guid] = data
    store.save_track(self.r, self.proj, guid, data)
  end
  self:rebuild()
end

function App:set_setting(field, value)
  self.settings[field] = value
  store.save_settings(self.r, self.proj, self.settings)
  self:rebuild()
end

function App:jobs()
  local ep = self.ep
  if not model.blank(ep.cover) and not self.r.file_exists(ep.cover) then
    ep = {}
    for k, v in pairs(self.ep) do ep[k] = v end
    ep.cover = ""
  end
  local jobs = model.plan_outputs(ep, self.rows, self.settings, self:output_dir())
  for _, job in ipairs(jobs) do job.tags = mapper.build(job.resolved) end
  return jobs
end

function App:existing_files()
  local out = {}
  for _, job in ipairs(self:jobs()) do
    for _, path in ipairs(job.files) do
      if fs.exists(path) then out[#out + 1] = path end
    end
  end
  return out
end

-- A project without songs only shows how to create them: pointing at empty required fields
-- before there is anything to export would greet a new project in red.
function App:shows_issues()
  return #self.rows > 0
end

function App:can_export()
  return #self.validation.errors == 0
end

function App:confirm_continue(item)
  local message = ('"%s" was not rendered (cancelled or failed).\n\nContinue with the remaining songs?'):format(item.title)
  return self.r.ShowMessageBox(message, "Release Exporter", 4) == 6
end

function App:export()
  local report
  local proj, projfn = self.r.EnumProjects(-1)
  -- REAPER renders the active project, so it must still be the one the user confirmed.
  if proj ~= self.proj or (projfn or "") ~= self.projfn then
    report = { items = {}, error = "The active project changed; review it and export again." }
  else
    self:refresh()
    if not self:can_export() then
      report = { items = {}, error = self.validation.errors[1].message }
    end
  end
  local dir = self:output_dir()
  if not report then
    if fs.ensure_dir(self.r, dir) then
      report = renderer.render(self.r, self.proj, self:jobs(), {
        output_dir = dir,
        primary_format = formats.primary(self.settings.primary),
        secondary_format = formats.secondary(self.settings.secondary),
        srate = self.settings.srate,
        on_failure = function(item) return self:confirm_continue(item) end,
      })
    else
      report = { items = {}, error = "Cannot create or write to " .. dir }
    end
  end
  report.output_dir = dir
  self.last_report = report
  return report
end

function App:create_regions_from_items()
  local count = regions.create_from_selected_items(self.r, self.proj)
  self:refresh()
  return count
end

return App
