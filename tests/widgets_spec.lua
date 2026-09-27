local widgets = require("release_exporter.ui.widgets")

-- Minimal ImGui stand-in: `frame.typed` simulates a keystroke, `frame.deactivated` the end of editing.
local frame = {}
local pushed = 0
local ImGui = {
  Col_FrameBg = 1,
  Col_Border = 2,
  Col_FrameBgHovered = 3,
  SetNextItemWidth = function() end,
  PushStyleColor = function() pushed = pushed + 1 end,
  PopStyleColor = function(_, count) pushed = pushed - (count or 1) end,
  SetItemTooltip = function() end,
  InputTextWithHint = function(_, _, _, buffer)
    if frame.typed then return true, frame.typed end
    return false, buffer
  end,
  IsItemDeactivated = function() return frame.deactivated == true end,
}

local function draw(value, opts)
  return widgets.text_field(ImGui, {}, "##artist", value, opts)
end

describe("widgets.text_field", function()
  before_each(function()
    widgets.reset()
    frame = {}
    pushed = 0
  end)

  it("restores the style stack for plain, ghost and invalid fields", function()
    for _, opts in ipairs({ {}, { ghost = true }, { error = "Bad ISRC" }, { ghost = true, error = "Bad ISRC" } }) do
      draw("", opts)
      assert.are.equal(0, pushed)
    end
  end)

  it("commits the draft only when editing ends", function()
    frame = { typed = "Clem" }
    assert.is_nil(draw(""))
    frame = { deactivated = true }
    assert.are.equal("Clem", draw(""))
  end)

  it("drops open drafts on reset so they never land in another project", function()
    frame = { typed = "Clem" }
    draw("")
    widgets.reset()
    frame = { deactivated = true }
    assert.is_nil(draw(""))
  end)
end)

describe("widgets.issue_chips", function()
  local function issues(n, prefix)
    local out = {}
    for i = 1, n do out[i] = { message = prefix .. i } end
    return out
  end

  it("lists errors before warnings", function()
    local chips = widgets.issue_chips(issues(1, "E"), issues(1, "W"), 4)
    assert.are.same({ { text = "E1", kind = "error" }, { text = "W1", kind = "warning" } }, chips.visible)
    assert.is_nil(chips.overflow)
  end)

  it("folds the extra issues into one chip whose tooltip lists them", function()
    local chips = widgets.issue_chips(issues(3, "E"), issues(3, "W"), 4)
    assert.are.equal(4, #chips.visible)
    assert.are.equal("+2 more", chips.overflow.text)
    assert.are.same({ "W2", "W3" }, chips.overflow.lines)
  end)
end)

describe("widgets.short_path", function()
  it("abbreviates the home folder", function()
    assert.are.equal("~/Music/EP", widgets.short_path("/Users/clem/Music/EP", "/Users/clem"))
  end)

  it("leaves other paths and look-alike prefixes untouched", function()
    assert.are.equal("/Volumes/EP", widgets.short_path("/Volumes/EP", "/Users/clem"))
    assert.are.equal("/Users/clement/EP", widgets.short_path("/Users/clement/EP", "/Users/clem"))
    assert.are.equal("/Users/clem/EP", widgets.short_path("/Users/clem/EP", nil))
  end)
end)
