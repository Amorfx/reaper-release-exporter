local fake = require("tests.support.fake_reaper")
local App = require("release_exporter.app")
local fs = require("release_exporter.fs")

local function setup()
  local r = fake.new()
  r.add_region(0, 10, "Intro")
  r.add_region(10, 20, "Minuit")
  return r, App.new(r)
end

local function fill_ep(app)
  app:set_ep_field("artist", "Clem")
  app:set_ep_field("album", "Nuits")
  app:set_ep_field("year", "2026")
end

describe("app", function()
  -- The folder check touches the real disk, and these projects live at made-up paths.
  local writable
  before_each(function()
    writable = true
    stub(fs, "can_create_dir", function() return writable end)
  end)
  after_each(function() fs.can_create_dir:revert() end)

  it("blocks the export when the output folder cannot be created", function()
    writable = false
    local _, app = setup()
    fill_ep(app)
    assert.is_false(app:can_export())
    assert.is_truthy(app.validation.errors[1].message:find("cannot be created", 1, true))
  end)

  it("checks the output folder once per path", function()
    local _, app = setup()
    fill_ep(app) -- the release title is part of the default folder, so this checks a new path
    local calls = #fs.can_create_dir.calls
    app:set_track_field(app.rows[1].guid, "composer", "Clem")
    assert.are.equal(calls, #fs.can_create_dir.calls)
    app:set_setting("output_dir", "/elsewhere")
    assert.are.equal(calls + 1, #fs.can_create_dir.calls)
  end)

  it("builds rows from the project's regions", function()
    local _, app = setup()
    assert.are.equal(2, #app.rows)
    assert.are.equal("Intro", app.rows[1].title)
    assert.are.equal(2, app.rows[2].number)
  end)

  it("renames the region when a title is edited", function()
    local r, app = setup()
    app:set_track_field(app.rows[1].guid, "title", "Aube")
    assert.are.equal("Aube", r.markers()[1].name)
    assert.are.equal("Aube", app.rows[1].title)
    assert.are.equal(1, #r.undo_points)
  end)

  it("stores other fields by GUID, normalizes ISRC and persists them", function()
    local r, app = setup()
    local guid = app.rows[2].guid
    app:set_track_field(guid, "isrc", "fr-xxx-26-00002")
    app:set_track_field(guid, "include", false)
    local reloaded = App.new(r)
    assert.are.equal("FRXXX2600002", reloaded.rows[2].isrc)
    assert.is_false(reloaded.rows[2].include)
    assert.are.equal(0, #r.undo_points)
  end)

  it("keeps metadata of a deleted region and gets it back when the region is restored", function()
    local r, app = setup()
    local guid = app.rows[1].guid
    app:set_track_field(guid, "isrc", "FRXXX2600001")
    local removed = r.remove_region(guid)
    app:refresh()
    assert.are.equal(1, #app.rows)
    r.restore_marker(removed)
    app:refresh()
    assert.are.equal("FRXXX2600001", app.rows[1].isrc)
  end)

  it("only rebuilds when the project changed", function()
    local r, app = setup()
    assert.is_false(app:refresh())
    r.add_region(20, 30, "Aube")
    assert.is_true(app:refresh())
    assert.are.equal(3, #app.rows)
  end)

  it("reloads everything when the active project changes", function()
    local r, app = setup()
    fill_ep(app)
    r.switch_project()
    app:refresh()
    assert.are.equal("", app.ep.artist)
    assert.are.equal(0, #app.rows)
  end)

  it("defaults the output folder next to the project", function()
    local _, app = setup()
    fill_ep(app)
    assert.are.equal("/music/ep/Exports/Nuits", app:output_dir())
    app:set_setting("output_dir", "/custom")
    assert.are.equal("/custom", app:output_dir())
  end)

  it("blocks export for an unsaved project without output folder", function()
    local r = fake.new()
    r.projfn = ""
    r.add_region(0, 10, "Intro")
    local app = App.new(r)
    fill_ep(app)
    assert.are.equal("", app:output_dir())
    assert.is_false(app:can_export())
    assert.are.equal("settings.output_dir", app.validation.errors[1].field)
  end)

  it("drops a missing cover from the tags", function()
    local _, app = setup()
    fill_ep(app)
    app:set_ep_field("cover", "/nope/cover.jpg")
    for _, tag in ipairs(app:jobs()[1].tags) do
      assert.is_nil(tag:find("APIC", 1, true))
    end
  end)

  it("exports every included song and keeps the report", function()
    local base = os.tmpname()
    os.remove(base)
    local r = fake.new()
    r.projfn = base .. "/EP.rpp"
    r.add_region(0, 10, "Intro")
    r.add_region(10, 20, "Minuit")
    local app = App.new(r)
    fill_ep(app)
    local report = app:export()
    assert.is_nil(report.error)
    assert.are.equal(2, #report.items)
    assert.is_true(report.items[2].ok)
    assert.is_true(fs.exists(base .. "/Exports/Nuits/02 - Minuit.mp3"))
    assert.are.equal(report, app.last_report)
    assert.are.equal(4, #app:existing_files())
  end)

  it("creates regions from selected items", function()
    local r = fake.new()
    local app = App.new(r)
    r.selected_items = { { pos = 0, len = 5, take = { name = "Song A.wav" } } }
    assert.are.equal(1, app:create_regions_from_items())
    assert.are.equal("Song A", app.rows[1].title)
  end)
  it("reloads when another project is opened in the same tab", function()
    local r, app = setup()
    fill_ep(app)
    r.SetProjExtState(r.proj, "ReleaseExporter", "", "") -- REAPER swaps the project state, keeps the pointer
    r.projfn = "/music/ep2/EP2.rpp"
    app:refresh()
    assert.are.equal("", app.ep.artist)
  end)

  it("reloads when the same file is reopened in the same tab (File > Revert)", function()
    local r, app = setup()
    fill_ep(app)
    local generation = app.generation
    -- Same pointer, same path: only the project state changes.
    r.SetProjExtState(r.proj, "ReleaseExporter", "ep", '{"artist":"Saved","album":"Nuits","year":"2026"}')
    r.change_count = r.change_count + 1
    app:refresh()
    assert.are.equal("Saved", app.ep.artist)
    assert.is_true(app.generation > generation)
  end)

  it("keeps open drafts when a change only echoes its own edits", function()
    local r, app = setup()
    fill_ep(app)
    local generation = app.generation
    r.change_count = r.change_count + 1
    app:refresh()
    assert.are.equal(generation, app.generation)
  end)

  it("hides issues until the project has songs, so a new project does not open in red", function()
    local r = fake.new()
    local app = App.new(r)
    assert.is_false(app:shows_issues())
    assert.is_false(app:can_export())
    r.add_region(0, 10, "Intro")
    app:refresh(true)
    assert.is_true(app:shows_issues())
  end)

  it("expands ~ in the output folder", function()
    local _, app = setup()
    app:set_setting("output_dir", "~/Music/EP")
    assert.are.equal(os.getenv("HOME") .. "/Music/EP", app:output_dir())
  end)

  it("follows the new path after Save As", function()
    local r, app = setup()
    fill_ep(app)
    r.projfn = "/new/place/EP.rpp"
    app:refresh()
    assert.are.equal("Clem", app.ep.artist)
    assert.are.equal("/new/place/Exports/Nuits", app:output_dir())
  end)

  it("clears the unsaved-project error once the project is saved", function()
    local r = fake.new()
    r.projfn = ""
    r.add_region(0, 10, "Intro")
    local app = App.new(r)
    fill_ep(app)
    assert.is_false(app:can_export())
    r.projfn = "/music/ep/EP.rpp"
    app:refresh()
    assert.is_true(app:can_export())
  end)

  it("bumps the generation only when the project is reloaded", function()
    local r, app = setup()
    local generation = app.generation
    r.add_region(20, 30, "Aube")
    app:refresh()
    assert.are.equal(generation, app.generation)
    r.switch_project()
    app:refresh()
    assert.are_not.equal(generation, app.generation)
  end)

  it("refuses to export when the active project changed since confirmation", function()
    local r, app = setup()
    fill_ep(app)
    r.switch_project()
    local report = app:export()
    assert.is_truthy(report.error:find("active project", 1, true))
    assert.are.equal(0, #r.commands)
  end)

  it("re-validates right before exporting", function()
    local r, app = setup()
    fill_ep(app)
    r.remove_region(app.rows[1].guid)
    r.remove_region(app.rows[2].guid)
    local report = app:export()
    assert.are.equal("No region is included in the export.", report.error)
    assert.are.equal(0, #r.commands)
  end)

  it("asks before continuing when a song was not rendered", function()
    local base = os.tmpname()
    os.remove(base)
    local r = fake.new()
    r.projfn = base .. "/EP.rpp"
    r.add_region(0, 10, "Intro")
    r.add_region(10, 20, "Minuit")
    local app = App.new(r)
    fill_ep(app)
    r.render_behavior = "missing"
    r.message_box_answer = 7
    local report = app:export()
    assert.are.equal(1, #r.commands)
    assert.are.equal(1, #r.message_boxes)
    assert.is_true(report.items[2].skipped)
  end)
end)
