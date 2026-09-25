# REAPER API notes

Empirical findings that `release_exporter` depends on. Fill in by running
`tools/probe_api.lua` and `tools/inspect_render_state.lua` in REAPER (plan Task 2).

**Status: capture pending.** Until then, the code uses the plan's hypotheses:

| Topic | Hypothesis used in code | Confirmed |
|---|---|---|
| Metadata identifiers | Table in spec §4 (`ID3:TYER`, `VORBIS:*`, `INFO:*`) | ☐ |
| Cover keys | `ID3:APIC_FILE` + `ID3:APIC_TYPE=3` for every format | ☐ |
| Clearing a metadata entry | `RENDER_METADATA` set with `"<id>|"` removes it | ☐ |
| Values containing `|` | Kept intact after the first separator | ☐ |
| `MARKER_GUID:<enum idx>` | Returns `{GUID}` for regions | ☐ |
| `EnumProjExtState` key case | Handled case-insensitively either way | ☐ |
| `RENDER_TARGETS` | Honors custom bounds and `RENDER_PATTERN` | ☐ |
| Render presets | 4-character defaults (`evaw`, `l3pm`, `calf`) | ☐ |

## Environment
- REAPER version:
- OS:

## Probe output (`tools/probe_api.lua`)

## RENDER_METADATA dump (`tools/inspect_render_state.lua`)

## Render presets
| Preset | RENDER_FORMAT / RENDER_FORMAT2 |
|---|---|
| wav24 | |
| wav16 | |
| mp3_320 | |
| flac | |
