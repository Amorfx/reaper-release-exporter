-- Pure: turns a resolved track (see model.resolve) into REAPER RENDER_METADATA entries.
-- Every scheme is written explicitly so we never rely on REAPER's implicit cross-scheme mapping.
-- Identifiers are confirmed by a real render inspected with exiftool (docs/reaper-api-notes.md).
local M = {}

M.SCHEMES = { "ID3", "VORBIS", "INFO" }

M.FIELDS = {
  { key = "title", ID3 = "TIT2", VORBIS = "TITLE", INFO = "INAM" },
  { key = "artist", ID3 = "TPE1", VORBIS = "ARTIST", INFO = "IART" },
  { key = "album_artist", ID3 = "TPE2", VORBIS = "ALBUMARTIST" },
  { key = "album", ID3 = "TALB", VORBIS = "ALBUM", INFO = "IPRD" },
  { key = "year", ID3 = "TDRC", VORBIS = "DATE", INFO = "ICRD" }, -- REAPER writes ID3v2.4, where TYER is obsolete
  { key = "genre", ID3 = "TCON", VORBIS = "GENRE", INFO = "IGNR" },
  { key = "label", ID3 = "TPUB", VORBIS = "ORGANIZATION" },
  { key = "label", VORBIS = "LABEL" }, -- players read either ORGANIZATION or LABEL
  { key = "copyright", ID3 = "TCOP", VORBIS = "COPYRIGHT", INFO = "ICOP" },
  { key = "isrc", ID3 = "TSRC", VORBIS = "ISRC" },
  { key = "composer", ID3 = "TCOM", VORBIS = "COMPOSER" },
}

M.COVER_KEYS = { "ID3:APIC_FILE" }

function M.build(t)
  local out = {}
  local function add(id, value)
    if value ~= nil and value ~= "" then out[#out + 1] = id .. "|" .. value end
  end
  for _, field in ipairs(M.FIELDS) do
    for _, scheme in ipairs(M.SCHEMES) do
      if field[scheme] then add(scheme .. ":" .. field[scheme], t[field.key]) end
    end
  end
  if t.number then
    add("ID3:TRCK", t.number .. "/" .. t.total)
    add("VORBIS:TRACKNUMBER", tostring(t.number))
    add("VORBIS:TRACKTOTAL", tostring(t.total))
    add("INFO:ITRK", tostring(t.number))
  end
  if t.cover and t.cover ~= "" then
    for _, id in ipairs(M.COVER_KEYS) do add(id, t.cover) end
    add("ID3:APIC_TYPE", "3")
  end
  return out
end

return M
