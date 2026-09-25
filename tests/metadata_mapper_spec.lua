local mapper = require("release_exporter.metadata_mapper")

local function track(overrides)
  local t = {
    title = "Intro", artist = "Clem", album_artist = "Clem", album = "Nuits", year = "2026", genre = "Electro",
    label = "Indie", copyright = "(P) 2026 Clem", cover = "/art/cover.jpg", isrc = "FRXXX2600001",
    composer = "C. D.", number = 1, total = 4,
  }
  for k, v in pairs(overrides or {}) do t[k] = v end
  return t
end

local function as_set(list)
  local set = {}
  for _, entry in ipairs(list) do set[entry] = true end
  return set
end

local function has_prefix(list, prefix)
  for _, entry in ipairs(list) do
    if entry:sub(1, #prefix) == prefix then return true end
  end
  return false
end

describe("metadata_mapper.build", function()
  it("writes every scheme for a complete track", function()
    local set = as_set(mapper.build(track()))
    for _, expected in ipairs({
      "ID3:TIT2|Intro", "VORBIS:TITLE|Intro", "INFO:INAM|Intro",
      "ID3:TPE1|Clem", "ID3:TPE2|Clem", "ID3:TALB|Nuits", "VORBIS:ALBUM|Nuits",
      "ID3:TRCK|1/4", "VORBIS:TRACKNUMBER|1", "VORBIS:TRACKTOTAL|4", "INFO:ITRK|1",
      "ID3:TSRC|FRXXX2600001", "VORBIS:ISRC|FRXXX2600001", "VORBIS:ORGANIZATION|Indie",
      "ID3:TCOM|C. D.", "ID3:APIC_TYPE|3",
    }) do
      assert.is_true(set[expected] == true, expected)
    end
  end)

  it("uses every configured cover key", function()
    local set = as_set(mapper.build(track()))
    for _, key in ipairs(mapper.COVER_KEYS) do
      assert.is_true(set[key .. "|/art/cover.jpg"] == true, key)
    end
  end)

  it("skips empty values", function()
    local list = mapper.build(track({ isrc = "", composer = "", cover = "" }))
    assert.is_false(has_prefix(list, "ID3:TSRC"))
    assert.is_false(has_prefix(list, "ID3:TCOM"))
    assert.is_false(has_prefix(list, "ID3:APIC"))
  end)

  it("keeps values containing separators intact", function()
    assert.is_true(as_set(mapper.build(track({ title = "A|B; C" })))["ID3:TIT2|A|B; C"])
  end)
end)
