local model = require("release_exporter.model")

local function region(guid, start, stop, name)
  return { guid = guid, start = start, stop = stop, name = name }
end

local function make_ep(overrides)
  local ep = model.new_ep()
  ep.artist, ep.album, ep.year, ep.cover = "Clem", "Nuits", "2026", "/art/cover.jpg"
  for k, v in pairs(overrides or {}) do ep[k] = v end
  return ep
end

-- specs: array of { guid, title, isrc, include }
local function make_rows(specs)
  local regions, data = {}, {}
  for i, s in ipairs(specs) do
    regions[i] = region(s[1], i * 10, i * 10 + 5, s[2])
    data[s[1]] = { include = s[4] ~= false, artist = "", isrc = s[3] or "", composer = "" }
  end
  return model.build_rows(regions, data)
end

local always = function() return true end

describe("model.build_rows", function()
  it("sorts by position and numbers only included rows", function()
    local rows = model.build_rows(
      { region("{B}", 10, 20, "Second"), region("{A}", 0, 10, "First"), region("{C}", 20, 30, "Draft") },
      { ["{C}"] = { include = false } })
    assert.are.same({ "First", "Second", "Draft" }, { rows[1].title, rows[2].title, rows[3].title })
    assert.are.equal(1, rows[1].number)
    assert.are.equal(2, rows[1].total)
    assert.are.equal(2, rows[2].number)
    assert.is_nil(rows[3].number)
  end)

  it("fills missing track data with defaults", function()
    local rows = model.build_rows({ region("{A}", 0, 5, "Intro") }, {})
    assert.is_true(rows[1].include)
    assert.are.equal("", rows[1].isrc)
    assert.are.equal(5, rows[1].duration)
  end)

  it("keeps metadata attached to the GUID when regions are reordered", function()
    local data = { ["{A}"] = { include = true, isrc = "FRXXX2600001", artist = "", composer = "" } }
    local rows = model.build_rows({ region("{B}", 0, 5, "Now first"), region("{A}", 5, 9, "Now second") }, data)
    assert.are.equal("", rows[1].isrc)
    assert.are.equal("FRXXX2600001", rows[2].isrc)
    assert.are.equal(2, rows[2].number)
  end)
end)

describe("model.resolve", function()
  it("falls back to the EP artist for track and album artist", function()
    local t = model.resolve(make_ep(), { title = "Intro", artist = "", isrc = "", composer = "", number = 1, total = 3 })
    assert.are.equal("Clem", t.artist)
    assert.are.equal("Clem", t.album_artist)
  end)

  it("keeps a per-track artist, trims the title and normalizes the ISRC", function()
    local t = model.resolve(make_ep(),
      { title = " Minuit ", artist = "Clem feat. Lea", isrc = "fr-xxx-26-00002", composer = "", number = 2, total = 3 })
    assert.are.equal("Minuit", t.title)
    assert.are.equal("Clem feat. Lea", t.artist)
    assert.are.equal("FRXXX2600002", t.isrc)
  end)
end)

describe("model validators", function()
  it("accepts well-formed ISRC codes only", function()
    assert.is_true(model.is_valid_isrc("FRXXX2600001"))
    assert.is_false(model.is_valid_isrc("FRXX2600001"))
    assert.is_false(model.is_valid_isrc("FRXXX26A0001"))
    assert.is_false(model.is_valid_isrc("12XXX2600001"))
  end)

  it("accepts YYYY and YYYY-MM-DD years", function()
    assert.is_true(model.is_valid_year("2026"))
    assert.is_true(model.is_valid_year("2026-09-25"))
    assert.is_false(model.is_valid_year("26"))
    assert.is_false(model.is_valid_year(""))
    assert.is_false(model.is_valid_year("2026/09/25"))
  end)
end)

describe("model file names", function()
  it("replaces characters that are illegal or special for REAPER", function()
    assert.are.equal("AC-DC- Live-", model.sanitize_filename("AC/DC: Live?"))
    assert.are.equal("Ca-h", model.sanitize_filename("Ca$h"))
    assert.are.equal("a-b", model.sanitize_filename("a;b"))
    assert.are.equal("Outro", model.sanitize_filename("  Outro. "))
    assert.are.equal("untitled", model.sanitize_filename("   "))
  end)

  it("expands known tokens and leaves unknown ones", function()
    local name = model.format_filename("{nn} - {artist} - {title} ({year}) {unknown}",
      { number = 3, title = "Néons", artist = "Clem", album = "Nuits", year = "2026" })
    assert.are.equal("03 - Clem - Néons (2026) {unknown}", name)
  end)

  it("builds the default output folder next to the project", function()
    assert.are.equal("/music/ep/Exports/Nuits- Blanches", model.default_output_dir("/music/ep", "Nuits: Blanches"))
    assert.are.equal("/music/ep/Exports/EP", model.default_output_dir("/music/ep", ""))
    assert.are.equal("", model.default_output_dir("", "Nuits"))
  end)
end)

describe("model.plan_outputs", function()
  it("lists primary and secondary files for included rows only", function()
    local jobs = model.plan_outputs(make_ep(), make_rows({ { "{A}", "Intro" }, { "{B}", "Skip", "", false } }),
      model.default_settings(), "/out")
    assert.are.equal(1, #jobs)
    assert.are.equal("01 - Intro", jobs[1].basename)
    assert.are.same({ "/out/01 - Intro.wav", "/out/01 - Intro.mp3" }, jobs[1].files)
  end)

  it("omits the secondary file when disabled", function()
    local settings = model.default_settings()
    settings.secondary = "none"
    local jobs = model.plan_outputs(make_ep(), make_rows({ { "{A}", "Intro" } }), settings, "/out")
    assert.are.same({ "/out/01 - Intro.wav" }, jobs[1].files)
  end)
end)

describe("model.validate", function()
  local settings = model.default_settings()

  it("passes a complete EP", function()
    local v = model.validate(make_ep(), make_rows({ { "{A}", "Intro", "FRXXX2600001" } }), settings, "/out",
      { file_exists = always })
    assert.are.same({}, v.errors)
    assert.are.same({}, v.warnings)
  end)

  it("blocks an unsaved project without output folder", function()
    local v = model.validate(make_ep(), make_rows({ { "{A}", "Intro", "FRXXX2600001" } }), settings, "",
      { file_exists = always })
    assert.are.equal(1, #v.errors)
    assert.are.equal("settings.output_dir", v.errors[1].field)
  end)

  it("reports missing EP fields, bad ISRC and empty titles", function()
    local v = model.validate(make_ep({ artist = "", year = "26" }), make_rows({ { "{A}", "", "BAD" } }), settings,
      "/out", { file_exists = always })
    local keys = {}
    for _, e in ipairs(v.errors) do keys[#keys + 1] = (e.guid or "") .. e.field end
    table.sort(keys)
    assert.are.same({ "ep.artist", "ep.year", "{A}isrc", "{A}title" }, keys)
  end)

  it("ignores excluded rows and blocks when nothing is included", function()
    local v = model.validate(make_ep(), make_rows({ { "{A}", "", "BAD", false } }), settings, "/out",
      { file_exists = always })
    assert.are.equal(1, #v.errors)
    assert.are.equal("rows", v.errors[1].field)
  end)

  it("detects duplicate file names case-insensitively", function()
    local s = model.default_settings()
    s.pattern = "{title}"
    local v = model.validate(make_ep(),
      make_rows({ { "{A}", "Intro", "FRXXX2600001" }, { "{B}", "INTRO", "FRXXX2600002" } }), s, "/out",
      { file_exists = always })
    assert.are.equal(1, #v.errors)
    assert.are.equal("{B}", v.errors[1].guid)
  end)

  it("warns about a missing ISRC and a missing cover file without blocking", function()
    local v = model.validate(make_ep({ cover = "/missing.jpg" }), make_rows({ { "{A}", "Intro", "" } }), settings,
      "/out", { file_exists = function() return false end })
    assert.are.same({}, v.errors)
    assert.are.equal(2, #v.warnings)
  end)

  it("finds the issue for a given row and field", function()
    local v = model.validate(make_ep(), make_rows({ { "{A}", "Intro", "BAD" } }), settings, "/out",
      { file_exists = always })
    assert.is_truthy(model.issue_for(v.errors, "{A}", "isrc"))
    assert.is_nil(model.issue_for(v.errors, "{A}", "title"))
  end)
end)
