# REAPER API notes

Empirical findings that `release_exporter` depends on, checked on REAPER 7.80 (macOS arm64) with the probes in
`tools/` and real renders inspected with exiftool. Re-run them when supporting a new REAPER version.

| Topic | Behaviour the code relies on | Confirmed |
|---|---|---|
| Metadata identifiers | The tag table in the README — confirmed by exiftool on real renders; year moved to `ID3:TDRC`, Vorbis label written as `ORGANIZATION` + `LABEL` | ☑ |
| Cover keys | `ID3:APIC_FILE`/`APIC_TYPE=3` (MP3, WAV ID3 chunk) + `FLACPIC:APIC_FILE`/`APIC_TYPE=3` (FLAC PICTURE block, verified) | ☑ |
| Clearing a metadata entry | `RENDER_METADATA` set with `"<id>|"` removes it | ☑ |
| Values containing `|` | Kept intact after the first separator | ☑ |
| `MARKER_GUID:<enum idx>` | Returns `{GUID}` for regions | ☑ |
| `EnumProjExtState` key case | Keys come back **upper-cased** (`TRACK:{ABC}`); handled | ☑ |
| `RENDER_TARGETS` | Honors bounds, `RENDER_FILE`, `RENDER_PATTERN`, `RENDER_FORMAT2`; **empty when bounds are zero-length** | ☑ |
| Render presets | wav24 captured, wav16 derived — both verified by render; mp3_320 and flac captured from `RENDER_FORMAT2` — render verified (320 kbps, 24-bit) | ☑ |

## Environment
- REAPER version: 7.80
- OS: macOS arm64

## Probe output (`tools/probe_api.lua`, 2026-09-28)
```
PASS metadata value with separators A|B; C
PASS clearing removes the id from the list
PASS MARKER_GUID returns a GUID {4B2DECB4-EEBD-6C46-A6E8-1152B4142D5A}
PASS EnumProjExtState upper-cases keys TRACK:{ABC}
PASS RENDER_TARGETS is empty for zero-length bounds
PASS RENDER_TARGETS lists both formats .../ReleaseExporterProbe/probe-name.wav;.../probe-name.mp3
PASS RecursiveCreateDirectory on an existing folder returned 0   <- 0 even on success; ensure_dir ignores it
PASS REAPER 7.80/macOS-arm64
```

## RENDER_TARGETS
Empty while the render bounds have zero length. Once bounds are set, it follows `RENDER_FILE`, `RENDER_PATTERN`
and `RENDER_FORMAT2` (one path per format, separated by `;`), and switching the source to the master mix does not
change it. The renderer sets the region bounds first, then reads it to know which files to delete and check.

## Render presets (`tools/inspect_render_state.lua`)
| Preset | RENDER_FORMAT / RENDER_FORMAT2 |
|---|---|
| wav24 | `ZXZhdxgAAQ==` (`evaw` + `18 00 01`) — render verified 24-bit |
| wav16 | `ZXZhdxAAAQ==` (derived, `10 00 01`) — render verified 16-bit |
| mp3_320 | `bDNwbUABAAAAAAAAAgAAAP////8EAAAAQAEAAAAAAAA=` (`l3pm`, bitrate `0x140` = 320 at offsets 4 and 24) — captured as secondary, render verified 320 kbps. The earlier `...gAAAA...` blob was the 128 kbps secondary (`0x80`) |
| flac | `Y2FsZhgAAAAFAAAA` (`calf` + `0x18` = 24-bit, compression level 5) — captured as secondary, render verified 24-bit |

Capture from `RENDER_FORMAT2`: the exporter always renders MP3/FLAC as the secondary format.

## End-to-end render (`tools/probe_render_e2e.lua`, inspected with `exiftool -G1 -a`)
REAPER accepts (keeps) every identifier it is given, so acceptance proves nothing; only the rendered files count.
- **MP3**: ID3v2.4 with Title, Artist, Band (TPE2), Album, Genre, Copyright, Composer, Publisher (TPUB),
  Track `2/5`, ISRC, RecordingTime (TDRC), Front Cover picture. `ID3:TYER` produced a *separate* ID3v2.3 tag → replaced by TDRC.
- **WAV**: RIFF INFO (INAM, IART, IPRD, ICRD, IGNR, ICOP, ITRK) + the same ID3v2.4 chunk as the MP3, cover included.
- **FLAC**: every Vorbis comment present (TITLE, ARTIST, ALBUMARTIST, ALBUM, DATE, GENRE, ORGANIZATION, LABEL,
  COPYRIGHT, ISRC, COMPOSER, TRACKNUMBER, TRACKTOTAL, TOTALTRACKS). The cover needs its own `FLACPIC:APIC_FILE`
  key: the `ID3:` one is ignored for FLAC. With it, the PICTURE block (front cover) is written.
