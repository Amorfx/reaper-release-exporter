local json = require("release_exporter.vendor.json")

describe("vendored json", function()
  it("round-trips a table with strings, booleans and numbers", function()
    local value = { artist = "Clém", include = false, srate = 48000 }
    assert.are.same(value, json.decode(json.encode(value)))
  end)

  it("raises on invalid input", function()
    assert.has_error(function() json.decode("{not json") end)
  end)
end)
