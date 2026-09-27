-- @noindex
-- EP card: cover (click to choose, or drop a file) and the EP-level fields.
local model = require("release_exporter.model")
local theme = require("release_exporter.ui.theme")
local widgets = require("release_exporter.ui.widgets")

local M = {}

local C = theme.COLORS
local COVER_SIZE = 118
local GRID_COLUMNS = 6
local cover = { path = nil, image = nil }

-- Forgets the cached cover, e.g. after the ImGui context had to be recreated.
function M.reset()
  cover.path, cover.image = nil, nil
end

local function cover_image(ImGui, ctx, path)
  if path == cover.path then return cover.image end
  if cover.image then ImGui.Detach(ctx, cover.image) end
  cover.path, cover.image = path, nil
  if path ~= "" then
    local ok, image = pcall(ImGui.CreateImage, path)
    if ok and image then
      ImGui.Attach(ctx, image)
      cover.image = image
    end
  end
  return cover.image
end

local function field(ImGui, ctx, app, key, width, hint)
  local value = widgets.text_field(ImGui, ctx, "##ep_" .. key, app.ep[key], {
    width = width, hint = hint, error = model.issue_for(app.validation.errors, nil, "ep." .. key),
  })
  if value then app:set_ep_field(key, value) end
end

-- Empty drop zone: dashed outline (accent while hovered), a "+" and a hint, centred.
local function drop_zone(ImGui, ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, "##cover", COVER_SIZE, COVER_SIZE)
  local hovered = ImGui.IsItemHovered(ctx)
  local draw_list = ImGui.GetWindowDrawList(ctx)
  widgets.dashed_rect(ImGui, draw_list, x, y, x + COVER_SIZE, y + COVER_SIZE, hovered and C.accent or C.dim)
  local lines = { { "+", hovered and C.accent or C.dim }, { "Drop cover", C.muted }, { "or click", C.muted } }
  local line_height = ImGui.GetTextLineHeight(ctx)
  local top = y + (COVER_SIZE - line_height * #lines) / 2
  for i, line in ipairs(lines) do
    local width = ImGui.CalcTextSize(ctx, line[1])
    ImGui.DrawList_AddText(draw_list, x + (COVER_SIZE - width) / 2, top + (i - 1) * line_height, line[2], line[1])
  end
  return clicked
end

local function draw_cover(ImGui, ctx, app)
  ImGui.BeginGroup(ctx)
  local image = cover_image(ImGui, ctx, app.ep.cover)
  local clicked
  if image then
    clicked = ImGui.ImageButton(ctx, "##cover", image, COVER_SIZE, COVER_SIZE)
  else
    clicked = drop_zone(ImGui, ctx)
  end
  if clicked then
    local ok, file = app.r.GetUserFileNameForRead("", "Choose cover image", "jpg")
    if ok then app:set_ep_field("cover", file) end
  end
  if ImGui.BeginDragDropTarget(ctx) then
    local ok, count = ImGui.AcceptDragDropPayloadFiles(ctx)
    if ok and count > 0 then
      local _, file = ImGui.GetDragDropPayloadFile(ctx, 0)
      app:set_ep_field("cover", file)
    end
    ImGui.EndDragDropTarget(ctx)
  end
  if app.ep.cover ~= "" and ImGui.SmallButton(ctx, "Remove cover") then app:set_ep_field("cover", "") end
  ImGui.EndGroup(ctx)
end

-- Fields laid out on a 6-column grid: each row is a list of { label, key, span, hint }.
local ROWS = {
  { { "Artist", "artist", 2 }, { "EP title", "album", 3 }, { "Release date", "year", 1, "YYYY or YYYY-MM-DD" } },
  { { "Album artist", "album_artist", 2, "Same as artist" }, { "Genre", "genre", 1 }, { "Label", "label", 1 },
    { "Copyright", "copyright", 2, "(P) 2026 Name" } },
}

-- Labels and inputs are drawn as two separate lines: mixing text and frames on one line would
-- push the labels after the first column down to the frames' text baseline.
-- Inside a group, SameLine's offset is measured from the group's left edge.
local LABEL_GAP = 5

local function draw_fields(ImGui, ctx, app)
  ImGui.BeginGroup(ctx)
  local gap = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local column = (ImGui.GetContentRegionAvail(ctx) - gap * (GRID_COLUMNS - 1)) / GRID_COLUMNS
  for _, row in ipairs(ROWS) do
    local cells, offset = {}, 0
    for i, f in ipairs(row) do
      local width = column * f[3] + gap * (f[3] - 1)
      cells[i] = { offset = offset, width = width }
      offset = offset + width + gap
    end
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, gap, LABEL_GAP)
    for i, f in ipairs(row) do
      if i > 1 then ImGui.SameLine(ctx, cells[i].offset) end
      widgets.label(ImGui, ctx, f[1])
    end
    ImGui.PopStyleVar(ctx)
    for i, f in ipairs(row) do
      if i > 1 then ImGui.SameLine(ctx, cells[i].offset) end
      field(ImGui, ctx, app, f[2], cells[i].width, f[4])
    end
  end
  ImGui.EndGroup(ctx)
end

function M.draw(ImGui, ctx, app)
  widgets.card(ImGui, ctx, "##ep", {}, function()
    draw_cover(ImGui, ctx, app)
    ImGui.SameLine(ctx, 0, 16)
    draw_fields(ImGui, ctx, app)
  end)
end

return M
