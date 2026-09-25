local fake = require("tests.support.fake_reaper")
local regions = require("release_exporter.regions")

describe("regions.list", function()
  it("returns regions with GUIDs in position order and skips markers", function()
    local r = fake.new()
    r.add_region(10, 20, "B")
    r.add_region(0, 10, "A")
    r.add_marker(5, "cue")
    local list = regions.list(r, r.proj)
    assert.are.equal(2, #list)
    assert.are.same({ "A", "B" }, { list[1].name, list[2].name })
    assert.is_truthy(list[1].guid:match("^{.+}$"))
  end)
end)

describe("regions.rename", function()
  it("renames by GUID with a single undo point", function()
    local r = fake.new()
    r.add_region(0, 10, "Old")
    local guid = regions.list(r, r.proj)[1].guid
    assert.is_true(regions.rename(r, r.proj, guid, "New"))
    assert.are.equal("New", r.markers()[1].name)
    assert.are.equal(1, #r.undo_points)
  end)

  it("can clear a name", function()
    local r = fake.new()
    r.add_region(0, 10, "Old")
    regions.rename(r, r.proj, regions.list(r, r.proj)[1].guid, "")
    assert.are.equal("", r.markers()[1].name)
  end)

  it("returns false for an unknown GUID", function()
    local r = fake.new()
    assert.is_false(regions.rename(r, r.proj, "{nope}", "X"))
    assert.are.equal(0, #r.undo_points)
  end)
end)

describe("regions.create_from_selected_items", function()
  it("creates one region per item, named after the take without extension", function()
    local r = fake.new()
    r.selected_items = {
      { pos = 0, len = 180, take = { name = "Intro.wav" } },
      { pos = 190, len = 200, take = { name = "Minuit.rpp" } },
      { pos = 400, len = 10 },
    }
    assert.are.equal(3, regions.create_from_selected_items(r, r.proj))
    local list = regions.list(r, r.proj)
    assert.are.same({ "Intro", "Minuit", "" }, { list[1].name, list[2].name, list[3].name })
    assert.are.equal(390, list[2].stop)
    assert.are.equal(1, #r.undo_points)
  end)

  it("does nothing without a selection", function()
    local r = fake.new()
    assert.are.equal(0, regions.create_from_selected_items(r, r.proj))
    assert.are.equal(0, #r.undo_points)
  end)
end)
