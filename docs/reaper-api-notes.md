# REAPER API notes

Empirical findings that `release_exporter` depends on. Fill in by running
`tools/probe_api.lua` and `tools/inspect_render_state.lua` in REAPER (plan Task 2).

**Status: probes and end-to-end renders done (REAPER 7.80, macOS arm64). Pending: MP3 320 and FLAC 24-bit presets.** Until then, the code uses the plan's hypotheses:

| Topic | Hypothesis used in code | Confirmed |
|---|---|---|
| Metadata identifiers | Table in spec §4 — confirmed by exiftool on real renders; year moved to `ID3:TDRC`, Vorbis label written as `ORGANIZATION` + `LABEL` | ☑ |
| Cover keys | `ID3:APIC_FILE`/`APIC_TYPE=3` (MP3, WAV ID3 chunk) + `FLACPIC:APIC_FILE`/`APIC_TYPE=3` (FLAC PICTURE block, verified) | ☑ |
| Clearing a metadata entry | `RENDER_METADATA` set with `"<id>|"` removes it | ☑ |
| Values containing `|` | Kept intact after the first separator | ☑ |
| `MARKER_GUID:<enum idx>` | Returns `{GUID}` for regions | ☑ |
| `EnumProjExtState` key case | Keys come back **upper-cased** (`TRACK:{ABC}`); handled | ☑ |
| `RENDER_TARGETS` | Honors bounds, `RENDER_FILE`, `RENDER_PATTERN`, `RENDER_FORMAT2`; **empty when bounds are zero-length** | ☑ |
| Render presets | wav24 captured, wav16 derived — both verified by render; `l3pm` = 128 kbps, `calf` = 16-bit → recapture | ◐ |

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
| wav24 | `ZXZhdxgAAQ==` (`evaw` + `18 00 01`) — render verified 24-bit |
| wav16 | `ZXZhdxAAAQ==` (derived, `10 00 01`) — render verified 16-bit |
| mp3_320 | not captured yet. `bDNwbYAAAAAAAAAAAgAAAP////8EAAAAgAAAAAAAAAA=` renders **128 kbps** (0x80 = 128?) |
| flac | not captured yet (default `calf` renders 16-bit) |

Next capture: set MP3 CBR 320 (then FLAC 24-bit) as the **primary** format, *Save settings*, read `RENDER_FORMAT`.

## End-to-end render (`tools/probe_render_e2e.lua`, inspected with `exiftool -G1 -a`)
REAPER accepts (keeps) every identifier it is given, so acceptance proves nothing; only the rendered files count.
- **MP3**: ID3v2.4 with Title, Artist, Band (TPE2), Album, Genre, Copyright, Composer, Publisher (TPUB),
  Track `2/5`, ISRC, RecordingTime (TDRC), Front Cover picture. `ID3:TYER` produced a *separate* ID3v2.3 tag → replaced by TDRC.
- **WAV**: RIFF INFO (INAM, IART, IPRD, ICRD, IGNR, ICOP, ITRK) + the same ID3v2.4 chunk as the MP3, cover included.
- **FLAC**: every Vorbis comment present (TITLE, ARTIST, ALBUMARTIST, ALBUM, DATE, GENRE, ORGANIZATION, LABEL,
  COPYRIGHT, ISRC, COMPOSER, TRACKNUMBER, TRACKTOTAL, TOTALTRACKS) but **no picture block**.
