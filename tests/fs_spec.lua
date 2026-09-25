local fake = require("tests.support.fake_reaper")
local fs = require("release_exporter.fs")

describe("fs.ensure_dir", function()
  it("creates nested folders and reports them writable", function()
    local base = os.tmpname()
    os.remove(base)
    local dir = base .. "/a/b"
    assert.is_true(fs.ensure_dir(fake.new(), dir))
    assert.is_false(fs.exists(dir .. "/.release_exporter_probe"))
  end)

  it("returns false when the folder cannot be created", function()
    assert.is_false(fs.ensure_dir(fake.new(), "/dev/null/nope"))
  end)
end)
