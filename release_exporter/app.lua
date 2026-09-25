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
  local self = setmetatable({ r = r, change_count = -1 }, App)
  self:refresh(true)
  return self
end

function App:refresh(force)
  local proj, projfn = self.r.EnumProjects(-1)
  local count = self.r.GetProjectStateChangeCount(proj)
  local switched = proj ~= self.proj
  if not force and not switched and count == self.change_count then return false end
  if force or switched then
    local data = store.load(self.r, proj)
    self.ep, self.tracks, self.settings = data.ep, data.tracks, data.settings
  end
  self.proj, self.projfn, self.change_count = proj, projfn or "", count
  self:rebuild()
  return true
end

function App:rebuild()
  self.rows = model.build_rows(regions.list(self.r, self.proj), self.tracks)
  self.validation = model.validate(self.ep, self.rows, self.settings, self:output_dir(),
    { file_exists = self.r.file_exists })
end

function App:project_dir()
  return self.projfn:match("^(.*)[/\\][^/\\]*$") or ""
end

function App:output_dir()
  if not model.blank(self.settings.output_dir) then return self.settings.output_dir end
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

function App:can_export()
  return #self.validation.errors == 0
end

function App:export()
  local dir = self:output_dir()
  local report
  if fs.ensure_dir(self.r, dir) then
    report = renderer.render(self.r, self.proj, self:jobs(), {
      output_dir = dir,
      primary_format = formats.primary(self.settings.primary),
      secondary_format = formats.secondary(self.settings.secondary),
      srate = self.settings.srate,
    })
  else
    report = { items = {}, error = "Cannot create or write to " .. dir }
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
