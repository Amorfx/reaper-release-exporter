# README demo

Everything needed to redo the screenshots in `docs/images/` for a new release. Not shipped with the package.

1. `python3 tools/readme-demo/make_demo.py` writes the demo projects, the media and the cover to
   `tools/readme-demo/out/` (git-ignored). The cover is rendered from `cover.html` with headless Chrome.
2. In REAPER, run `tools/readme-demo/open_demo.lua` (Actions list, or
   `REAPER -nonewinst tools/readme-demo/open_demo.lua`). It opens `demo.rpp` in a new tab; running it again
   in that tab cycles to `demo-invalid.rpp`, then `demo-empty.rpp`.
3. Run *Release Exporter* and capture each window with `screencapture -x -o -l<window id>`
   (the `-o` removes the shadow). The window ids come from `CGWindowListCopyWindowInfo`.

| Screenshot | Project | State |
|---|---|---|
| `main.png` | `demo.rpp` | As opened |
| `settings.png` | `demo.rpp` | *Settings* open |
| `confirm.png` | `demo.rpp` | *Export 4 songs* clicked |
| `report.png` | `demo.rpp` | After the export (writes to `/Users/Shared/Releases/Night Songs`) |
| `validation.png` | `demo-invalid.rpp` | As opened |
| `empty-state.png` | `demo-empty.rpp` | As opened |
| `reapack-import.png` | any | *Extensions > ReaPack > Import repositories…* with the index URL, then *Cancel* |

`header.rpp` and `track.rpp` are the project header and track block of an empty REAPER 7.80 project.
