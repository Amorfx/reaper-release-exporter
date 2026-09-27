-- @noindex
-- Pure data model: EP and track fields, fallbacks, numbering, validation and file names.
-- Must never reference the `reaper` API so it stays testable outside REAPER.
local M = {}

M.FORMAT_EXT = { wav16 = "wav", wav24 = "wav", mp3_320 = "mp3", flac = "flac" }
M.FORMAT_LABELS = { wav24 = "WAV 24-bit", wav16 = "WAV 16-bit", mp3_320 = "MP3 320 kbps", flac = "FLAC", none = "None" }
M.PRIMARY_CHOICES = { wav24 = true, wav16 = true }
M.SECONDARY_CHOICES = { mp3_320 = true, flac = true, none = true }
M.SAMPLE_RATE_CHOICES = { [0] = true, [44100] = true, [48000] = true }

function M.new_ep()
  return { artist = "", album_artist = "", album = "", year = "", genre = "", label = "", copyright = "", cover = "" }
end

function M.default_track()
  return { include = true, artist = "", isrc = "", composer = "" }
end

function M.default_settings()
  return { output_dir = "", pattern = "{nn} - {title}", primary = "wav24", secondary = "mp3_320", srate = 0 }
end

function M.blank(s)
  return s == nil or s:match("^%s*$") ~= nil
end

local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

function M.build_rows(regions, track_data)
  local rows = {}
  for _, rgn in ipairs(regions) do
    local data = track_data[rgn.guid] or {}
    local row = { guid = rgn.guid, title = rgn.name, start = rgn.start, stop = rgn.stop, duration = rgn.stop - rgn.start }
    for key, default in pairs(M.default_track()) do
      if data[key] == nil then row[key] = default else row[key] = data[key] end
    end
    rows[#rows + 1] = row
  end
  table.sort(rows, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.guid < b.guid
  end)
  local total = 0
  for _, row in ipairs(rows) do
    if row.include then total = total + 1 end
  end
  local n = 0
  for _, row in ipairs(rows) do
    if row.include then
      n = n + 1
      row.number, row.total = n, total
    end
  end
  return rows
end

function M.normalize_isrc(s)
  return ((s or ""):upper():gsub("[%s%-]", ""))
end

function M.is_valid_isrc(s)
  return s:match("^%u%u[%u%d][%u%d][%u%d]%d%d%d%d%d%d%d$") ~= nil
end

function M.is_valid_year(s)
  return s:match("^%d%d%d%d$") ~= nil or s:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

function M.resolve(ep, row)
  local artist = trim(ep.artist)
  return {
    title = trim(row.title),
    artist = M.blank(row.artist) and artist or trim(row.artist),
    album_artist = M.blank(ep.album_artist) and artist or trim(ep.album_artist),
    album = trim(ep.album),
    year = trim(ep.year),
    genre = trim(ep.genre),
    label = trim(ep.label),
    copyright = trim(ep.copyright),
    cover = trim(ep.cover),
    isrc = M.normalize_isrc(row.isrc),
    composer = trim(row.composer),
    number = row.number,
    total = row.total,
  }
end

-- `$` would be read as a REAPER wildcard and `;` separates RENDER_TARGETS entries.
function M.sanitize_filename(name)
  local s = (name or ""):gsub('[/\\:%*%?"<>|%$;%c]', "-")
  s = s:gsub("^%s+", ""):gsub("[%s%.]+$", "")
  if s == "" then return "untitled" end
  return s
end

function M.format_filename(pattern, resolved)
  local values = {
    nn = string.format("%02d", resolved.number or 0),
    n = tostring(resolved.number or 0),
    title = resolved.title,
    artist = resolved.artist,
    album = resolved.album,
    year = resolved.year,
  }
  local name = pattern:gsub("{(%w+)}", function(key) return values[key] end)
  return M.sanitize_filename(name)
end

function M.default_output_dir(project_dir, album)
  if M.blank(project_dir) then return "" end
  local folder = M.blank(album) and "EP" or M.sanitize_filename(album)
  return project_dir .. "/Exports/" .. folder
end

function M.plan_outputs(ep, rows, settings, output_dir)
  local jobs = {}
  for _, row in ipairs(rows) do
    if row.include then
      local resolved = M.resolve(ep, row)
      local basename = M.format_filename(settings.pattern, resolved)
      local files = { output_dir .. "/" .. basename .. "." .. M.FORMAT_EXT[settings.primary] }
      local secondary_ext = M.FORMAT_EXT[settings.secondary]
      if secondary_ext then files[#files + 1] = output_dir .. "/" .. basename .. "." .. secondary_ext end
      jobs[#jobs + 1] = {
        guid = row.guid, title = resolved.title, start = row.start, stop = row.stop,
        resolved = resolved, basename = basename, files = files,
      }
    end
  end
  return jobs
end

function M.validate(ep, rows, settings, output_dir, opts)
  opts = opts or {}
  local errors, warnings = {}, {}
  local function err(field, message, guid) errors[#errors + 1] = { field = field, message = message, guid = guid } end
  local function warn(field, message, guid) warnings[#warnings + 1] = { field = field, message = message, guid = guid } end

  if M.blank(ep.artist) then err("ep.artist", "Artist is required.") end
  if M.blank(ep.album) then err("ep.album", "EP title is required.") end
  if not M.is_valid_year(trim(ep.year)) then err("ep.year", "Release date must be YYYY or YYYY-MM-DD.") end
  if M.blank(ep.cover) then
    warn("ep.cover", "No cover image.")
  elseif opts.file_exists and not opts.file_exists(trim(ep.cover)) then
    warn("ep.cover", "Cover image not found; it will be skipped.")
  end
  if M.blank(output_dir) then err("settings.output_dir", "Save the project or choose an output folder.") end

  local included = 0
  for _, row in ipairs(rows) do
    if row.include then
      included = included + 1
      if M.blank(row.title) then err("title", "Title is required.", row.guid) end
      local isrc = M.normalize_isrc(row.isrc)
      if isrc == "" then
        warn("isrc", "No ISRC.", row.guid)
      elseif not M.is_valid_isrc(isrc) then
        err("isrc", "ISRC must look like FRXXX2600001.", row.guid)
      end
    end
  end
  if included == 0 then err("rows", "No region is included in the export.") end

  local seen = {}
  for _, job in ipairs(M.plan_outputs(ep, rows, settings, output_dir)) do
    local key = job.basename:lower()
    if seen[key] then err("title", 'Duplicate file name "' .. job.basename .. '".', job.guid) end
    seen[key] = true
  end
  return { errors = errors, warnings = warnings }
end

function M.issue_for(issues, guid, field)
  for _, issue in ipairs(issues) do
    if issue.guid == guid and issue.field == field then return issue.message end
  end
end

return M
