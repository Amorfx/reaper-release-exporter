# Manual test checklist

Run on REAPER 7.0 (oldest supported) and on the latest REAPER, with ReaImGui ≥ 0.9.

## Setup
1. Symlink the repo into REAPER's Scripts folder (*Options > Show REAPER resource path*):
   `ln -s "$PWD" "<resource path>/Scripts/reaper-release-plugin"`
2. *Actions > Show action list > New action > Load ReaScript…* → `Release Exporter.lua`.
3. Sample project: 3 audio items on one track, saved as `EP.rpp` in an empty folder.

## Checks
- [ ] Without ReaImGui installed: a clear message box, no Lua error.
- [ ] Empty project: the empty state is shown. Select the 3 items → "Create one region per selected item" → 3 rows named after the items. One Ctrl+Z removes all 3 regions.
- [ ] Fill Artist, EP title, Year. Drop a JPEG onto the cover → the preview appears.
- [ ] Edit a title in the table, press Tab → the region is renamed in the timeline. One Ctrl+Z restores the old name.
- [ ] Rename a region in REAPER → the table updates. Move the last region to the start → the row order and numbers update.
- [ ] Enter an invalid ISRC → the cell turns red, a tooltip shows, Export is disabled. Fix it → Export is enabled.
- [ ] Untick one row → the numbering skips it and "Export EP (2)" is shown.
- [ ] Save, close and reopen the project → every field is still there.
- [ ] Set render dialog options first (e.g. region matrix bounds, a custom pattern, some metadata). Export WAV 24 + MP3 → the report says OK for 2 songs, and the render dialog options are unchanged afterwards.
- [ ] `ffprobe -hide_banner "02 - <title>.mp3"` shows title, artist, album, track `2/2`, date, ISRC and an attached picture stream.
- [ ] Switch to WAV 16 + FLAC, export again → the overwrite prompt lists 4 files. `ffprobe` on the FLAC shows the Vorbis tags and the picture.
- [ ] Unsaved new project with regions → the "Save the project or choose an output folder." error blocks Export.
- [ ] A title with `AC/DC: Live?` → exported as `01 - AC-DC- Live-.wav`.
- [ ] Open two project tabs with different data and switch between them → the window follows the active tab.
