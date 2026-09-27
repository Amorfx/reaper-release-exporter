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

describe("fs.choose_image", function()
  it("offers JPEG and PNG files when js_ReaScriptAPI is installed", function()
    local r, filter = fake.new(), nil
    r.JS_Dialog_BrowseForOpenFiles = function(_, _, _, extensions)
      filter = extensions
      return 1, "/art/cover.png"
    end
    assert.are.equal("/art/cover.png", fs.choose_image(r, "Choose cover image"))
    assert.is_truthy(filter:find("*.png", 1, true))
    assert.is_truthy(filter:find("*.jpg", 1, true))
  end)

  it("returns nil when the dialog is cancelled", function()
    local r = fake.new()
    r.JS_Dialog_BrowseForOpenFiles = function() return 0, "" end
    assert.is_nil(fs.choose_image(r, "Choose cover image"))
  end)

  it("falls back to REAPER's dialog without an extension filter", function()
    local r, ext = fake.new(), nil
    r.GetUserFileNameForRead = function(_, _, defext)
      ext = defext
      return true, "/art/cover.png"
    end
    assert.are.equal("/art/cover.png", fs.choose_image(r, "Choose cover image"))
    assert.are.equal("", ext)
  end)
end)
