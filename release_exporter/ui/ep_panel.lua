-- EP card: cover (click to choose, or drop a file) and the EP-level fields.
local model = require("release_exporter.model")
local widgets = require("release_exporter.ui.widgets")

local M = {}

local COVER_SIZE = 110
local cover = { path = nil, image = nil }

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

local function field(ImGui, ctx, app, label, key, width, hint)
  ImGui.BeginGroup(ctx)
  ImGui.TextDisabled(ctx, label)
  local value = widgets.text_field(ImGui, ctx, "##ep_" .. key, app.ep[key], {
    width = width, hint = hint, error = model.issue_for(app.validation.errors, nil, "ep." .. key),
  })
  if value then app:set_ep_field(key, value) end
  ImGui.EndGroup(ctx)
end

local function draw_cover(ImGui, ctx, app)
  ImGui.BeginGroup(ctx)
  local image = cover_image(ImGui, ctx, app.ep.cover)
  local clicked
  if image then
    clicked = ImGui.ImageButton(ctx, "##cover", image, COVER_SIZE, COVER_SIZE)
  else
    clicked = ImGui.Button(ctx, "Drop cover\nor click", COVER_SIZE, COVER_SIZE)
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

function M.draw(ImGui, ctx, app)
  draw_cover(ImGui, ctx, app)
  ImGui.SameLine(ctx)
  ImGui.BeginGroup(ctx)
  local width = ImGui.GetContentRegionAvail(ctx)
  local col = (width - 16) / 10
  field(ImGui, ctx, app, "Artist", "artist", col * 3.5)
  ImGui.SameLine(ctx)
  field(ImGui, ctx, app, "EP title", "album", col * 4.5)
  ImGui.SameLine(ctx)
  field(ImGui, ctx, app, "Year", "year", col * 2, "YYYY")
  field(ImGui, ctx, app, "Album artist", "album_artist", col * 3.5, app.ep.artist)
  ImGui.SameLine(ctx)
  field(ImGui, ctx, app, "Genre", "genre", col * 2)
  ImGui.SameLine(ctx)
  field(ImGui, ctx, app, "Label", "label", col * 2)
  ImGui.SameLine(ctx)
  field(ImGui, ctx, app, "Copyright", "copyright", col * 2.5, "(P) 2026 Name")
  ImGui.EndGroup(ctx)
end

return M
