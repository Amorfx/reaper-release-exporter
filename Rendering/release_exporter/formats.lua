-- Render sink configurations per preset, captured from REAPER (see docs/reaper-api-notes.md).
-- A 4-character code ("evaw", "l3pm", "calf") means "REAPER defaults for that sink".
local M = {}

M.PRIMARY = {
  wav24 = "evaw", -- replace with the captured base64 for WAV 24-bit
  wav16 = "evaw", -- replace with the captured base64 for WAV 16-bit
}

M.SECONDARY = {
  mp3_320 = "l3pm", -- replace with the captured base64 for MP3 CBR 320
  flac = "calf",    -- replace with the captured base64 for FLAC
  none = "",
}

function M.primary(key)
  return M.PRIMARY[key] or M.PRIMARY.wav24
end

function M.secondary(key)
  return M.SECONDARY[key] or ""
end

return M
