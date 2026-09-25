# REAPER API notes

Empirical findings that `release_exporter` depends on. Fill in by running
`tools/probe_api.lua` and `tools/inspect_render_state.lua` in REAPER (plan Task 2).

**Status: probes done (REAPER 7.80, macOS arm64); metadata identifiers and render presets still to capture.** Until then, the code uses the plan's hypotheses:

| Topic | Hypothesis used in code | Confirmed |
|---|---|---|
| Metadata identifiers | Table in spec §4 (`ID3:TYER`, `VORBIS:*`, `INFO:*`) | ☐ |
| Cover keys | `ID3:APIC_FILE` + `ID3:APIC_TYPE=3` for every format | ☐ |
| Clearing a metadata entry | `RENDER_METADATA` set with `"<id>|"` removes it | ☑ |
| Values containing `|` | Kept intact after the first separator | ☑ |
| `MARKER_GUID:<enum idx>` | Returns `{GUID}` for regions | ☑ |
| `EnumProjExtState` key case | Keys come back **upper-cased** (`TRACK:{ABC}`); handled | ☑ |
| `RENDER_TARGETS` | Honors bounds, `RENDER_FILE`, `RENDER_PATTERN`, `RENDER_FORMAT2`; **empty when bounds are zero-length** | ☑ |
| Render presets | 4-character defaults (`evaw`, `l3pm`, `calf`) | ☐ |

## Environment
- REAPER version: 7.80
- OS: macOS arm64

## Probe output (`tools/probe_api.lua`)
```
PASS metadata value with separators A|B; C
PASS clearing removes the id from the list
PASS MARKER_GUID returns a GUID {6B622AC0-AC13-6743-95A7-439D756E8D6A}
PASS EnumProjExtState key case returned key = TRACK:{ABC}
FAIL RENDER_TARGETS uses the pattern          <- bounds were 0..0, see below
PASS RecursiveCreateDirectory (new)
PASS RecursiveCreateDirectory (existing) returned 0   <- 0 even on success; ensure_dir ignores it
```

## RENDER_TARGETS (`tools/probe_render_targets.lua`)
```
0. current settings              (empty)            <- custom bounds 0..0
1. custom bounds 0..5 s          .../reaper-test/probe-name.wav
2. + RENDER_FILE                 .../ReleaseExporterProbe/probe-name.wav
5. + RENDER_FORMAT2 l3pm         .../probe-name.wav;.../probe-name.mp3
6. + master mix only             (unchanged)
```

## RENDER_METADATA dump (`tools/inspect_render_state.lua`)

## Render presets
| Preset | RENDER_FORMAT / RENDER_FORMAT2 |
|---|---|
| wav24 | |
| wav16 | |
| mp3_320 | |
| flac | |
