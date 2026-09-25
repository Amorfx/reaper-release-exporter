# Release Exporter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a REAPER ReaScript (Lua + ReaImGui) that lets a user fill EP-level and per-song metadata in one modern window and export every region of an EP project as WAV + MP3/FLAC with correct embedded tags, in one click.

**Architecture:** Pure Lua modules (`model`, `metadata_mapper`) hold all business rules and are unit-tested outside REAPER. Thin adapters (`regions`, `project_store`, `renderer`, `fs`) talk to the REAPER API through an injected `r` table, so they are tested against an in-memory fake. An `app` controller glues them together. ReaImGui views only call `app` methods. The renderer drives REAPER one region at a time (action 42230), then restores the user's render settings no matter what.

**Tech Stack:** Lua 5.4 (REAPER's embedded Lua), ReaImGui ≥ 0.9, busted + luacheck for tests and lint, rxi/json.lua (vendored), ReaPack + reapack-index for distribution, GitHub Actions for CI.

**Spec:** `docs/superpowers/specs/2026-09-25-ep-metadata-export-design.md`

## Global Constraints

- Minimum REAPER version: **7.0**. The only runtime dependency is **ReaImGui ≥ 0.9** (loaded with `require("imgui")("0.9")`).
- `release_exporter/model.lua` and `release_exporter/metadata_mapper.lua` must **never** reference the global `reaper`.
- Every REAPER-facing function takes the API table `r` as its first argument and never reads the global `reaper` directly. The entry script passes `reaper` in.
- ExtState section: `"ReleaseExporter"`. Project keys: `ep`, `settings`, `track:<GUID>`, `schema_version` (= `"1"`). Global key: `default_settings`.
- Region identity: GUID from `GetSetProjectInfo_String(proj, "MARKER_GUID:<enum idx>", "", false)`.
- Render action: `42230` (*File: Render project, using the most recent render settings, auto-close render dialog*).
- Defaults: file name pattern `{nn} - {title}`, output folder `<project dir>/Exports/<EP title>`, primary `wav24`, secondary `mp3_320`, sample rate `0` (= project rate).
- Characters replaced by `-` in file names: `/ \ : * ? " < > | $ ;` and control characters. Trailing spaces and dots are trimmed, and an empty result becomes `untitled`.
- ISRC regex (after upper-casing and stripping spaces and dashes): 2 letters, 3 alphanumerics, 7 digits (12 characters).
- Year: `YYYY` or `YYYY-MM-DD`.
- UI strings in **English**.
- Commits: conventional commits `type(domain): message`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Unsaved project** (no `.rpp` path) with no output folder chosen → export is blocked with "Save the project or choose an output folder." It must never render to `/Exports/...` or crash. Pinned in Task 3 (`validate`) and Task 7 (`app` unsaved project).
2. **Song titles with characters that are illegal or special** (`AC/DC: Live?`, `Ca$h`, `a;b`, trailing dots) → safe file names, and REAPER never interprets `$` as a wildcard. Pinned in Task 3 (`sanitize_filename`).
3. **A Lua error or a missing file in the middle of an export** → the user's render settings and project metadata are restored exactly, the failure shows in the report, and the other songs are still rendered when the failure is a missing file. Pinned in Task 6.
4. **Regions reordered, deleted then restored (Ctrl+Z), or the active project tab switched** → metadata follows the region GUID, and nothing leaks between projects. Pinned in Task 3 (reorder), Task 7 (delete/restore, project switch).
5. **Corrupted, hand-edited or mistyped ExtState** (bad JSON, wrong types, upper-cased keys) → falls back to defaults field by field, never crashes on load. Pinned in Task 5.

---

## File Structure

```
Release Exporter.lua                 -- entry point: dependency check, package.path, defer loop (Task 8)
release_exporter/
  model.lua                          -- pure: fields, defaults, rows, fallback, numbering, validation, file names (Task 3)
  metadata_mapper.lua                -- pure: resolved track -> "SCHEME:TAG|value" list (Task 4)
  formats.lua                        -- render sink configs per preset (Task 2)
  fs.lua                             -- file helpers: exists, size, remove, ensure_dir, open_folder (Task 6)
  regions.lua                        -- REAPER adapter: list/rename/create regions (Task 5)
  project_store.lua                  -- REAPER adapter: ProjExtState persistence (Task 5)
  renderer.lua                       -- REAPER adapter: snapshot, per-region render, restore (Task 6)
  app.lua                            -- controller used by the UI (Task 7)
  ui/init.lua                        -- window layout (Task 8)
  ui/widgets.lua                     -- commit-on-deactivate text field, combo (Task 8)
  ui/ep_panel.lua                    -- EP card + cover (Task 8)
  ui/tracks_table.lua                -- songs table + empty state (Task 8)
  ui/export_bar.lua                  -- summary, issues, Export button, confirm popup (Task 8)
  ui/settings_popup.lua              -- export settings modal (Task 8)
  ui/report_popup.lua                -- export report modal (Task 8)
  vendor/json.lua                    -- rxi/json.lua, MIT (Task 1)
tools/inspect_render_state.lua       -- dev-only: dump render state (Task 2)
tools/probe_api.lua                  -- dev-only: check API assumptions (Task 2)
tests/support/fake_reaper.lua        -- in-memory REAPER API subset (Task 5, extended in Task 6)
tests/*_spec.lua                     -- busted specs
docs/reaper-api-notes.md             -- empirical findings (Task 2)
docs/testing.md                      -- manual test checklist (Task 8)
README.md, .busted, .luacheckrc, .github/workflows/ci.yml
```

---

### Task 1: Tooling scaffold

**Files:**
- Create: `.busted`, `.luacheckrc`, `.github/workflows/ci.yml`, `release_exporter/vendor/json.lua`, `tests/json_spec.lua`

**Interfaces:**
- Produces: `require("release_exporter.vendor.json")` with `encode(value) -> string` and `decode(string) -> value` (raises an error on invalid input). Also a working `busted` + `luacheck` setup run from the repo root.

- [ ] **Step 1: Install the local toolchain**

```bash
brew install lua luarocks
luarocks install busted
luarocks install luacheck
lua -v   # Expected: Lua 5.4.x
```

- [ ] **Step 2: Vendor the JSON library**

```bash
mkdir -p release_exporter/vendor
curl -sL https://raw.githubusercontent.com/rxi/json.lua/master/json.lua -o release_exporter/vendor/json.lua
head -5 release_exporter/vendor/json.lua   # Expected: rxi copyright header (MIT)
```

- [ ] **Step 3: Add the busted and luacheck configs**

`.busted`:

```lua
return {
  default = {
    ROOT = { "tests" },
    pattern = "_spec",
    lpath = "./?.lua;./?/init.lua",
  },
}
```

`.luacheckrc`:

```lua
std = "lua54"
read_globals = { "reaper" }
max_line_length = 140
exclude_files = { "release_exporter/vendor/**", ".superpowers/**", "lua_modules/**", ".luarocks/**" }
files["tests/**"] = { std = "+busted" }
```

- [ ] **Step 4: Write the smoke test**

`tests/json_spec.lua`:

```lua
local json = require("release_exporter.vendor.json")

describe("vendored json", function()
  it("round-trips a table with strings, booleans and numbers", function()
    local value = { artist = "Clém", include = false, srate = 48000 }
    assert.are.same(value, json.decode(json.encode(value)))
  end)

  it("raises on invalid input", function()
    assert.has_error(function() json.decode("{not json") end)
  end)
end)
```

- [ ] **Step 5: Run the tests and lint**

Run: `busted && luacheck .`
Expected: `2 successes / 0 failures`, then `Total: 0 warnings / 0 errors`.

- [ ] **Step 6: Add CI**

`.github/workflows/ci.yml`:

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: leafo/gh-actions-lua@v10
        with:
          luaVersion: "5.4"
      - uses: leafo/gh-actions-luarocks@v4
      - run: luarocks install busted && luarocks install luacheck
      - run: luacheck .
      - run: busted
```

- [ ] **Step 7: Commit**

```bash
git add .busted .luacheckrc .github release_exporter/vendor tests/json_spec.lua
git commit -m "chore(tooling): add busted, luacheck, CI and vendored json

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Verify REAPER API assumptions (human in the loop)

This task needs a person at REAPER. Its output is **data** that later tasks depend on: the exact metadata identifiers, the base64 render configs, and a few behaviors of the API.

**Files:**
- Create: `tools/inspect_render_state.lua`, `tools/probe_api.lua`, `release_exporter/formats.lua`, `docs/reaper-api-notes.md`

**Interfaces:**
- Produces: `formats.PRIMARY` (`{ wav16 = string, wav24 = string }`), `formats.SECONDARY` (`{ mp3_320 = string, flac = string, none = "" }`), `formats.primary(key) -> string`, `formats.secondary(key) -> string`.
- Produces: `docs/reaper-api-notes.md`. It lists confirmed tag identifiers (which feed the `M.FIELDS` and `M.COVER_KEYS` tables in Task 4) and the answers to the probes.

- [ ] **Step 1: Write the inspection tool**

`tools/inspect_render_state.lua`:

```lua
-- Dev tool (not shipped): prints the current project's render state to the REAPER console.
local r = reaper
local proj = 0
local function p(s) r.ShowConsoleMsg(s .. "\n") end

r.ClearConsole()
p("=== RENDER_METADATA ===")
local _, ids = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "", false)
for id in ids:gmatch("[^;]+") do
  local _, value = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", id, false)
  p(id .. " = " .. value)
end
p("=== STRINGS ===")
for _, key in ipairs({ "RENDER_FORMAT", "RENDER_FORMAT2", "RENDER_FILE", "RENDER_PATTERN", "RENDER_TARGETS" }) do
  local _, value = r.GetSetProjectInfo_String(proj, key, "", false)
  p(key .. " = " .. value)
end
p("=== NUMBERS ===")
for _, key in ipairs({ "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_SRATE", "RENDER_ADDTOPROJ", "RENDER_TAILFLAG" }) do
  p(key .. " = " .. tostring(r.GetSetProjectInfo(proj, key, 0, false)))
end
```

- [ ] **Step 2: Write the probe tool**

`tools/probe_api.lua`:

```lua
-- Dev tool (not shipped): checks the API behaviors release_exporter relies on. Run on a scratch project.
local r = reaper
local proj = 0
local function p(label, ok, detail) r.ShowConsoleMsg(("%s %s %s\n"):format(ok and "PASS" or "FAIL", label, detail or "")) end
local function meta(id) local _, v = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", id, false); return v end

r.ClearConsole()

-- 1. Metadata set / read / clear with "ID|" and values containing "|"
r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "ID3:TIT2|A|B; C", true)
p("metadata value with separators", meta("ID3:TIT2") == "A|B; C", meta("ID3:TIT2"))
r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "ID3:TIT2|", true)
local _, ids = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "", false)
p("clearing removes the id from the list", not ids:find("ID3:TIT2", 1, true), ids)

-- 2. MARKER_GUID on a region
local idx = r.AddProjectMarker2(proj, true, 0, 5, "probe", -1, 0)
local count = r.CountProjectMarkers(proj)
local guid
for i = 0, count - 1 do
  local _, isrgn, _, _, name, number = r.EnumProjectMarkers3(proj, i)
  if isrgn and number == idx and name == "probe" then
    local _, g = r.GetSetProjectInfo_String(proj, "MARKER_GUID:" .. i, "", false)
    guid = g
  end
end
p("MARKER_GUID returns a GUID", guid and guid:match("^{.+}$") ~= nil, guid)

-- 3. ProjExtState key case in EnumProjExtState
r.SetProjExtState(proj, "ReleaseExporterProbe", "track:{abc}", "x")
local _, key = r.EnumProjExtState(proj, "ReleaseExporterProbe", 0)
p("EnumProjExtState key case", true, "returned key = " .. tostring(key))
r.SetProjExtState(proj, "ReleaseExporterProbe", "", "")

-- 4. RENDER_TARGETS follows custom bounds + pattern
r.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 0, true)
r.GetSetProjectInfo_String(proj, "RENDER_PATTERN", "probe-name", true)
local _, targets = r.GetSetProjectInfo_String(proj, "RENDER_TARGETS", "", false)
p("RENDER_TARGETS uses the pattern", targets:find("probe-name", 1, true) ~= nil, targets)

-- 5. RecursiveCreateDirectory return value on an existing folder
local dir = r.GetResourcePath() .. "/ReleaseExporterProbe"
p("RecursiveCreateDirectory (new)", r.RecursiveCreateDirectory(dir, 0) > 0)
p("RecursiveCreateDirectory (existing)", true, "returned " .. r.RecursiveCreateDirectory(dir, 0))
```

- [ ] **Step 3: Run the probe in REAPER**

In REAPER: *Actions > Show action list > New action > Load ReaScript…*, pick `tools/probe_api.lua`, then run it in a new, empty project.
Expected: every line reads `PASS` except the informative ones (EnumProjExtState key case, RecursiveCreateDirectory existing). Copy the whole console output.

- [ ] **Step 4: Capture metadata identifiers**

1. In a scratch project, open *File > Project Render Metadata* (the *Metadata* button of the render dialog).
2. Fill **every** field from spec §4 in the ID3, Vorbis and INFO schemes with a recognizable value. Set an image file.
3. Run `tools/inspect_render_state.lua` and copy the `RENDER_METADATA` section.
4. Check the year key (`ID3:TYER` or `ID3:TDRC`), the Vorbis and INFO scheme prefixes, and any image key that is not `ID3:APIC_FILE` (for example, one specific to FLAC or Vorbis).

- [ ] **Step 5: Capture format configs**

For each preset, configure the render dialog, click *Save settings* (not Render), then run `tools/inspect_render_state.lua` and copy `RENDER_FORMAT` / `RENDER_FORMAT2`:

| Preset key | Render dialog setting |
|---|---|
| `wav24` | Primary: WAV, 24-bit PCM, no secondary |
| `wav16` | Primary: WAV, 16-bit PCM, no secondary |
| `mp3_320` | Secondary: MP3, CBR 320 kbps (read `RENDER_FORMAT2`) |
| `flac` | Secondary: FLAC, 24-bit, default compression (read `RENDER_FORMAT2`) |

- [ ] **Step 6: Write `release_exporter/formats.lua`**

Paste the captured base64 strings in place of the 4-character fallback codes (`evaw` = WAV, `l3pm` = MP3, `calf` = FLAC, which are REAPER's per-sink defaults). Keep the fallback if a capture was impossible, and say so in the notes.

```lua
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
```

- [ ] **Step 7: Write `docs/reaper-api-notes.md`**

Record: the REAPER version used, the probe output from Step 3, the full `RENDER_METADATA` dump from Step 4, the confirmed identifier for each row of spec §4 (update the spec table if any differ), the list of image keys, and the preset strings from Step 5.

- [ ] **Step 8: Commit**

```bash
git add tools release_exporter/formats.lua docs/reaper-api-notes.md docs/superpowers/specs
git commit -m "chore(reaper): record verified API identifiers and render presets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `model` — rows, fallbacks, validation, file names

**Files:**
- Create: `release_exporter/model.lua`
- Test: `tests/model_spec.lua`

**Interfaces:**
- Produces (all pure):
  - `model.FORMAT_EXT = { wav16 = "wav", wav24 = "wav", mp3_320 = "mp3", flac = "flac" }`
  - `model.FORMAT_LABELS = { wav24 = "WAV 24-bit", wav16 = "WAV 16-bit", mp3_320 = "MP3 320 kbps", flac = "FLAC", none = "None" }`
  - `model.new_ep() -> { artist, album_artist, album, year, genre, label, copyright, cover }` (all `""`)
  - `model.default_track() -> { include = true, artist = "", isrc = "", composer = "" }`
  - `model.default_settings() -> { output_dir = "", pattern = "{nn} - {title}", primary = "wav24", secondary = "mp3_320", srate = 0 }`
  - `model.blank(s) -> boolean`
  - `model.build_rows(regions, track_data) -> rows`. `regions` is an array of `{ guid, name, start, stop }` and `track_data` maps `guid -> partial track`. Each row is `{ guid, title, start, stop, duration, include, artist, isrc, composer, number?, total? }`, sorted by `start` (then `guid`).
  - `model.resolve(ep, row) -> resolved`, where `resolved = { title, artist, album_artist, album, year, genre, label, copyright, cover, isrc, composer, number, total }`
  - `model.normalize_isrc(s) -> string`, `model.is_valid_isrc(s) -> boolean`, `model.is_valid_year(s) -> boolean`
  - `model.sanitize_filename(s) -> string`, `model.format_filename(pattern, resolved) -> string`
  - `model.default_output_dir(project_dir, album) -> string` (`""` if `project_dir` is blank)
  - `model.plan_outputs(ep, rows, settings, output_dir) -> jobs`. Each job is `{ guid, title, start, stop, resolved, basename, files }` and covers included rows only.
  - `model.validate(ep, rows, settings, output_dir, opts) -> { errors = issues, warnings = issues }`. Each issue is `{ field, message, guid? }`. `opts.file_exists(path)` is optional.
  - `model.issue_for(issues, guid, field) -> message | nil`
  - Issue `field` values: `"ep.artist"`, `"ep.album"`, `"ep.year"`, `"ep.cover"`, `"settings.output_dir"`, `"rows"`, `"title"`, `"isrc"`.

- [ ] **Step 1: Write the failing tests**

`tests/model_spec.lua`:

```lua
local model = require("release_exporter.model")

local function region(guid, start, stop, name)
  return { guid = guid, start = start, stop = stop, name = name }
end

local function make_ep(overrides)
  local ep = model.new_ep()
  ep.artist, ep.album, ep.year, ep.cover = "Clem", "Nuits", "2026", "/art/cover.jpg"
  for k, v in pairs(overrides or {}) do ep[k] = v end
  return ep
end

-- specs: array of { guid, title, isrc, include }
local function make_rows(specs)
  local regions, data = {}, {}
  for i, s in ipairs(specs) do
    regions[i] = region(s[1], i * 10, i * 10 + 5, s[2])
    data[s[1]] = { include = s[4] ~= false, artist = "", isrc = s[3] or "", composer = "" }
  end
  return model.build_rows(regions, data)
end

local always = function() return true end

describe("model.build_rows", function()
  it("sorts by position and numbers only included rows", function()
    local rows = model.build_rows(
      { region("{B}", 10, 20, "Second"), region("{A}", 0, 10, "First"), region("{C}", 20, 30, "Draft") },
      { ["{C}"] = { include = false } })
    assert.are.same({ "First", "Second", "Draft" }, { rows[1].title, rows[2].title, rows[3].title })
    assert.are.equal(1, rows[1].number)
    assert.are.equal(2, rows[1].total)
    assert.are.equal(2, rows[2].number)
    assert.is_nil(rows[3].number)
  end)

  it("fills missing track data with defaults", function()
    local rows = model.build_rows({ region("{A}", 0, 5, "Intro") }, {})
    assert.is_true(rows[1].include)
    assert.are.equal("", rows[1].isrc)
    assert.are.equal(5, rows[1].duration)
  end)

  it("keeps metadata attached to the GUID when regions are reordered", function()
    local data = { ["{A}"] = { include = true, isrc = "FRXXX2600001", artist = "", composer = "" } }
    local rows = model.build_rows({ region("{B}", 0, 5, "Now first"), region("{A}", 5, 9, "Now second") }, data)
    assert.are.equal("", rows[1].isrc)
    assert.are.equal("FRXXX2600001", rows[2].isrc)
    assert.are.equal(2, rows[2].number)
  end)
end)

describe("model.resolve", function()
  it("falls back to the EP artist for track and album artist", function()
    local t = model.resolve(make_ep(), { title = "Intro", artist = "", isrc = "", composer = "", number = 1, total = 3 })
    assert.are.equal("Clem", t.artist)
    assert.are.equal("Clem", t.album_artist)
  end)

  it("keeps a per-track artist, trims the title and normalizes the ISRC", function()
    local t = model.resolve(make_ep(),
      { title = " Minuit ", artist = "Clem feat. Lea", isrc = "fr-xxx-26-00002", composer = "", number = 2, total = 3 })
    assert.are.equal("Minuit", t.title)
    assert.are.equal("Clem feat. Lea", t.artist)
    assert.are.equal("FRXXX2600002", t.isrc)
  end)
end)

describe("model validators", function()
  it("accepts well-formed ISRC codes only", function()
    assert.is_true(model.is_valid_isrc("FRXXX2600001"))
    assert.is_false(model.is_valid_isrc("FRXX2600001"))
    assert.is_false(model.is_valid_isrc("FRXXX26A0001"))
    assert.is_false(model.is_valid_isrc("12XXX2600001"))
  end)

  it("accepts YYYY and YYYY-MM-DD years", function()
    assert.is_true(model.is_valid_year("2026"))
    assert.is_true(model.is_valid_year("2026-09-25"))
    assert.is_false(model.is_valid_year("26"))
    assert.is_false(model.is_valid_year(""))
    assert.is_false(model.is_valid_year("2026/09/25"))
  end)
end)

describe("model file names", function()
  it("replaces characters that are illegal or special for REAPER", function()
    assert.are.equal("AC-DC- Live-", model.sanitize_filename("AC/DC: Live?"))
    assert.are.equal("Ca-h", model.sanitize_filename("Ca$h"))
    assert.are.equal("a-b", model.sanitize_filename("a;b"))
    assert.are.equal("Outro", model.sanitize_filename("  Outro. "))
    assert.are.equal("untitled", model.sanitize_filename("   "))
  end)

  it("expands known tokens and leaves unknown ones", function()
    local name = model.format_filename("{nn} - {artist} - {title} ({year}) {unknown}",
      { number = 3, title = "Néons", artist = "Clem", album = "Nuits", year = "2026" })
    assert.are.equal("03 - Clem - Néons (2026) {unknown}", name)
  end)

  it("builds the default output folder next to the project", function()
    assert.are.equal("/music/ep/Exports/Nuits- Blanches", model.default_output_dir("/music/ep", "Nuits: Blanches"))
    assert.are.equal("/music/ep/Exports/EP", model.default_output_dir("/music/ep", ""))
    assert.are.equal("", model.default_output_dir("", "Nuits"))
  end)
end)

describe("model.plan_outputs", function()
  it("lists primary and secondary files for included rows only", function()
    local jobs = model.plan_outputs(make_ep(), make_rows({ { "{A}", "Intro" }, { "{B}", "Skip", "", false } }),
      model.default_settings(), "/out")
    assert.are.equal(1, #jobs)
    assert.are.equal("01 - Intro", jobs[1].basename)
    assert.are.same({ "/out/01 - Intro.wav", "/out/01 - Intro.mp3" }, jobs[1].files)
  end)

  it("omits the secondary file when disabled", function()
    local settings = model.default_settings()
    settings.secondary = "none"
    local jobs = model.plan_outputs(make_ep(), make_rows({ { "{A}", "Intro" } }), settings, "/out")
    assert.are.same({ "/out/01 - Intro.wav" }, jobs[1].files)
  end)
end)

describe("model.validate", function()
  local settings = model.default_settings()

  it("passes a complete EP", function()
    local v = model.validate(make_ep(), make_rows({ { "{A}", "Intro", "FRXXX2600001" } }), settings, "/out",
      { file_exists = always })
    assert.are.same({}, v.errors)
    assert.are.same({}, v.warnings)
  end)

  it("blocks an unsaved project without output folder", function()
    local v = model.validate(make_ep(), make_rows({ { "{A}", "Intro", "FRXXX2600001" } }), settings, "",
      { file_exists = always })
    assert.are.equal(1, #v.errors)
    assert.are.equal("settings.output_dir", v.errors[1].field)
  end)

  it("reports missing EP fields, bad ISRC and empty titles", function()
    local v = model.validate(make_ep({ artist = "", year = "26" }), make_rows({ { "{A}", "", "BAD" } }), settings,
      "/out", { file_exists = always })
    local keys = {}
    for _, e in ipairs(v.errors) do keys[#keys + 1] = (e.guid or "") .. e.field end
    table.sort(keys)
    assert.are.same({ "ep.artist", "ep.year", "{A}isrc", "{A}title" }, keys)
  end)

  it("ignores excluded rows and blocks when nothing is included", function()
    local v = model.validate(make_ep(), make_rows({ { "{A}", "", "BAD", false } }), settings, "/out",
      { file_exists = always })
    assert.are.equal(1, #v.errors)
    assert.are.equal("rows", v.errors[1].field)
  end)

  it("detects duplicate file names case-insensitively", function()
    local s = model.default_settings()
    s.pattern = "{title}"
    local v = model.validate(make_ep(),
      make_rows({ { "{A}", "Intro", "FRXXX2600001" }, { "{B}", "INTRO", "FRXXX2600002" } }), s, "/out",
      { file_exists = always })
    assert.are.equal(1, #v.errors)
    assert.are.equal("{B}", v.errors[1].guid)
  end)

  it("warns about a missing ISRC and a missing cover file without blocking", function()
    local v = model.validate(make_ep({ cover = "/missing.jpg" }), make_rows({ { "{A}", "Intro", "" } }), settings,
      "/out", { file_exists = function() return false end })
    assert.are.same({}, v.errors)
    assert.are.equal(2, #v.warnings)
  end)

  it("finds the issue for a given row and field", function()
    local v = model.validate(make_ep(), make_rows({ { "{A}", "Intro", "BAD" } }), settings, "/out",
      { file_exists = always })
    assert.is_truthy(model.issue_for(v.errors, "{A}", "isrc"))
    assert.is_nil(model.issue_for(v.errors, "{A}", "title"))
  end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `busted tests/model_spec.lua`
Expected: FAIL with `module 'release_exporter.model' not found`.

- [ ] **Step 3: Implement `release_exporter/model.lua`**

```lua
-- Pure data model: EP and track fields, fallbacks, numbering, validation and file names.
-- Must never reference the `reaper` API so it stays testable outside REAPER.
local M = {}

M.FORMAT_EXT = { wav16 = "wav", wav24 = "wav", mp3_320 = "mp3", flac = "flac" }
M.FORMAT_LABELS = { wav24 = "WAV 24-bit", wav16 = "WAV 16-bit", mp3_320 = "MP3 320 kbps", flac = "FLAC", none = "None" }

function M.new_ep()
  return { artist = "", album_artist = "", album = "", year = "", genre = "", label = "", copyright = "", cover = "" }
end

function M.default_track()
  return { include = true, artist = "", isrc = "", composer = "" }
end

function M.default_settings()
  return { output_dir = "", pattern = "{nn} - {title}", primary = "wav24", secondary = "mp3_320", srate = 0 }
end

function M.blank(s)
  return s == nil or s:match("^%s*$") ~= nil
end

local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

function M.build_rows(regions, track_data)
  local rows = {}
  for _, rgn in ipairs(regions) do
    local data = track_data[rgn.guid] or {}
    local row = { guid = rgn.guid, title = rgn.name, start = rgn.start, stop = rgn.stop, duration = rgn.stop - rgn.start }
    for key, default in pairs(M.default_track()) do
      if data[key] == nil then row[key] = default else row[key] = data[key] end
    end
    rows[#rows + 1] = row
  end
  table.sort(rows, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.guid < b.guid
  end)
  local total = 0
  for _, row in ipairs(rows) do
    if row.include then total = total + 1 end
  end
  local n = 0
  for _, row in ipairs(rows) do
    if row.include then
      n = n + 1
      row.number, row.total = n, total
    end
  end
  return rows
end

function M.normalize_isrc(s)
  return ((s or ""):upper():gsub("[%s%-]", ""))
end

function M.is_valid_isrc(s)
  return s:match("^%u%u[%u%d][%u%d][%u%d]%d%d%d%d%d%d%d$") ~= nil
end

function M.is_valid_year(s)
  return s:match("^%d%d%d%d$") ~= nil or s:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

function M.resolve(ep, row)
  local artist = trim(ep.artist)
  return {
    title = trim(row.title),
    artist = M.blank(row.artist) and artist or trim(row.artist),
    album_artist = M.blank(ep.album_artist) and artist or trim(ep.album_artist),
    album = trim(ep.album),
    year = trim(ep.year),
    genre = trim(ep.genre),
    label = trim(ep.label),
    copyright = trim(ep.copyright),
    cover = trim(ep.cover),
    isrc = M.normalize_isrc(row.isrc),
    composer = trim(row.composer),
    number = row.number,
    total = row.total,
  }
end

-- `$` would be read as a REAPER wildcard and `;` separates RENDER_TARGETS entries.
function M.sanitize_filename(name)
  local s = (name or ""):gsub('[/\\:%*%?"<>|%$;%c]', "-")
  s = s:gsub("^%s+", ""):gsub("[%s%.]+$", "")
  if s == "" then return "untitled" end
  return s
end

function M.format_filename(pattern, resolved)
  local values = {
    nn = string.format("%02d", resolved.number or 0),
    n = tostring(resolved.number or 0),
    title = resolved.title,
    artist = resolved.artist,
    album = resolved.album,
    year = resolved.year,
  }
  local name = pattern:gsub("{(%w+)}", function(key) return values[key] end)
  return M.sanitize_filename(name)
end

function M.default_output_dir(project_dir, album)
  if M.blank(project_dir) then return "" end
  local folder = M.blank(album) and "EP" or M.sanitize_filename(album)
  return project_dir .. "/Exports/" .. folder
end

function M.plan_outputs(ep, rows, settings, output_dir)
  local jobs = {}
  for _, row in ipairs(rows) do
    if row.include then
      local resolved = M.resolve(ep, row)
      local basename = M.format_filename(settings.pattern, resolved)
      local files = { output_dir .. "/" .. basename .. "." .. M.FORMAT_EXT[settings.primary] }
      local secondary_ext = M.FORMAT_EXT[settings.secondary]
      if secondary_ext then files[#files + 1] = output_dir .. "/" .. basename .. "." .. secondary_ext end
      jobs[#jobs + 1] = {
        guid = row.guid, title = resolved.title, start = row.start, stop = row.stop,
        resolved = resolved, basename = basename, files = files,
      }
    end
  end
  return jobs
end

function M.validate(ep, rows, settings, output_dir, opts)
  opts = opts or {}
  local errors, warnings = {}, {}
  local function err(field, message, guid) errors[#errors + 1] = { field = field, message = message, guid = guid } end
  local function warn(field, message, guid) warnings[#warnings + 1] = { field = field, message = message, guid = guid } end

  if M.blank(ep.artist) then err("ep.artist", "Artist is required.") end
  if M.blank(ep.album) then err("ep.album", "EP title is required.") end
  if not M.is_valid_year(trim(ep.year)) then err("ep.year", "Year must be YYYY or YYYY-MM-DD.") end
  if M.blank(ep.cover) then
    warn("ep.cover", "No cover image.")
  elseif opts.file_exists and not opts.file_exists(trim(ep.cover)) then
    warn("ep.cover", "Cover image not found; it will be skipped.")
  end
  if M.blank(output_dir) then err("settings.output_dir", "Save the project or choose an output folder.") end

  local included = 0
  for _, row in ipairs(rows) do
    if row.include then
      included = included + 1
      if M.blank(row.title) then err("title", "Title is required.", row.guid) end
      local isrc = M.normalize_isrc(row.isrc)
      if isrc == "" then
        warn("isrc", "No ISRC.", row.guid)
      elseif not M.is_valid_isrc(isrc) then
        err("isrc", "ISRC must look like FRXXX2600001.", row.guid)
      end
    end
  end
  if included == 0 then err("rows", "No region is included in the export.") end

  local seen = {}
  for _, job in ipairs(M.plan_outputs(ep, rows, settings, output_dir)) do
    local key = job.basename:lower()
    if seen[key] then err("title", 'Duplicate file name "' .. job.basename .. '".', job.guid) end
    seen[key] = true
  end
  return { errors = errors, warnings = warnings }
end

function M.issue_for(issues, guid, field)
  for _, issue in ipairs(issues) do
    if issue.guid == guid and issue.field == field then return issue.message end
  end
end

return M
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted tests/model_spec.lua && luacheck release_exporter tests`
Expected: all specs pass, `0 warnings / 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add release_exporter/model.lua tests/model_spec.lua
git commit -m "feat(model): add EP/track model with fallbacks, validation and file names

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `metadata_mapper` — resolved track to REAPER tags

**Files:**
- Create: `release_exporter/metadata_mapper.lua`
- Test: `tests/metadata_mapper_spec.lua`

**Interfaces:**
- Consumes: `resolved` shape from `model.resolve` (Task 3). Confirmed identifiers from `docs/reaper-api-notes.md` (Task 2).
- Produces: `mapper.FIELDS` (array of `{ key, ID3?, VORBIS?, INFO? }`), `mapper.COVER_KEYS` (array of full ids, e.g. `"ID3:APIC_FILE"`), `mapper.build(resolved) -> { "SCHEME:TAG|value", ... }` (empty values skipped).

- [ ] **Step 1: Align the tables with Task 2 findings**

Open `docs/reaper-api-notes.md`. If an identifier differs from the table below (for example, `TDRC` instead of `TYER`, or an extra image key for FLAC), use the confirmed one in **both** the implementation and the test.

- [ ] **Step 2: Write the failing tests**

`tests/metadata_mapper_spec.lua`:

```lua
local mapper = require("release_exporter.metadata_mapper")

local function track(overrides)
  local t = {
    title = "Intro", artist = "Clem", album_artist = "Clem", album = "Nuits", year = "2026", genre = "Electro",
    label = "Indie", copyright = "(P) 2026 Clem", cover = "/art/cover.jpg", isrc = "FRXXX2600001",
    composer = "C. D.", number = 1, total = 4,
  }
  for k, v in pairs(overrides or {}) do t[k] = v end
  return t
end

local function as_set(list)
  local set = {}
  for _, entry in ipairs(list) do set[entry] = true end
  return set
end

local function has_prefix(list, prefix)
  for _, entry in ipairs(list) do
    if entry:sub(1, #prefix) == prefix then return true end
  end
  return false
end

describe("metadata_mapper.build", function()
  it("writes every scheme for a complete track", function()
    local set = as_set(mapper.build(track()))
    for _, expected in ipairs({
      "ID3:TIT2|Intro", "VORBIS:TITLE|Intro", "INFO:INAM|Intro",
      "ID3:TPE1|Clem", "ID3:TPE2|Clem", "ID3:TALB|Nuits", "VORBIS:ALBUM|Nuits",
      "ID3:TRCK|1/4", "VORBIS:TRACKNUMBER|1", "VORBIS:TRACKTOTAL|4", "INFO:ITRK|1",
      "ID3:TSRC|FRXXX2600001", "VORBIS:ISRC|FRXXX2600001", "VORBIS:ORGANIZATION|Indie",
      "ID3:TCOM|C. D.", "ID3:APIC_TYPE|3",
    }) do
      assert.is_true(set[expected] == true, expected)
    end
  end)

  it("uses every configured cover key", function()
    local set = as_set(mapper.build(track()))
    for _, key in ipairs(mapper.COVER_KEYS) do
      assert.is_true(set[key .. "|/art/cover.jpg"] == true, key)
    end
  end)

  it("skips empty values", function()
    local list = mapper.build(track({ isrc = "", composer = "", cover = "" }))
    assert.is_false(has_prefix(list, "ID3:TSRC"))
    assert.is_false(has_prefix(list, "ID3:TCOM"))
    assert.is_false(has_prefix(list, "ID3:APIC"))
  end)

  it("keeps values containing separators intact", function()
    assert.is_true(as_set(mapper.build(track({ title = "A|B; C" })))["ID3:TIT2|A|B; C"])
  end)
end)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `busted tests/metadata_mapper_spec.lua`
Expected: FAIL with `module 'release_exporter.metadata_mapper' not found`.

- [ ] **Step 4: Implement `release_exporter/metadata_mapper.lua`**

```lua
-- Pure: turns a resolved track (see model.resolve) into REAPER RENDER_METADATA entries.
-- Every scheme is written explicitly so we never rely on REAPER's implicit cross-scheme mapping.
-- Identifiers are confirmed in docs/reaper-api-notes.md.
local M = {}

M.SCHEMES = { "ID3", "VORBIS", "INFO" }

M.FIELDS = {
  { key = "title", ID3 = "TIT2", VORBIS = "TITLE", INFO = "INAM" },
  { key = "artist", ID3 = "TPE1", VORBIS = "ARTIST", INFO = "IART" },
  { key = "album_artist", ID3 = "TPE2", VORBIS = "ALBUMARTIST" },
  { key = "album", ID3 = "TALB", VORBIS = "ALBUM", INFO = "IPRD" },
  { key = "year", ID3 = "TYER", VORBIS = "DATE", INFO = "ICRD" },
  { key = "genre", ID3 = "TCON", VORBIS = "GENRE", INFO = "IGNR" },
  { key = "label", ID3 = "TPUB", VORBIS = "ORGANIZATION" },
  { key = "copyright", ID3 = "TCOP", VORBIS = "COPYRIGHT", INFO = "ICOP" },
  { key = "isrc", ID3 = "TSRC", VORBIS = "ISRC" },
  { key = "composer", ID3 = "TCOM", VORBIS = "COMPOSER" },
}

M.COVER_KEYS = { "ID3:APIC_FILE" }

function M.build(t)
  local out = {}
  local function add(id, value)
    if value ~= nil and value ~= "" then out[#out + 1] = id .. "|" .. value end
  end
  for _, field in ipairs(M.FIELDS) do
    for _, scheme in ipairs(M.SCHEMES) do
      if field[scheme] then add(scheme .. ":" .. field[scheme], t[field.key]) end
    end
  end
  if t.number then
    add("ID3:TRCK", t.number .. "/" .. t.total)
    add("VORBIS:TRACKNUMBER", tostring(t.number))
    add("VORBIS:TRACKTOTAL", tostring(t.total))
    add("INFO:ITRK", tostring(t.number))
  end
  if t.cover and t.cover ~= "" then
    for _, id in ipairs(M.COVER_KEYS) do add(id, t.cover) end
    add("ID3:APIC_TYPE", "3")
  end
  return out
end

return M
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `busted && luacheck release_exporter tests`
Expected: all specs pass, `0 warnings / 0 errors`.

- [ ] **Step 6: Commit**

```bash
git add release_exporter/metadata_mapper.lua tests/metadata_mapper_spec.lua
git commit -m "feat(metadata): map resolved tracks to ID3, Vorbis and INFO tags

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Fake REAPER, `regions` and `project_store` adapters

**Files:**
- Create: `tests/support/fake_reaper.lua`, `release_exporter/regions.lua`, `release_exporter/project_store.lua`
- Test: `tests/regions_spec.lua`, `tests/project_store_spec.lua`

**Interfaces:**
- Consumes: `model.new_ep`, `model.default_track`, `model.default_settings` (Task 3), `vendor/json` (Task 1).
- Produces:
  - `fake.new() -> r`. This is the REAPER API subset plus the test helpers `r.add_region(start, stop, name) -> number`, `r.add_marker(pos, name)`, `r.remove_region(guid) -> marker`, `r.restore_marker(marker)`, `r.markers() -> list`, `r.switch_project()`, `r.metadata() -> map`. Fields: `r.proj`, `r.projfn`, `r.change_count`, `r.dirty`, `r.undo_points`, `r.selected_items` (array of `{ pos, len, take = { name } | nil }`).
  - `regions.list(r, proj) -> { { guid, index, number, name, start, stop, color }, ... }` (regions only, in enumeration order)
  - `regions.rename(r, proj, guid, name) -> boolean` (one undo point)
  - `regions.create_from_selected_items(r, proj) -> count` (one undo point)
  - `store.EXT = "ReleaseExporter"`, `store.load(r, proj) -> { ep, settings, tracks }`, `store.save_ep(r, proj, ep)`, `store.save_track(r, proj, guid, data)`, `store.save_settings(r, proj, settings)`

- [ ] **Step 1: Write the fake REAPER API**

`tests/support/fake_reaper.lua`:

```lua
-- In-memory stand-in for the subset of the REAPER API that release_exporter uses.
local M = {}

local FORMAT_EXT = { evaw = "wav", l3pm = "mp3", calf = "flac" }

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function M.new()
  local r = {}
  local projects = {}
  local num, str, metadata, global_ext = {}, {}, {}, {}
  local next_id = 0

  local function state(proj)
    projects[proj] = projects[proj] or { markers = {}, ext = {} }
    return projects[proj]
  end

  r.proj = { id = 1 }
  r.projfn = "/music/ep/EP.rpp"
  r.change_count = 0
  r.dirty = 0
  r.undo_points = {}
  r.commands = {}
  r.selected_items = {}
  r.render_behavior = "ok" -- "ok" | "missing" | "error", or function(call_index) returning one of them
  r.os = "OSX64"

  local function touch() r.change_count = r.change_count + 1 end
  local function markers() return state(r.proj).markers end
  local function sort() table.sort(markers(), function(a, b) return a.start < b.start end) end

  local function add(isrgn, start, stop, name)
    next_id = next_id + 1
    local list = markers()
    list[#list + 1] = {
      isrgn = isrgn, start = start, stop = stop, name = name, number = next_id, color = 0,
      guid = string.format("{%08X-0000-0000-0000-000000000000}", next_id),
    }
    sort()
    touch()
    return next_id
  end

  -- Test helpers
  function r.add_region(start, stop, name) return add(true, start, stop, name) end
  function r.add_marker(pos, name) return add(false, pos, pos, name) end
  function r.markers() return markers() end
  function r.metadata() return metadata end
  function r.remove_region(guid)
    for i, m in ipairs(markers()) do
      if m.guid == guid then
        table.remove(markers(), i)
        touch()
        return m
      end
    end
  end
  function r.restore_marker(marker)
    local list = markers()
    list[#list + 1] = marker
    sort()
    touch()
  end
  function r.switch_project()
    r.proj = { id = r.proj.id + 1 }
    r.projfn = "/music/other/Other.rpp"
  end

  -- Projects and markers
  function r.EnumProjects(idx)
    if idx == -1 then return r.proj, r.projfn end
  end
  function r.GetProjectStateChangeCount() return r.change_count end
  function r.CountProjectMarkers(proj)
    local list, regions = state(proj).markers, 0
    for _, m in ipairs(list) do
      if m.isrgn then regions = regions + 1 end
    end
    return #list, #list - regions, regions
  end
  function r.EnumProjectMarkers3(proj, idx)
    local m = state(proj).markers[idx + 1]
    if not m then return 0, false, 0, 0, "", 0, 0 end
    return idx + 1, m.isrgn, m.start, m.stop, m.name, m.number, m.color
  end
  function r.SetProjectMarkerByIndex2(proj, idx, isrgn, pos, stop, number, name, color, flags)
    local m = state(proj).markers[idx + 1]
    if not m then return false end
    m.isrgn, m.start, m.stop, m.number, m.color = isrgn, pos, stop, number, color
    if flags & 1 == 1 then m.name = "" elseif name ~= "" then m.name = name end
    sort()
    touch()
    return true
  end
  function r.AddProjectMarker2(_, isrgn, pos, stop, name) return add(isrgn, pos, stop, name) end

  -- Project info
  function r.GetSetProjectInfo(_, key, value, is_set)
    if is_set then num[key] = value end
    return num[key] or 0
  end
  function r.render_targets()
    local out = {}
    for _, key in ipairs({ "RENDER_FORMAT", "RENDER_FORMAT2" }) do
      -- Base64 configs captured in Task 2 are opaque here: treat any unknown primary as WAV, secondary as MP3.
      local value = str[key] or ""
      local ext = FORMAT_EXT[value] or (value ~= "" and (key == "RENDER_FORMAT" and "wav" or "mp3")) or nil
      if ext then out[#out + 1] = (str.RENDER_FILE or "") .. "/" .. (str.RENDER_PATTERN or "") .. "." .. ext end
    end
    return out
  end
  function r.GetSetProjectInfo_String(proj, key, value, is_set)
    local idx = key:match("^MARKER_GUID:(%d+)$")
    if idx then
      local m = state(proj).markers[tonumber(idx) + 1]
      return m ~= nil, m and m.guid or ""
    end
    if key == "RENDER_METADATA" then
      if is_set then
        local id, v = value:match("^([^|]+)|(.*)$")
        metadata[id] = v ~= "" and v or nil
        return true, value
      elseif value == "" then
        local ids = {}
        for id in pairs(metadata) do ids[#ids + 1] = id end
        table.sort(ids)
        return true, table.concat(ids, ";")
      end
      return true, metadata[value] or ""
    end
    if key == "RENDER_TARGETS" then return true, table.concat(r.render_targets(), ";") end
    if is_set then str[key] = value end
    return true, str[key] or ""
  end

  -- Ext state
  function r.SetProjExtState(proj, section, key, value)
    local ext = state(proj).ext
    ext[section] = ext[section] or {}
    ext[section][key] = value ~= "" and value or nil
    return 0
  end
  function r.GetProjExtState(proj, section, key)
    local v = state(proj).ext[section] and state(proj).ext[section][key]
    return v and 1 or 0, v or ""
  end
  function r.EnumProjExtState(proj, section, idx)
    local values = state(proj).ext[section] or {}
    local keys = {}
    for k in pairs(values) do keys[#keys + 1] = k end
    table.sort(keys)
    local k = keys[idx + 1]
    if not k then return false end
    return true, k, values[k]
  end
  function r.SetExtState(section, key, value) global_ext[section .. "/" .. key] = value end
  function r.GetExtState(section, key) return global_ext[section .. "/" .. key] or "" end

  -- Undo, dirty
  function r.MarkProjectDirty() r.dirty = r.dirty + 1 end
  function r.Undo_BeginBlock2() end
  function r.Undo_EndBlock2(_, desc) r.undo_points[#r.undo_points + 1] = desc end

  -- Rendering and files
  function r.Main_OnCommand(cmd)
    r.commands[#r.commands + 1] = {
      cmd = cmd, pattern = str.RENDER_PATTERN, metadata = copy(metadata),
      bounds = { num.RENDER_STARTPOS, num.RENDER_ENDPOS }, boundsflag = num.RENDER_BOUNDSFLAG,
      settings = num.RENDER_SETTINGS, addtoproj = num.RENDER_ADDTOPROJ,
    }
    local behavior = r.render_behavior
    if type(behavior) == "function" then behavior = behavior(#r.commands) end
    if behavior == "error" then error("render exploded") end
    if behavior == "ok" then
      for _, path in ipairs(r.render_targets()) do
        local f = assert(io.open(path, "wb"))
        f:write("RIFF")
        f:close()
      end
    end
  end
  function r.RecursiveCreateDirectory(path)
    return os.execute('mkdir -p "' .. path .. '" 2>/dev/null') and 1 or 0
  end
  function r.file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
  end
  function r.GetOS() return r.os end

  -- Media items
  function r.CountSelectedMediaItems() return #r.selected_items end
  function r.GetSelectedMediaItem(_, i) return r.selected_items[i + 1] end
  function r.GetMediaItemInfo_Value(item, key)
    if key == "D_POSITION" then return item.pos end
    if key == "D_LENGTH" then return item.len end
    return 0
  end
  function r.GetActiveTake(item) return item.take end
  function r.GetTakeName(take) return take.name end

  return r
end

return M
```

- [ ] **Step 2: Write the failing adapter tests**

`tests/regions_spec.lua`:

```lua
local fake = require("tests.support.fake_reaper")
local regions = require("release_exporter.regions")

describe("regions.list", function()
  it("returns regions with GUIDs in position order and skips markers", function()
    local r = fake.new()
    r.add_region(10, 20, "B")
    r.add_region(0, 10, "A")
    r.add_marker(5, "cue")
    local list = regions.list(r, r.proj)
    assert.are.equal(2, #list)
    assert.are.same({ "A", "B" }, { list[1].name, list[2].name })
    assert.is_truthy(list[1].guid:match("^{.+}$"))
  end)
end)

describe("regions.rename", function()
  it("renames by GUID with a single undo point", function()
    local r = fake.new()
    r.add_region(0, 10, "Old")
    local guid = regions.list(r, r.proj)[1].guid
    assert.is_true(regions.rename(r, r.proj, guid, "New"))
    assert.are.equal("New", r.markers()[1].name)
    assert.are.equal(1, #r.undo_points)
  end)

  it("can clear a name", function()
    local r = fake.new()
    r.add_region(0, 10, "Old")
    regions.rename(r, r.proj, regions.list(r, r.proj)[1].guid, "")
    assert.are.equal("", r.markers()[1].name)
  end)

  it("returns false for an unknown GUID", function()
    local r = fake.new()
    assert.is_false(regions.rename(r, r.proj, "{nope}", "X"))
    assert.are.equal(0, #r.undo_points)
  end)
end)

describe("regions.create_from_selected_items", function()
  it("creates one region per item, named after the take without extension", function()
    local r = fake.new()
    r.selected_items = {
      { pos = 0, len = 180, take = { name = "Intro.wav" } },
      { pos = 190, len = 200, take = { name = "Minuit.rpp" } },
      { pos = 400, len = 10 },
    }
    assert.are.equal(3, regions.create_from_selected_items(r, r.proj))
    local list = regions.list(r, r.proj)
    assert.are.same({ "Intro", "Minuit", "" }, { list[1].name, list[2].name, list[3].name })
    assert.are.equal(390, list[2].stop)
    assert.are.equal(1, #r.undo_points)
  end)

  it("does nothing without a selection", function()
    local r = fake.new()
    assert.are.equal(0, regions.create_from_selected_items(r, r.proj))
    assert.are.equal(0, #r.undo_points)
  end)
end)
```

`tests/project_store_spec.lua`:

```lua
local fake = require("tests.support.fake_reaper")
local store = require("release_exporter.project_store")
local model = require("release_exporter.model")

describe("project_store", function()
  it("returns defaults for a fresh project", function()
    local r = fake.new()
    local data = store.load(r, r.proj)
    assert.are.same(model.new_ep(), data.ep)
    assert.are.same(model.default_settings(), data.settings)
    assert.are.same({}, data.tracks)
  end)

  it("round-trips EP, tracks and settings and marks the project dirty", function()
    local r = fake.new()
    local ep = model.new_ep()
    ep.artist = "Clem"
    store.save_ep(r, r.proj, ep)
    store.save_track(r, r.proj, "{A}", { include = false, artist = "X", isrc = "FRXXX2600001", composer = "" })
    local settings = model.default_settings()
    settings.pattern, settings.output_dir = "{title}", "/out"
    store.save_settings(r, r.proj, settings)

    local data = store.load(r, r.proj)
    assert.are.equal("Clem", data.ep.artist)
    assert.is_false(data.tracks["{A}"].include)
    assert.are.equal("{title}", data.settings.pattern)
    assert.are.equal("/out", data.settings.output_dir)
    assert.are.equal(3, r.dirty)
  end)

  it("uses the last settings as defaults for a new project, without the folder", function()
    local r = fake.new()
    local settings = model.default_settings()
    settings.secondary, settings.output_dir = "flac", "/old/out"
    store.save_settings(r, r.proj, settings)
    r.switch_project()

    local data = store.load(r, r.proj)
    assert.are.equal("flac", data.settings.secondary)
    assert.are.equal("", data.settings.output_dir)
  end)

  it("falls back field by field on corrupted or mistyped data", function()
    local r = fake.new()
    r.SetProjExtState(r.proj, store.EXT, "ep", "{not json")
    r.SetProjExtState(r.proj, store.EXT, "settings", '{"pattern":42,"secondary":"flac"}')
    r.SetProjExtState(r.proj, store.EXT, "track:{A}", "[]")

    local data = store.load(r, r.proj)
    assert.are.same(model.new_ep(), data.ep)
    assert.are.equal("{nn} - {title}", data.settings.pattern)
    assert.are.equal("flac", data.settings.secondary)
    assert.is_true(data.tracks["{A}"].include)
  end)

  it("reads track keys regardless of case", function()
    local r = fake.new()
    r.SetProjExtState(r.proj, store.EXT, "TRACK:{A}", '{"isrc":"FRXXX2600001"}')
    assert.are.equal("FRXXX2600001", store.load(r, r.proj).tracks["{A}"].isrc)
  end)
end)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `busted tests/regions_spec.lua tests/project_store_spec.lua`
Expected: FAIL with `module 'release_exporter.regions' not found` and `module 'release_exporter.project_store' not found`.

- [ ] **Step 4: Implement `release_exporter/regions.lua`**

```lua
-- REAPER adapter for project regions. Takes the API table `r` so it can run against tests/support/fake_reaper.lua.
local M = {}

local function guid_at(r, proj, idx)
  local ok, guid = r.GetSetProjectInfo_String(proj, "MARKER_GUID:" .. idx, "", false)
  if ok and guid ~= "" then return guid end
end

function M.list(r, proj)
  local out = {}
  local total = r.CountProjectMarkers(proj)
  for idx = 0, total - 1 do
    local rv, isrgn, pos, rgnend, name, number, color = r.EnumProjectMarkers3(proj, idx)
    if rv > 0 and isrgn then
      local guid = guid_at(r, proj, idx)
      if guid then
        out[#out + 1] = { guid = guid, index = idx, number = number, name = name, start = pos, stop = rgnend, color = color }
      end
    end
  end
  return out
end

function M.rename(r, proj, guid, name)
  for _, rgn in ipairs(M.list(r, proj)) do
    if rgn.guid == guid then
      r.Undo_BeginBlock2(proj)
      local flags = name == "" and 1 or 0
      r.SetProjectMarkerByIndex2(proj, rgn.index, true, rgn.start, rgn.stop, rgn.number, name, rgn.color, flags)
      r.Undo_EndBlock2(proj, "Release Exporter: rename region", -1)
      return true
    end
  end
  return false
end

function M.create_from_selected_items(r, proj)
  local count = r.CountSelectedMediaItems(proj)
  if count == 0 then return 0 end
  r.Undo_BeginBlock2(proj)
  for i = 0, count - 1 do
    local item = r.GetSelectedMediaItem(proj, i)
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local take = r.GetActiveTake(item)
    local name = take and r.GetTakeName(take) or ""
    name = name:gsub("%.%w+$", "")
    r.AddProjectMarker2(proj, true, pos, pos + len, name, -1, 0)
  end
  r.Undo_EndBlock2(proj, "Release Exporter: create regions from items", -1)
  return count
end

return M
```

- [ ] **Step 5: Implement `release_exporter/project_store.lua`**

```lua
-- REAPER adapter: persists EP, track and settings data in the project (ProjExtState) as JSON.
local json = require("release_exporter.vendor.json")
local model = require("release_exporter.model")

local M = {}

M.EXT = "ReleaseExporter"
M.SCHEMA_VERSION = "1"

local function decode(s)
  if s == nil or s == "" then return nil end
  local ok, value = pcall(json.decode, s)
  if ok and type(value) == "table" then return value end
end

-- Keeps only known keys whose type matches the default, so bad data degrades field by field.
local function merge(defaults, data)
  local out = {}
  for key, default in pairs(defaults) do
    local value = data and data[key]
    if value ~= nil and type(value) == type(default) then out[key] = value else out[key] = default end
  end
  return out
end

function M.load(r, proj)
  local _, ep = r.GetProjExtState(proj, M.EXT, "ep")
  local _, settings = r.GetProjExtState(proj, M.EXT, "settings")

  local loaded_settings
  local project_settings = decode(settings)
  if project_settings then
    loaded_settings = merge(model.default_settings(), project_settings)
  else
    loaded_settings = merge(model.default_settings(), decode(r.GetExtState(M.EXT, "default_settings")))
    loaded_settings.output_dir = ""
  end

  local tracks = {}
  local idx = 0
  while true do
    local ok, key, value = r.EnumProjExtState(proj, M.EXT, idx)
    if not ok then break end
    if key:lower():sub(1, 6) == "track:" then
      tracks[key:sub(7)] = merge(model.default_track(), decode(value))
    end
    idx = idx + 1
  end

  return { ep = merge(model.new_ep(), decode(ep)), settings = loaded_settings, tracks = tracks }
end

local function save(r, proj, key, value)
  r.SetProjExtState(proj, M.EXT, "schema_version", M.SCHEMA_VERSION)
  r.SetProjExtState(proj, M.EXT, key, json.encode(value))
  r.MarkProjectDirty(proj)
end

function M.save_ep(r, proj, ep)
  save(r, proj, "ep", ep)
end

function M.save_track(r, proj, guid, data)
  save(r, proj, "track:" .. guid, data)
end

function M.save_settings(r, proj, settings)
  save(r, proj, "settings", settings)
  r.SetExtState(M.EXT, "default_settings", json.encode(settings), true)
end

return M
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `busted && luacheck .`
Expected: all specs pass, `0 warnings / 0 errors`.

- [ ] **Step 7: Commit**

```bash
git add tests/support release_exporter/regions.lua release_exporter/project_store.lua tests/regions_spec.lua tests/project_store_spec.lua
git commit -m "feat(project): add region and project storage adapters with a fake REAPER API

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `fs` and `renderer` — render per region and always restore

**Files:**
- Create: `release_exporter/fs.lua`, `release_exporter/renderer.lua`
- Test: `tests/fs_spec.lua`, `tests/renderer_spec.lua`

**Interfaces:**
- Consumes: `fake.new()` (Task 5), job shape from `model.plan_outputs` (Task 3) plus a `tags` field (a `mapper.build` list, Task 4).
- Produces:
  - `fs.exists(path) -> boolean`, `fs.size(path) -> integer`, `fs.remove(path)`, `fs.ensure_dir(r, path) -> boolean` (creates the folder and checks it is writable), `fs.open_folder(r, path)`
  - `renderer.RENDER_COMMAND = 42230`
  - `renderer.render(r, proj, jobs, opts) -> report`. Each job is `{ title, basename, start, stop, tags }`. `opts` is `{ output_dir, primary_format, secondary_format, srate }`. The report is `{ items = { { title, ok, files, error? } }, error? }`.
  - `renderer.snapshot(r, proj) -> state`, `renderer.restore(r, proj, state)`

- [ ] **Step 1: Write the failing tests**

`tests/fs_spec.lua`:

```lua
local fake = require("tests.support.fake_reaper")
local fs = require("release_exporter.fs")

describe("fs.ensure_dir", function()
  it("creates nested folders and reports them writable", function()
    local base = os.tmpname()
    os.remove(base)
    local dir = base .. "/a/b"
    assert.is_true(fs.ensure_dir(fake.new(), dir))
    assert.is_false(fs.exists(dir .. "/.release_exporter_probe"))
  end)

  it("returns false when the folder cannot be created", function()
    assert.is_false(fs.ensure_dir(fake.new(), "/dev/null/nope"))
  end)
end)
```

`tests/renderer_spec.lua`:

```lua
local fake = require("tests.support.fake_reaper")
local renderer = require("release_exporter.renderer")
local fs = require("release_exporter.fs")

local function tmpdir()
  local path = os.tmpname()
  os.remove(path)
  os.execute('mkdir -p "' .. path .. '"')
  return path
end

local function job(basename, start, stop)
  return { title = basename, basename = basename, start = start, stop = stop, tags = { "ID3:TIT2|" .. basename } }
end

local USER_SETTINGS = 8 | 1024 -- render matrix + embed take markers

local function user_setup(r)
  r.GetSetProjectInfo(r.proj, "RENDER_SETTINGS", USER_SETTINGS, true)
  r.GetSetProjectInfo(r.proj, "RENDER_BOUNDSFLAG", 3, true)
  r.GetSetProjectInfo(r.proj, "RENDER_ADDTOPROJ", 1, true)
  r.GetSetProjectInfo_String(r.proj, "RENDER_FILE", "/user/dir", true)
  r.GetSetProjectInfo_String(r.proj, "RENDER_PATTERN", "$project", true)
  r.GetSetProjectInfo_String(r.proj, "RENDER_FORMAT", "evaw", true)
  r.GetSetProjectInfo_String(r.proj, "RENDER_METADATA", "ID3:TIT2|$region", true)
  r.GetSetProjectInfo_String(r.proj, "RENDER_METADATA", "ID3:COMM|user comment", true)
end

local function assert_user_setup(r)
  assert.are.equal(USER_SETTINGS, r.GetSetProjectInfo(r.proj, "RENDER_SETTINGS", 0, false))
  assert.are.equal(3, r.GetSetProjectInfo(r.proj, "RENDER_BOUNDSFLAG", 0, false))
  assert.are.equal(1, r.GetSetProjectInfo(r.proj, "RENDER_ADDTOPROJ", 0, false))
  assert.are.same({ true, "/user/dir" }, { r.GetSetProjectInfo_String(r.proj, "RENDER_FILE", "", false) })
  assert.are.same({ true, "$project" }, { r.GetSetProjectInfo_String(r.proj, "RENDER_PATTERN", "", false) })
  assert.are.same({ true, "evaw" }, { r.GetSetProjectInfo_String(r.proj, "RENDER_FORMAT", "", false) })
  assert.are.same({ true, "" }, { r.GetSetProjectInfo_String(r.proj, "RENDER_FORMAT2", "", false) })
  assert.are.same({ ["ID3:TIT2"] = "$region", ["ID3:COMM"] = "user comment" }, r.metadata())
end

describe("renderer.render", function()
  local opts

  before_each(function()
    opts = { output_dir = tmpdir(), primary_format = "evaw", secondary_format = "l3pm", srate = 0 }
  end)

  it("renders each job with its own bounds, name and only its own metadata", function()
    local r = fake.new()
    user_setup(r)
    local report = renderer.render(r, r.proj, { job("01 - Intro", 0, 10), job("02 - Minuit", 10, 25) }, opts)
    assert.are.equal(2, #r.commands)
    assert.are.equal(42230, r.commands[1].cmd)
    assert.are.equal("01 - Intro", r.commands[1].pattern)
    assert.are.same({ 10, 25 }, r.commands[2].bounds)
    assert.are.same({ ["ID3:TIT2"] = "02 - Minuit" }, r.commands[2].metadata)
    assert.is_true(report.items[1].ok)
    assert.are.same({ opts.output_dir .. "/01 - Intro.wav", opts.output_dir .. "/01 - Intro.mp3" }, report.items[1].files)
  end)

  it("forces master mix, custom bounds, embedded metadata and no add-to-project", function()
    local r = fake.new()
    user_setup(r)
    renderer.render(r, r.proj, { job("01 - Intro", 0, 10) }, opts)
    assert.are.equal(512 | 1024, r.commands[1].settings)
    assert.are.equal(0, r.commands[1].boundsflag)
    assert.are.equal(0, r.commands[1].addtoproj)
  end)

  it("restores the user's render settings and metadata afterwards", function()
    local r = fake.new()
    user_setup(r)
    renderer.render(r, r.proj, { job("01 - Intro", 0, 10) }, opts)
    assert_user_setup(r)
  end)

  it("restores everything even when the render raises an error", function()
    local r = fake.new()
    user_setup(r)
    r.render_behavior = "error"
    local report = renderer.render(r, r.proj, { job("01 - Intro", 0, 10) }, opts)
    assert.is_truthy(report.error:find("render exploded", 1, true))
    assert_user_setup(r)
  end)

  it("reports a missing file and continues with the next job", function()
    local r = fake.new()
    r.render_behavior = function(n) return n == 1 and "missing" or "ok" end
    local report = renderer.render(r, r.proj, { job("01 - Intro", 0, 10), job("02 - Minuit", 10, 25) }, opts)
    assert.is_false(report.items[1].ok)
    assert.is_truthy(report.items[1].error:find("Missing", 1, true))
    assert.is_true(report.items[2].ok)
  end)

  it("deletes stale output files before rendering so REAPER never prompts", function()
    local r = fake.new()
    local stale = opts.output_dir .. "/01 - Intro.wav"
    local f = assert(io.open(stale, "wb"))
    f:write("old")
    f:close()
    r.render_behavior = "missing"
    renderer.render(r, r.proj, { job("01 - Intro", 0, 10) }, opts)
    assert.is_false(fs.exists(stale))
  end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `busted tests/fs_spec.lua tests/renderer_spec.lua`
Expected: FAIL with `module 'release_exporter.fs' not found`.

- [ ] **Step 3: Implement `release_exporter/fs.lua`**

```lua
-- Small file-system helpers built on plain Lua io/os plus the REAPER API where needed.
local M = {}

function M.exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

function M.size(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local size = f:seek("end")
  f:close()
  return size or 0
end

function M.remove(path)
  return os.remove(path)
end

-- Creates the folder, then proves it is writable with a probe file.
function M.ensure_dir(r, path)
  r.RecursiveCreateDirectory(path, 0)
  local probe = path .. "/.release_exporter_probe"
  local f = io.open(probe, "wb")
  if not f then return false end
  f:close()
  os.remove(probe)
  return true
end

function M.open_folder(r, path)
  if r.CF_ShellExecute then return r.CF_ShellExecute(path) end
  local os_name = r.GetOS()
  if os_name:match("^Win") then
    os.execute('start "" "' .. path:gsub("/", "\\") .. '"')
  elseif os_name:match("^OSX") or os_name:match("^macOS") then
    os.execute('open "' .. path .. '"')
  else
    os.execute('xdg-open "' .. path .. '"')
  end
end

return M
```

- [ ] **Step 4: Implement `release_exporter/renderer.lua`**

```lua
-- Drives REAPER's renderer one region at a time, then restores the user's render settings no matter what.
local fs = require("release_exporter.fs")

local M = {}

M.RENDER_COMMAND = 42230 -- File: Render project, using the most recent render settings, auto-close render dialog

M.NUM_KEYS = {
  "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_STARTPOS", "RENDER_ENDPOS", "RENDER_TAILFLAG",
  "RENDER_SRATE", "RENDER_ADDTOPROJ",
}
M.STR_KEYS = { "RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT", "RENDER_FORMAT2" }

-- Bits of RENDER_SETTINGS that select something other than a plain master mix (stems, matrix, items, razor).
local SOURCE_MASK = 1 | 2 | 4 | 8 | 32 | 64 | 128 | 4096
local EMBED_METADATA = 512
local ADD_TO_PROJECT = 1

local function split(s, sep)
  local out = {}
  for part in (s or ""):gmatch("[^" .. sep .. "]+") do out[#out + 1] = part end
  return out
end

local function metadata_ids(r, proj)
  local _, list = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", "", false)
  return split(list, ";")
end

local function clear_metadata(r, proj)
  for _, id in ipairs(metadata_ids(r, proj)) do
    r.GetSetProjectInfo_String(proj, "RENDER_METADATA", id .. "|", true)
  end
end

function M.snapshot(r, proj)
  local state = { num = {}, str = {}, metadata = {} }
  for _, key in ipairs(M.NUM_KEYS) do state.num[key] = r.GetSetProjectInfo(proj, key, 0, false) end
  for _, key in ipairs(M.STR_KEYS) do
    local _, value = r.GetSetProjectInfo_String(proj, key, "", false)
    state.str[key] = value
  end
  for _, id in ipairs(metadata_ids(r, proj)) do
    local _, value = r.GetSetProjectInfo_String(proj, "RENDER_METADATA", id, false)
    state.metadata[#state.metadata + 1] = { id = id, value = value }
  end
  return state
end

function M.restore(r, proj, state)
  for key, value in pairs(state.num) do r.GetSetProjectInfo(proj, key, value, true) end
  for key, value in pairs(state.str) do r.GetSetProjectInfo_String(proj, key, value, true) end
  clear_metadata(r, proj)
  for _, entry in ipairs(state.metadata) do
    r.GetSetProjectInfo_String(proj, "RENDER_METADATA", entry.id .. "|" .. entry.value, true)
  end
end

local function render_one(r, proj, job, opts)
  r.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 0, true)
  r.GetSetProjectInfo(proj, "RENDER_STARTPOS", job.start, true)
  r.GetSetProjectInfo(proj, "RENDER_ENDPOS", job.stop, true)
  r.GetSetProjectInfo(proj, "RENDER_TAILFLAG", 0, true)
  r.GetSetProjectInfo_String(proj, "RENDER_FILE", opts.output_dir, true)
  r.GetSetProjectInfo_String(proj, "RENDER_PATTERN", job.basename, true)
  clear_metadata(r, proj)
  for _, entry in ipairs(job.tags) do r.GetSetProjectInfo_String(proj, "RENDER_METADATA", entry, true) end

  local _, targets = r.GetSetProjectInfo_String(proj, "RENDER_TARGETS", "", false)
  local files = split(targets, ";")
  if #files == 0 then return false, files, "REAPER reported no file to render." end
  for _, path in ipairs(files) do
    if fs.exists(path) then fs.remove(path) end
  end

  r.Main_OnCommand(M.RENDER_COMMAND, 0)

  for _, path in ipairs(files) do
    if not fs.exists(path) or fs.size(path) == 0 then return false, files, "Missing or empty file: " .. path end
  end
  return true, files
end

function M.render(r, proj, jobs, opts)
  local report = { items = {} }
  local state = M.snapshot(r, proj)
  local ok, err = pcall(function()
    local settings = math.floor(state.num.RENDER_SETTINGS)
    r.GetSetProjectInfo(proj, "RENDER_SETTINGS", (settings & ~SOURCE_MASK) | EMBED_METADATA, true)
    r.GetSetProjectInfo(proj, "RENDER_ADDTOPROJ", math.floor(state.num.RENDER_ADDTOPROJ) & ~ADD_TO_PROJECT, true)
    r.GetSetProjectInfo(proj, "RENDER_SRATE", opts.srate or 0, true)
    r.GetSetProjectInfo_String(proj, "RENDER_FORMAT", opts.primary_format, true)
    r.GetSetProjectInfo_String(proj, "RENDER_FORMAT2", opts.secondary_format or "", true)
    for _, job in ipairs(jobs) do
      local item_ok, files, item_err = render_one(r, proj, job, opts)
      report.items[#report.items + 1] = { title = job.title, ok = item_ok, files = files, error = item_err }
    end
  end)
  M.restore(r, proj, state)
  if not ok then report.error = tostring(err) end
  return report
end

return M
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `busted && luacheck .`
Expected: all specs pass, `0 warnings / 0 errors`.

- [ ] **Step 6: Commit**

```bash
git add release_exporter/fs.lua release_exporter/renderer.lua tests/fs_spec.lua tests/renderer_spec.lua
git commit -m "feat(render): render regions one by one and always restore user settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `app` controller

**Files:**
- Create: `release_exporter/app.lua`
- Test: `tests/app_spec.lua`

**Interfaces:**
- Consumes: `model` (Task 3), `metadata_mapper.build` (Task 4), `formats.primary/secondary` (Task 2), `regions`, `project_store` (Task 5), `renderer.render`, `fs` (Task 6).
- Produces (what the UI calls):
  - `App.new(r) -> app`, with fields `app.r`, `app.proj`, `app.ep`, `app.tracks`, `app.settings`, `app.rows`, `app.validation`, `app.last_report`, `app.pending_export`, `app.show_report`, `app.flash`
  - `app:refresh(force?) -> boolean` (`true` if it rebuilt)
  - `app:set_ep_field(field, value)`, `app:set_track_field(guid, field, value)` (`field` is one of `"title"`, `"include"`, `"artist"`, `"isrc"`, `"composer"`), `app:set_setting(field, value)`
  - `app:project_dir() -> string`, `app:output_dir() -> string`
  - `app:jobs() -> jobs` (with `.tags`), `app:existing_files() -> { path, ... }`, `app:can_export() -> boolean`
  - `app:export() -> report` (adds `report.output_dir`, stores it in `app.last_report`)
  - `app:create_regions_from_items() -> count`

- [ ] **Step 1: Write the failing tests**

`tests/app_spec.lua`:

```lua
local fake = require("tests.support.fake_reaper")
local App = require("release_exporter.app")
local fs = require("release_exporter.fs")

local function setup()
  local r = fake.new()
  r.add_region(0, 10, "Intro")
  r.add_region(10, 20, "Minuit")
  return r, App.new(r)
end

local function fill_ep(app)
  app:set_ep_field("artist", "Clem")
  app:set_ep_field("album", "Nuits")
  app:set_ep_field("year", "2026")
end

describe("app", function()
  it("builds rows from the project's regions", function()
    local _, app = setup()
    assert.are.equal(2, #app.rows)
    assert.are.equal("Intro", app.rows[1].title)
    assert.are.equal(2, app.rows[2].number)
  end)

  it("renames the region when a title is edited", function()
    local r, app = setup()
    app:set_track_field(app.rows[1].guid, "title", "Aube")
    assert.are.equal("Aube", r.markers()[1].name)
    assert.are.equal("Aube", app.rows[1].title)
    assert.are.equal(1, #r.undo_points)
  end)

  it("stores other fields by GUID, normalizes ISRC and persists them", function()
    local r, app = setup()
    local guid = app.rows[2].guid
    app:set_track_field(guid, "isrc", "fr-xxx-26-00002")
    app:set_track_field(guid, "include", false)
    local reloaded = App.new(r)
    assert.are.equal("FRXXX2600002", reloaded.rows[2].isrc)
    assert.is_false(reloaded.rows[2].include)
    assert.are.equal(0, #r.undo_points)
  end)

  it("keeps metadata of a deleted region and gets it back when the region is restored", function()
    local r, app = setup()
    local guid = app.rows[1].guid
    app:set_track_field(guid, "isrc", "FRXXX2600001")
    local removed = r.remove_region(guid)
    app:refresh()
    assert.are.equal(1, #app.rows)
    r.restore_marker(removed)
    app:refresh()
    assert.are.equal("FRXXX2600001", app.rows[1].isrc)
  end)

  it("only rebuilds when the project changed", function()
    local r, app = setup()
    assert.is_false(app:refresh())
    r.add_region(20, 30, "Aube")
    assert.is_true(app:refresh())
    assert.are.equal(3, #app.rows)
  end)

  it("reloads everything when the active project changes", function()
    local r, app = setup()
    fill_ep(app)
    r.switch_project()
    app:refresh()
    assert.are.equal("", app.ep.artist)
    assert.are.equal(0, #app.rows)
  end)

  it("defaults the output folder next to the project", function()
    local _, app = setup()
    fill_ep(app)
    assert.are.equal("/music/ep/Exports/Nuits", app:output_dir())
    app:set_setting("output_dir", "/custom")
    assert.are.equal("/custom", app:output_dir())
  end)

  it("blocks export for an unsaved project without output folder", function()
    local r = fake.new()
    r.projfn = ""
    r.add_region(0, 10, "Intro")
    local app = App.new(r)
    fill_ep(app)
    assert.are.equal("", app:output_dir())
    assert.is_false(app:can_export())
    assert.are.equal("settings.output_dir", app.validation.errors[1].field)
  end)

  it("drops a missing cover from the tags", function()
    local _, app = setup()
    fill_ep(app)
    app:set_ep_field("cover", "/nope/cover.jpg")
    for _, tag in ipairs(app:jobs()[1].tags) do
      assert.is_nil(tag:find("APIC", 1, true))
    end
  end)

  it("exports every included song and keeps the report", function()
    local base = os.tmpname()
    os.remove(base)
    local r = fake.new()
    r.projfn = base .. "/EP.rpp"
    r.add_region(0, 10, "Intro")
    r.add_region(10, 20, "Minuit")
    local app = App.new(r)
    fill_ep(app)
    local report = app:export()
    assert.is_nil(report.error)
    assert.are.equal(2, #report.items)
    assert.is_true(report.items[2].ok)
    assert.is_true(fs.exists(base .. "/Exports/Nuits/02 - Minuit.mp3"))
    assert.are.equal(report, app.last_report)
    assert.are.equal(4, #app:existing_files())
  end)

  it("creates regions from selected items", function()
    local r = fake.new()
    local app = App.new(r)
    r.selected_items = { { pos = 0, len = 5, take = { name = "Song A.wav" } } }
    assert.are.equal(1, app:create_regions_from_items())
    assert.are.equal("Song A", app.rows[1].title)
  end)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `busted tests/app_spec.lua`
Expected: FAIL with `module 'release_exporter.app' not found`.

- [ ] **Step 3: Implement `release_exporter/app.lua`**

```lua
-- Controller between the ReaImGui views and the model/adapters. Holds the state of the active project.
local model = require("release_exporter.model")
local mapper = require("release_exporter.metadata_mapper")
local formats = require("release_exporter.formats")
local regions = require("release_exporter.regions")
local store = require("release_exporter.project_store")
local renderer = require("release_exporter.renderer")
local fs = require("release_exporter.fs")

local App = {}
App.__index = App

function App.new(r)
  local self = setmetatable({ r = r, change_count = -1 }, App)
  self:refresh(true)
  return self
end

function App:refresh(force)
  local proj, projfn = self.r.EnumProjects(-1)
  local count = self.r.GetProjectStateChangeCount(proj)
  local switched = proj ~= self.proj
  if not force and not switched and count == self.change_count then return false end
  if force or switched then
    local data = store.load(self.r, proj)
    self.ep, self.tracks, self.settings = data.ep, data.tracks, data.settings
  end
  self.proj, self.projfn, self.change_count = proj, projfn or "", count
  self:rebuild()
  return true
end

function App:rebuild()
  self.rows = model.build_rows(regions.list(self.r, self.proj), self.tracks)
  self.validation = model.validate(self.ep, self.rows, self.settings, self:output_dir(),
    { file_exists = self.r.file_exists })
end

function App:project_dir()
  return self.projfn:match("^(.*)[/\\][^/\\]*$") or ""
end

function App:output_dir()
  if not model.blank(self.settings.output_dir) then return self.settings.output_dir end
  return model.default_output_dir(self:project_dir(), self.ep.album)
end

function App:set_ep_field(field, value)
  self.ep[field] = value
  store.save_ep(self.r, self.proj, self.ep)
  self:rebuild()
end

function App:set_track_field(guid, field, value)
  if field == "title" then
    regions.rename(self.r, self.proj, guid, value)
  else
    if field == "isrc" then value = model.normalize_isrc(value) end
    local data = self.tracks[guid] or model.default_track()
    data[field] = value
    self.tracks[guid] = data
    store.save_track(self.r, self.proj, guid, data)
  end
  self:rebuild()
end

function App:set_setting(field, value)
  self.settings[field] = value
  store.save_settings(self.r, self.proj, self.settings)
  self:rebuild()
end

function App:jobs()
  local ep = self.ep
  if not model.blank(ep.cover) and not self.r.file_exists(ep.cover) then
    ep = {}
    for k, v in pairs(self.ep) do ep[k] = v end
    ep.cover = ""
  end
  local jobs = model.plan_outputs(ep, self.rows, self.settings, self:output_dir())
  for _, job in ipairs(jobs) do job.tags = mapper.build(job.resolved) end
  return jobs
end

function App:existing_files()
  local out = {}
  for _, job in ipairs(self:jobs()) do
    for _, path in ipairs(job.files) do
      if fs.exists(path) then out[#out + 1] = path end
    end
  end
  return out
end

function App:can_export()
  return #self.validation.errors == 0
end

function App:export()
  local dir = self:output_dir()
  local report
  if fs.ensure_dir(self.r, dir) then
    report = renderer.render(self.r, self.proj, self:jobs(), {
      output_dir = dir,
      primary_format = formats.primary(self.settings.primary),
      secondary_format = formats.secondary(self.settings.secondary),
      srate = self.settings.srate,
    })
  else
    report = { items = {}, error = "Cannot create or write to " .. dir }
  end
  report.output_dir = dir
  self.last_report = report
  return report
end

function App:create_regions_from_items()
  local count = regions.create_from_selected_items(self.r, self.proj)
  self:refresh()
  return count
end

return App
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted && luacheck .`
Expected: all specs pass, `0 warnings / 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add release_exporter/app.lua tests/app_spec.lua
git commit -m "feat(app): add controller tying regions, storage, validation and rendering

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: ReaImGui interface and entry script (manual verification)

ReaImGui calls cannot be unit-tested. This task is checked with lint plus the manual checklist in `docs/testing.md`, run inside REAPER.

**Files:**
- Create: `Release Exporter.lua`, `release_exporter/ui/init.lua`, `release_exporter/ui/widgets.lua`, `release_exporter/ui/ep_panel.lua`, `release_exporter/ui/tracks_table.lua`, `release_exporter/ui/export_bar.lua`, `release_exporter/ui/settings_popup.lua`, `release_exporter/ui/report_popup.lua`, `docs/testing.md`

**Interfaces:**
- Consumes: everything `App` produces (Task 7), `model.issue_for`, `model.FORMAT_LABELS`, `model.default_settings`, `model.blank` (Task 3), `fs.open_folder` (Task 6).
- Produces: `ui.draw(ImGui, ctx, app)`. Each view module exposes `draw(ImGui, ctx, app, ...)`.

- [ ] **Step 1: Write `release_exporter/ui/widgets.lua`**

```lua
-- Shared ReaImGui widgets.
local M = {}

local drafts = {}

-- Text input that reports its value only when editing ends (Enter, Tab or focus loss).
-- A region rename then creates one undo point instead of one per keystroke.
-- Returns the new value, or nil when nothing was committed this frame.
function M.text_field(ImGui, ctx, id, value, opts)
  opts = opts or {}
  local key = opts.key or id
  if opts.width then ImGui.SetNextItemWidth(ctx, opts.width) end
  if opts.error then ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x7A2E2EFF) end
  local changed, new_value = ImGui.InputTextWithHint(ctx, id, opts.hint or "", drafts[key] or value or "")
  if opts.error then
    ImGui.PopStyleColor(ctx)
    ImGui.SetItemTooltip(ctx, opts.error)
  end
  if changed then drafts[key] = new_value end
  if ImGui.IsItemDeactivated(ctx) then
    local draft = drafts[key]
    drafts[key] = nil
    if draft ~= nil and draft ~= (value or "") then return draft end
  end
end

-- options: array of { value = any, label = string }. Returns the picked value or nil.
function M.combo(ImGui, ctx, id, current, options, width)
  local preview = tostring(current)
  for _, option in ipairs(options) do
    if option.value == current then preview = option.label end
  end
  if width then ImGui.SetNextItemWidth(ctx, width) end
  local picked
  if ImGui.BeginCombo(ctx, id, preview) then
    for _, option in ipairs(options) do
      if ImGui.Selectable(ctx, option.label, option.value == current) then picked = option.value end
    end
    ImGui.EndCombo(ctx)
  end
  return picked
end

M.COLOR_ERROR = 0xE06C6CFF
M.COLOR_WARNING = 0xF2B84BFF

return M
```

- [ ] **Step 2: Write `release_exporter/ui/ep_panel.lua`**

```lua
-- EP card: cover (click to choose, or drop a file) and the EP-level fields.
local model = require("release_exporter.model")
local widgets = require("release_exporter.ui.widgets")

local M = {}

local COVER_SIZE = 110
local cover = { path = nil, image = nil }

local function cover_image(ImGui, ctx, path)
  if path == cover.path then return cover.image end
  if cover.image then ImGui.Detach(ctx, cover.image) end
  cover.path, cover.image = path, nil
  if path ~= "" then
    local ok, image = pcall(ImGui.CreateImage, path)
    if ok and image then
      ImGui.Attach(ctx, image)
      cover.image = image
    end
  end
  return cover.image
end

local function field(ImGui, ctx, app, label, key, width, hint)
  ImGui.BeginGroup(ctx)
  ImGui.TextDisabled(ctx, label)
  local value = widgets.text_field(ImGui, ctx, "##ep_" .. key, app.ep[key], {
    width = width, hint = hint, error = model.issue_for(app.validation.errors, nil, "ep." .. key),
  })
  if value then app:set_ep_field(key, value) end
  ImGui.EndGroup(ctx)
end

local function draw_cover(ImGui, ctx, app)
  ImGui.BeginGroup(ctx)
  local image = cover_image(ImGui, ctx, app.ep.cover)
  local clicked
  if image then
    clicked = ImGui.ImageButton(ctx, "##cover", image, COVER_SIZE, COVER_SIZE)
  else
    clicked = ImGui.Button(ctx, "Drop cover\nor click", COVER_SIZE, COVER_SIZE)
  end
  if clicked then
    local ok, file = app.r.GetUserFileNameForRead("", "Choose cover image", "jpg")
    if ok then app:set_ep_field("cover", file) end
  end
  if ImGui.BeginDragDropTarget(ctx) then
    local ok, count = ImGui.AcceptDragDropPayloadFiles(ctx)
    if ok and count > 0 then
      local _, file = ImGui.GetDragDropPayloadFile(ctx, 0)
      app:set_ep_field("cover", file)
    end
    ImGui.EndDragDropTarget(ctx)
  end
  if app.ep.cover ~= "" and ImGui.SmallButton(ctx, "Remove cover") then app:set_ep_field("cover", "") end
  ImGui.EndGroup(ctx)
end

function M.draw(ImGui, ctx, app)
  draw_cover(ImGui, ctx, app)
  ImGui.SameLine(ctx)
  ImGui.BeginGroup(ctx)
  local width = ImGui.GetContentRegionAvail(ctx)
  local col = (width - 16) / 10
  field(ImGui, ctx, app, "Artist", "artist", col * 3.5)
  ImGui.SameLine(ctx)
  field(ImGui, ctx, app, "EP title", "album", col * 4.5)
  ImGui.SameLine(ctx)
  field(ImGui, ctx, app, "Year", "year", col * 2, "YYYY")
  field(ImGui, ctx, app, "Album artist", "album_artist", col * 3.5, app.ep.artist)
  ImGui.SameLine(ctx)
  field(ImGui, ctx, app, "Genre", "genre", col * 2)
  ImGui.SameLine(ctx)
  field(ImGui, ctx, app, "Label", "label", col * 2)
  ImGui.SameLine(ctx)
  field(ImGui, ctx, app, "Copyright", "copyright", col * 2.5, "(P) 2026 Name")
  ImGui.EndGroup(ctx)
end

return M
```

- [ ] **Step 3: Write `release_exporter/ui/tracks_table.lua`**

```lua
-- Songs table (one row per region) and the empty state for projects without regions.
local model = require("release_exporter.model")
local widgets = require("release_exporter.ui.widgets")

local M = {}

local function duration(seconds)
  local total = math.floor(seconds + 0.5)
  return string.format("%d:%02d", total // 60, total % 60)
end

local function cell(ImGui, ctx, app, row, key, hint)
  ImGui.TableNextColumn(ctx)
  local issue = row.include and model.issue_for(app.validation.errors, row.guid, key) or nil
  local value = widgets.text_field(ImGui, ctx, "##" .. key, row[key], {
    key = row.guid .. ":" .. key, width = -1, hint = hint, error = issue,
  })
  if value then app:set_track_field(row.guid, key, value) end
end

local function draw_empty(ImGui, ctx, app)
  ImGui.Dummy(ctx, 0, 16)
  ImGui.TextWrapped(ctx, "This project has no regions yet. Create one region per song, or select the song items "
    .. "(rendered mixes or subprojects) and click the button below.")
  if ImGui.Button(ctx, "Create one region per selected item") then
    app.flash = app:create_regions_from_items() == 0 and "Select at least one media item first." or nil
  end
  if app.flash then ImGui.TextColored(ctx, widgets.COLOR_WARNING, app.flash) end
end

function M.draw(ImGui, ctx, app, height)
  if #app.rows == 0 then return draw_empty(ImGui, ctx, app) end
  local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_ScrollY
  if not ImGui.BeginTable(ctx, "tracks", 7, flags, 0, height) then return end
  ImGui.TableSetupScrollFreeze(ctx, 0, 1)
  ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthFixed, 24)
  ImGui.TableSetupColumn(ctx, "#", ImGui.TableColumnFlags_WidthFixed, 28)
  ImGui.TableSetupColumn(ctx, "Title", ImGui.TableColumnFlags_WidthStretch, 3)
  ImGui.TableSetupColumn(ctx, "Artist", ImGui.TableColumnFlags_WidthStretch, 2)
  ImGui.TableSetupColumn(ctx, "ISRC", ImGui.TableColumnFlags_WidthStretch, 1.6)
  ImGui.TableSetupColumn(ctx, "Composer", ImGui.TableColumnFlags_WidthStretch, 2)
  ImGui.TableSetupColumn(ctx, "Length", ImGui.TableColumnFlags_WidthFixed, 52)
  ImGui.TableHeadersRow(ctx)
  for _, row in ipairs(app.rows) do
    ImGui.PushID(ctx, row.guid)
    ImGui.TableNextRow(ctx)
    ImGui.TableNextColumn(ctx)
    local changed, include = ImGui.Checkbox(ctx, "##include", row.include)
    if changed then app:set_track_field(row.guid, "include", include) end
    ImGui.TableNextColumn(ctx)
    if row.number then ImGui.Text(ctx, tostring(row.number)) else ImGui.TextDisabled(ctx, "-") end
    cell(ImGui, ctx, app, row, "title", "Title")
    cell(ImGui, ctx, app, row, "artist", app.ep.artist)
    cell(ImGui, ctx, app, row, "isrc", "CCXXXYYNNNNN")
    cell(ImGui, ctx, app, row, "composer", "")
    ImGui.TableNextColumn(ctx)
    ImGui.Text(ctx, duration(row.duration))
    ImGui.PopID(ctx)
  end
  ImGui.EndTable(ctx)
end

return M
```

- [ ] **Step 4: Write `release_exporter/ui/settings_popup.lua`**

```lua
-- Export settings modal.
local model = require("release_exporter.model")
local widgets = require("release_exporter.ui.widgets")

local M = { ID = "Export settings" }

local PRIMARY = { { value = "wav24", label = model.FORMAT_LABELS.wav24 }, { value = "wav16", label = model.FORMAT_LABELS.wav16 } }
local SECONDARY = {
  { value = "mp3_320", label = model.FORMAT_LABELS.mp3_320 },
  { value = "flac", label = model.FORMAT_LABELS.flac },
  { value = "none", label = model.FORMAT_LABELS.none },
}
local SAMPLE_RATES = { { value = 0, label = "Project rate" }, { value = 44100, label = "44.1 kHz" }, { value = 48000, label = "48 kHz" } }

function M.draw(ImGui, ctx, app)
  if not ImGui.BeginPopupModal(ctx, M.ID, true, ImGui.WindowFlags_AlwaysAutoResize) then return end
  local s = app.settings

  ImGui.TextDisabled(ctx, "Output folder (empty = next to the project)")
  local dir = widgets.text_field(ImGui, ctx, "##output_dir", s.output_dir, { width = 420, hint = app:output_dir() })
  if dir then app:set_setting("output_dir", dir) end
  if app.r.JS_Dialog_BrowseForFolder then
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Browse...") then
      local rv, folder = app.r.JS_Dialog_BrowseForFolder("Choose output folder", app:output_dir())
      if rv == 1 then app:set_setting("output_dir", folder) end
    end
  end

  ImGui.TextDisabled(ctx, "File name pattern: {nn} {n} {title} {artist} {album} {year}")
  local pattern = widgets.text_field(ImGui, ctx, "##pattern", s.pattern, { width = 420 })
  if pattern then
    app:set_setting("pattern", model.blank(pattern) and model.default_settings().pattern or pattern)
  end

  ImGui.TextDisabled(ctx, "Main format")
  local primary = widgets.combo(ImGui, ctx, "##primary", s.primary, PRIMARY, 200)
  if primary then app:set_setting("primary", primary) end

  ImGui.TextDisabled(ctx, "Second format")
  local secondary = widgets.combo(ImGui, ctx, "##secondary", s.secondary, SECONDARY, 200)
  if secondary then app:set_setting("secondary", secondary) end

  ImGui.TextDisabled(ctx, "Sample rate")
  local srate = widgets.combo(ImGui, ctx, "##srate", s.srate, SAMPLE_RATES, 200)
  if srate then app:set_setting("srate", srate) end

  ImGui.Separator(ctx)
  if ImGui.Button(ctx, "Close") then ImGui.CloseCurrentPopup(ctx) end
  ImGui.EndPopup(ctx)
end

return M
```

- [ ] **Step 5: Write `release_exporter/ui/report_popup.lua`**

```lua
-- Export report modal, opened by the main loop once an export finishes.
local fs = require("release_exporter.fs")
local widgets = require("release_exporter.ui.widgets")

local M = { ID = "Export report" }

function M.draw(ImGui, ctx, app)
  if app.show_report then
    ImGui.OpenPopup(ctx, M.ID)
    app.show_report = false
  end
  if not ImGui.BeginPopupModal(ctx, M.ID, true, ImGui.WindowFlags_AlwaysAutoResize) then return end
  local report = app.last_report
  if report.error then ImGui.TextColored(ctx, widgets.COLOR_ERROR, "Export stopped: " .. report.error) end
  for _, item in ipairs(report.items) do
    if item.ok then
      ImGui.Text(ctx, "OK      " .. item.title)
    else
      ImGui.TextColored(ctx, widgets.COLOR_ERROR, "FAILED  " .. item.title .. " - " .. (item.error or ""))
    end
    for _, path in ipairs(item.files or {}) do ImGui.TextDisabled(ctx, "        " .. path) end
  end
  ImGui.Separator(ctx)
  if ImGui.Button(ctx, "Open folder") then fs.open_folder(app.r, report.output_dir) end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Close") then ImGui.CloseCurrentPopup(ctx) end
  ImGui.EndPopup(ctx)
end

return M
```

- [ ] **Step 6: Write `release_exporter/ui/export_bar.lua`**

```lua
-- Bottom bar: issues, summary, Settings and Export buttons, and the confirmation modal.
local model = require("release_exporter.model")
local widgets = require("release_exporter.ui.widgets")
local settings_popup = require("release_exporter.ui.settings_popup")
local report_popup = require("release_exporter.ui.report_popup")

local M = {}

local CONFIRM_ID = "Confirm export"
local MAX_LINES = 3
local existing = {}

local function draw_issues(ImGui, ctx, issues, color, prefix)
  for i, issue in ipairs(issues) do
    if i > MAX_LINES then
      ImGui.TextColored(ctx, color, ("... and %d more"):format(#issues - MAX_LINES))
      break
    end
    ImGui.TextColored(ctx, color, prefix .. issue.message)
  end
end

local function draw_confirm(ImGui, ctx, app, jobs)
  if not ImGui.BeginPopupModal(ctx, CONFIRM_ID, true, ImGui.WindowFlags_AlwaysAutoResize) then return end
  local files = 0
  for _, job in ipairs(jobs) do files = files + #job.files end
  ImGui.Text(ctx, ("%d songs -> %d files in"):format(#jobs, files))
  ImGui.TextDisabled(ctx, app:output_dir())
  if #existing > 0 then
    ImGui.TextColored(ctx, widgets.COLOR_WARNING, ("%d files already exist and will be overwritten."):format(#existing))
  end
  ImGui.Separator(ctx)
  if ImGui.Button(ctx, #existing > 0 and "Overwrite and export" or "Export") then
    app.pending_export = true
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Cancel") then ImGui.CloseCurrentPopup(ctx) end
  ImGui.EndPopup(ctx)
end

function M.draw(ImGui, ctx, app)
  local v = app.validation
  local jobs = app:jobs()
  ImGui.Separator(ctx)
  draw_issues(ImGui, ctx, v.errors, widgets.COLOR_ERROR, "Error: ")
  if #v.errors == 0 then draw_issues(ImGui, ctx, v.warnings, widgets.COLOR_WARNING, "Warning: ") end

  local s = app.settings
  local formats = model.FORMAT_LABELS[s.primary]
  if s.secondary ~= "none" then formats = formats .. " + " .. model.FORMAT_LABELS[s.secondary] end
  local example = jobs[1] and jobs[1].basename or "-"
  ImGui.TextDisabled(ctx, ("%s  |  %s  |  e.g. %s"):format(formats, app:output_dir(), example))

  if ImGui.Button(ctx, "Settings...") then ImGui.OpenPopup(ctx, settings_popup.ID) end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, not app:can_export())
  if ImGui.Button(ctx, ("Export EP (%d)"):format(#jobs)) then
    existing = app:existing_files()
    ImGui.OpenPopup(ctx, CONFIRM_ID)
  end
  ImGui.EndDisabled(ctx)

  settings_popup.draw(ImGui, ctx, app)
  draw_confirm(ImGui, ctx, app, jobs)
  report_popup.draw(ImGui, ctx, app)
end

return M
```

- [ ] **Step 7: Write `release_exporter/ui/init.lua`**

```lua
-- Main window layout: EP card, songs table, export bar.
local ep_panel = require("release_exporter.ui.ep_panel")
local tracks_table = require("release_exporter.ui.tracks_table")
local export_bar = require("release_exporter.ui.export_bar")

local M = {}

local EXPORT_BAR_HEIGHT = 110

function M.draw(ImGui, ctx, app)
  ep_panel.draw(ImGui, ctx, app)
  ImGui.Spacing(ctx)
  local _, height = ImGui.GetContentRegionAvail(ctx)
  tracks_table.draw(ImGui, ctx, app, math.max(120, height - EXPORT_BAR_HEIGHT))
  export_bar.draw(ImGui, ctx, app)
end

return M
```

- [ ] **Step 8: Write the entry script `Release Exporter.lua`**

```lua
-- @description Release Exporter: fill EP metadata and export every song in one click
-- @author Clément Decou
-- @version 0.1.0
-- @about
--   Fill EP-level and per-song metadata (title, artist, ISRC, composer, cover...) in one window,
--   then render every region of the project as WAV + MP3/FLAC with embedded tags.
--   Requires ReaImGui (ReaTeam Extensions).
-- @provides
--   [nomain] release_exporter/*.lua
--   [nomain] release_exporter/ui/*.lua
--   [nomain] release_exporter/vendor/*.lua
local r = reaper

if not r.ImGui_GetBuiltinPath then
  r.ShowMessageBox("Release Exporter needs ReaImGui 0.9 or newer.\n\n"
    .. "Install it with Extensions > ReaPack > Browse packages > \"ReaImGui\", then restart REAPER.",
    "Release Exporter", 0)
  return
end

local script_dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
package.path = r.ImGui_GetBuiltinPath() .. "/?.lua;" .. script_dir .. "?.lua;" .. script_dir .. "?/init.lua;"
  .. package.path

local ImGui = require("imgui")("0.9")
local App = require("release_exporter.app")
local ui = require("release_exporter.ui")

local app = App.new(r)
local ctx = ImGui.CreateContext("Release Exporter")

local function loop()
  -- Rendering blocks REAPER, so it runs between frames rather than inside Begin/End.
  if app.pending_export then
    app.pending_export = false
    app:export()
    app.show_report = true
  end
  app:refresh()
  ImGui.SetNextWindowSize(ctx, 920, 600, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "Release Exporter", true)
  if visible then
    ui.draw(ImGui, ctx, app)
    ImGui.End(ctx)
  end
  if open then r.defer(loop) end
end

r.defer(loop)
```

- [ ] **Step 9: Lint and run the unit suite**

Run: `luacheck . && busted`
Expected: `0 warnings / 0 errors`, all specs still pass.

- [ ] **Step 10: Write `docs/testing.md`**

```markdown
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
```

- [ ] **Step 11: Run the manual checklist in REAPER**

Work through `docs/testing.md` on REAPER 7.0 and the latest version. Fix any failure before committing: add a unit test when the bug is in a pure or adapter module.

- [ ] **Step 12: Commit**

```bash
git add "Release Exporter.lua" release_exporter/ui docs/testing.md
git commit -m "feat(ui): add ReaImGui window for EP metadata and one-click export

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: ReaPack distribution and README

**Files:**
- Create: `README.md`, `LICENSE`
- Modify: `.github/workflows/ci.yml` (add the `reapack` job), `Release Exporter.lua` (add `@link`)

**Interfaces:**
- Consumes: the package header written in Task 8.
- Produces: a ReaPack repository whose `index.xml` is generated by `reapack-index`, and a public README.

- [ ] **Step 1: Create the GitHub repository and remote**

```bash
gh repo create reaper-release-plugin --public --source . --remote origin
git remote get-url origin   # e.g. https://github.com/<owner>/reaper-release-plugin.git
```

- [ ] **Step 2: Add the link to the package header**

In `Release Exporter.lua`, add the line below right after `-- @author Clément Decou`. Use the owner from Step 1.

```lua
-- @link https://github.com/<owner>/reaper-release-plugin
```

- [ ] **Step 3: Add the MIT license**

```bash
gh api /licenses/mit --jq .body | sed "s/\[year\]/2026/; s/\[fullname\]/Clément Decou/" > LICENSE
```

- [ ] **Step 4: Write `README.md`**

```markdown
# Release Exporter for REAPER

Fill your EP's metadata in one window and export every song as WAV + MP3/FLAC with proper tags (title, artist, album, track number, ISRC, composer, cover art) in one click.

## Requirements
- REAPER 7.0 or newer
- ReaImGui 0.9 or newer (Extensions > ReaPack > Browse packages > "ReaImGui")

## Install
1. Extensions > ReaPack > Import repositories…
2. Paste `https://github.com/<owner>/reaper-release-plugin/raw/main/index.xml`
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
```

- [ ] **Step 5: Add the ReaPack check to CI**

Append this job under `jobs:` in `.github/workflows/ci.yml`:

```yaml
  reapack:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
      - run: gem install reapack-index
      - run: reapack-index --check
```

- [ ] **Step 6: Generate the index locally**

```bash
gem install reapack-index
reapack-index --check    # Expected: no errors
reapack-index --commit   # Creates/updates index.xml and commits it
```

- [ ] **Step 7: Commit and push**

```bash
git add README.md LICENSE .github/workflows/ci.yml "Release Exporter.lua"
git commit -m "chore(release): add README, license and ReaPack index check

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin main
```

Expected: both CI jobs are green on GitHub. Importing the repository URL in ReaPack on a clean REAPER install shows "Release Exporter".
