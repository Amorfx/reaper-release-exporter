local tracks_table = require("release_exporter.ui.tracks_table")
local export_bar = require("release_exporter.ui.export_bar")

describe("tracks_table.summary", function()
  it("counts the included songs and adds up their length", function()
    local rows = {
      { include = true, duration = 72 },
      { include = true, duration = 245.4 },
      { include = false, duration = 253 },
      { include = true, duration = 302 },
    }
    assert.are.equal("3 of 4 included · 10:19", tracks_table.summary(rows))
  end)
end)

describe("export_bar.export_label", function()
  it("agrees with the number of songs", function()
    assert.are.equal("Export", export_bar.export_label(0))
    assert.are.equal("Export 1 song", export_bar.export_label(1))
    assert.are.equal("Export 3 songs", export_bar.export_label(3))
  end)
end)
