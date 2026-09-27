# Release Exporter for REAPER

Fill your EP's metadata in one window and export every song as WAV + MP3/FLAC with proper tags (title, artist, album, track number, ISRC, composer, cover art) in one click.

## Requirements
- REAPER 7.80 or newer. It is only tested on REAPER 7.80 (macOS); older 7.x releases may work but are not supported.
- ReaImGui 0.9 or newer (Extensions > ReaPack > Browse packages > "ReaImGui")

## Install
1. Extensions > ReaPack > Import repositories…
2. Paste `https://github.com/Amorfx/reaper-release-plugin/raw/main/index.xml`
3. Extensions > ReaPack > Browse packages > "Release Exporter" > Install
4. Run the action "Script: Release Exporter.lua"

## Workflow
1. Put the songs of your EP in one project: rendered mixes or subprojects, in order.
2. One region per song. No regions yet? Select the items and click "Create one region per selected item".
3. Fill the EP card (artist, title, year, cover…) and the songs table (title = region name, ISRC…).
4. Click "Export EP". Files land in `<project folder>/Exports/<EP title>` unless you pick another folder.

## Good to know
- Metadata is saved inside the `.rpp` (save the project to keep it).
- Renaming a song renames its region and can be undone with Ctrl+Z. Other fields are not part of REAPER's undo history.
- Each region is rendered exactly from its start to its end: extend the region to keep a reverb tail.
- Your own render settings are restored after the export.
- `$`, `;` and characters that are not allowed in file names are replaced by `-`.
