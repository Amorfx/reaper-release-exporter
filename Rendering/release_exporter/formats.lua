-- @noindex
-- Render sink configurations per preset, captured from REAPER (see docs/reaper-api-notes.md).
-- A 4-character code ("evaw", "l3pm", "calf") means "REAPER defaults for that sink".
local M = {}

M.PRIMARY = {
  wav24 = "ZXZhdxgAAQ==", -- captured on REAPER 7.80: "evaw" + 0x18 (24-bit PCM)
  wav16 = "ZXZhdxAAAQ==", -- same config with 0x10 (16-bit PCM)
}

M.SECONDARY = {
  mp3_320 = "bDNwbUABAAAAAAAAAgAAAP////8EAAAAQAEAAAAAAAA=", -- captured on REAPER 7.80: "l3pm", CBR, 0x140 (320 kbps)
  flac = "Y2FsZhgAAAAFAAAA",                                -- captured on REAPER 7.80: "calf" + 0x18 (24-bit), level 5
  none = "",
}

function M.primary(key)
  return M.PRIMARY[key] or M.PRIMARY.wav24
end

function M.secondary(key)
  return M.SECONDARY[key] or ""
end

return M
