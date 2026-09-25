local widgets = require("release_exporter.ui.widgets")

-- Minimal ImGui stand-in: `frame.typed` simulates a keystroke, `frame.deactivated` the end of editing.
local frame = {}
local ImGui = {
  Col_FrameBg = 1,
  SetNextItemWidth = function() end,
  PushStyleColor = function() end,
  PopStyleColor = function() end,
  SetItemTooltip = function() end,
  InputTextWithHint = function(_, _, _, buffer)
    if frame.typed then return true, frame.typed end
    return false, buffer
  end,
  IsItemDeactivated = function() return frame.deactivated == true end,
}

local function draw(value)
  return widgets.text_field(ImGui, {}, "##artist", value)
end

describe("widgets.text_field", function()
  before_each(function()
    widgets.reset()
    frame = {}
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
