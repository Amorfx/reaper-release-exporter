# Manual test checklist

Run on REAPER 7.80 (the only supported and tested version), with ReaImGui ≥ 0.9.

## Setup
1. Symlink the repo into REAPER's Scripts folder (*Options > Show REAPER resource path*):
   `ln -s "$PWD" "<resource path>/Scripts/reaper-release-plugin"`
2. *Actions > Show action list > New action > Load ReaScript…* → `Rendering/Release Exporter.lua`.
3. Sample project: 3 audio items on one track, saved as `Release.rpp` in an empty folder.

## Checks
- [ ] Without ReaImGui installed: a clear message box, no Lua error.
- [ ] Empty project: the empty state is shown. Select the 3 items → "Create one region per selected item" → 3 rows named after the items. One Ctrl+Z removes all 3 regions.
- [ ] Look: opaque near-black window (nothing shows through), release card and songs table in rounded cards, green accent only on ticked boxes and the Export button, placeholders clearly dimmer than values. Compare with the mockup (`style-direction3`, option C).
- [ ] Fill Artist, Release title, Release date. Drop a JPEG onto the cover → the preview appears.
- [ ] Edit a title in the table, press Tab → the region is renamed in the timeline. One Ctrl+Z restores the old name.
- [ ] Rename a region in REAPER → the table updates. Move the last region to the start → the row order and numbers update.
- [ ] Enter an invalid ISRC → the cell turns red, a tooltip shows, Export is disabled. Fix it → Export is enabled.
- [ ] Untick one row → the numbering skips it, the row is dimmed and "Export 2 songs" is shown.
- [ ] Save, close and reopen the project → every field is still there.
- [ ] Set render dialog options first (e.g. region matrix bounds, a custom pattern, some metadata). Export WAV 24 + MP3 → the report says OK for 2 songs, and the render dialog options are unchanged afterwards.
- [ ] `ffprobe -hide_banner "02 - <title>.mp3"` shows title, artist, album, track `2/2`, date, ISRC and an attached picture stream.
- [ ] Switch to WAV 16 + FLAC, export again → the overwrite prompt lists 4 files. `ffprobe` on the FLAC shows the Vorbis tags and the picture.
- [ ] Unsaved new project with regions → the "Save the project or choose an output folder." error blocks Export.
- [ ] A title with `AC/DC: Live?` → exported as `01 - AC-DC- Live-.wav`.
- [ ] Open two project tabs with different data and switch between them → the window follows the active tab.
- [ ] Open another project **in the same tab** (File > Open project, not a new tab) → the release card shows the new project's data, never the previous one.
- [ ] Unsaved project: fill everything, then Save → the output folder error disappears without any other edit. Save As to another folder → the summary shows the new folder.
- [ ] Type in the release Artist field without leaving it, then click another project tab → the text is not saved in either project.
- [ ] During an export, press Cancel in REAPER's render window → a prompt asks whether to continue. "No" marks the remaining songs as skipped. Check whether REAPER left a partial file for the cancelled song (note it in docs/reaper-api-notes.md).
- [ ] Open one of the exported WAVs in another app (Windows: keeps it locked), export again → that song reports "Cannot overwrite …", no REAPER overwrite prompt.
- [ ] Export an 8-song release (several minutes) → the window and the report still show afterwards.
