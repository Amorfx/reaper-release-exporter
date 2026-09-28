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

  it("never touches a file that was not announced to the user", function()
    local r = fake.new()
    local stale = opts.output_dir .. "/01 - Intro.mp3"
    local f = io.open(stale, "wb")
    f:write("old")
    f:close()
    local announced = job("01 - Intro", 0, 10)
    announced.files = { opts.output_dir .. "/01 - Intro.wav" } -- REAPER will also want the .mp3
    local report = renderer.render(r, r.proj, { announced }, opts)
    assert.is_false(report.items[1].ok)
    assert.is_truthy(report.items[1].error:find("not announced", 1, true))
    assert.are.equal(0, #r.commands)
    assert.is_true(fs.exists(stale))
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
  it("stops after a song produced no file when told not to continue", function()
    local r = fake.new()
    r.render_behavior = "missing"
    local asked = {}
    opts.on_failure = function(item) asked[#asked + 1] = item.title; return false end
    local report = renderer.render(r, r.proj, { job("01 - A", 0, 1), job("02 - B", 1, 2), job("03 - C", 2, 3) }, opts)
    assert.are.equal(1, #r.commands)
    assert.are.same({ "01 - A" }, asked)
    assert.are.equal(3, #report.items)
    assert.is_false(report.items[2].ok)
    assert.is_true(report.items[2].skipped)
    assert.is_true(report.items[3].skipped)
  end)

  it("keeps going when on_failure says to continue", function()
    local r = fake.new()
    r.render_behavior = "missing"
    opts.on_failure = function() return true end
    renderer.render(r, r.proj, { job("01 - A", 0, 1), job("02 - B", 1, 2) }, opts)
    assert.are.equal(2, #r.commands)
  end)

  it("skips the render when a stale file cannot be deleted", function()
    local r = fake.new()
    local stale = opts.output_dir .. "/01 - Intro.wav"
    local f = assert(io.open(stale, "wb"))
    f:write("old")
    f:close()
    os.execute('chmod 555 "' .. opts.output_dir .. '"')
    local report = renderer.render(r, r.proj, { job("01 - Intro", 0, 10) }, opts)
    os.execute('chmod 755 "' .. opts.output_dir .. '"')
    assert.are.equal(0, #r.commands)
    assert.is_false(report.items[1].ok)
    assert.is_truthy(report.items[1].error:find("Cannot overwrite", 1, true))
  end)
end)
