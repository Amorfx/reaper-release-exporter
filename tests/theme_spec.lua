local theme = require("release_exporter.ui.theme")

-- ImGui stand-in that records the style stack, so an unbalanced push/pop fails here and not in REAPER.
local function recorder()
  local stack = { colors = 0, vars = 0, pushed = {} }
  local ImGui = setmetatable({
    PushStyleColor = function(_, idx, color)
      stack.colors = stack.colors + 1
      stack.pushed[idx] = color
    end,
    PushStyleVar = function() stack.vars = stack.vars + 1 end,
    PopStyleColor = function(_, count) stack.colors = stack.colors - (count or 1) end,
    PopStyleVar = function(_, count) stack.vars = stack.vars - (count or 1) end,
  }, {
    -- Every ImGui.Col_* / StyleVar_* constant resolves to its own name.
    __index = function(_, key) return key end,
  })
  return ImGui, stack
end

describe("ui.theme", function()
  it("pops exactly what it pushed", function()
    local ImGui, stack = recorder()
    theme.push(ImGui, {})
    assert.is_true(stack.colors > 0)
    assert.is_true(stack.vars > 0)
    theme.pop(ImGui, {})
    assert.are.equal(0, stack.colors)
    assert.are.equal(0, stack.vars)
  end)

  it("paints an opaque window background", function()
    local ImGui, stack = recorder()
    theme.push(ImGui, {})
    assert.are.equal(0xFF, stack.pushed.Col_WindowBg & 0xFF)
  end)
end)
