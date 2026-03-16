-- shatter
--
-- bbcut-inspired live audio
-- cutting for norns
--
-- llllllll.co/t/shatter
--
-- E1: page select
-- K2: start/stop
-- K3: retrigger phrase
--
-- >> page CUT
-- E2: dry/wet mix
-- E3: tempo
--
-- >> page ALGO
-- E2: select parameter
-- E3: adjust value
--
-- >> page FX
-- E2: select fx slot
-- E3: adjust mix
--
-- v1.0.0 @yourname

engine.name = "Shatter"

local cutprocs = include("shatter/lib/cutprocs")
local ui = include("shatter/lib/ui")

-- ============================================================
-- STATE
-- ============================================================

local state = {
  running = false,
  tempo = 120,
  proc_name = "proc11",
  proc_label = "BBCutProc11",
  proc = nil,
  cut_clock = nil,
  capture_pos = 0,
  dry_wet = 0.8,
  algo_sel = 1,    -- selected param on algo page
  -- per-procedure parameter tables
  proc_params = {
    proc11 = {
      {name = "subdiv",   key = "sdiv",          val = 8,   min = 2,  max = 32, step = 1,   fmt = "%d"},
      {name = "bars",     key = "phrasebars",    val = 4,   min = 1,  max = 16, step = 1,   fmt = "%d"},
      {name = "repeats",  key = "numrepeats",    val = 2,   min = 1,  max = 8,  step = 1,   fmt = "%d"},
      {name = "stut.prob",key = "stutterchance", val = 0.2, min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
      {name = "stut.spd", key = "stutterspeed",  val = 2,   min = 0.5,max = 4,  step = 0.25,fmt = "%.2f"},
      {name = "offset",   key = "offset_chance", val = 0.3, min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
    },
    warpcut = {
      {name = "subdiv",   key = "sdiv",          val = 8,   min = 2,  max = 32, step = 1,   fmt = "%d"},
      {name = "bars",     key = "phrasebars",    val = 2,   min = 1,  max = 16, step = 1,   fmt = "%d"},
      {name = "warp",     key = "warp",          val = 0.5, min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
      {name = "deform",   key = "deform",        val = 0.3, min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
      {name = "offset",   key = "offset_chance", val = 0.5, min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
    },
    sqpush1 = {
      {name = "subdiv",   key = "sdiv",          val = 16,  min = 4,  max = 32, step = 1,   fmt = "%d"},
      {name = "bars",     key = "phrasebars",    val = 2,   min = 1,  max = 8,  step = 1,   fmt = "%d"},
      {name = "fill",     key = "fill_chance",   val = 0.35,min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
      {name = "accel",    key = "accel_chance",  val = 0.2, min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
      {name = "roll",     key = "roll_chance",   val = 0.25,min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
      {name = "offset",   key = "offset_chance", val = 0.6, min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
    },
    sqpush2 = {
      {name = "subdiv",   key = "sdiv",          val = 16,  min = 4,  max = 32, step = 1,   fmt = "%d"},
      {name = "bars",     key = "phrasebars",    val = 2,   min = 1,  max = 8,  step = 1,   fmt = "%d"},
      {name = "grain",    key = "grain_chance",  val = 0.3, min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
      {name = "pitch",    key = "pitch_chance",  val = 0.25,min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
      {name = "silence",  key = "silence_chance",val = 0.1, min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
      {name = "offset",   key = "offset_chance", val = 0.7, min = 0,  max = 1,  step = 0.05,fmt = "%.0f%%", scale = 100},
    }
  },
  -- fx state
  fx = {
    {name = "reverb",   mix = 0, params = {room = 0.6, damp = 0.5}},
    {name = "comb",     mix = 0, params = {freq = 800, decay = 0.2}},
    {name = "bitcrush", mix = 0, params = {bits = 12, downsample = 1}},
    {name = "ringmod",  mix = 0, params = {freq = 440, depth = 0.5}},
    {name = "brf",      mix = 0, params = {freq = 1200, rq = 0.5}},
  }
}

-- ============================================================
-- ENGINE COMMUNICATION
-- ============================================================

local function send_cut(cut)
  if cut.amp <= 0 then return end
  if cut.stutter and cut.stutter_grain then
    engine.play_stutter(
      cut.offset,
      cut.stutter_grain,
      cut.rate,
      cut.amp * state.dry_wet,
      cut.dur
    )
  else
    engine.play_slice(
      cut.offset,
      cut.dur,
      cut.rate,
      cut.amp * state.dry_wet,
      0,  -- pan
      cut.reverse or 0
    )
  end
end

local function send_fx()
  for _, fx in ipairs(state.fx) do
    if fx.name == "reverb" then
      engine.fx_reverb_mix(fx.mix)
      engine.fx_reverb_room(fx.params.room)
      engine.fx_reverb_damp(fx.params.damp)
    elseif fx.name == "comb" then
      engine.fx_comb_mix(fx.mix)
      engine.fx_comb_freq(fx.params.freq)
      engine.fx_comb_decay(fx.params.decay)
    elseif fx.name == "bitcrush" then
      engine.fx_bitcrush_mix(fx.mix)
      engine.fx_bitcrush_bits(fx.params.bits)
      engine.fx_bitcrush_downsample(fx.params.downsample)
    elseif fx.name == "ringmod" then
      engine.fx_ringmod_mix(fx.mix)
      engine.fx_ringmod_freq(fx.params.freq)
      engine.fx_ringmod_depth(fx.params.depth)
    elseif fx.name == "brf" then
      engine.fx_brf_mix(fx.mix)
      engine.fx_brf_freq(fx.params.freq)
      engine.fx_brf_rq(fx.params.rq)
    end
  end
end

-- ============================================================
-- CUT SCHEDULER (runs via norns clock)
-- ============================================================

local function get_subdiv_dur()
  -- duration of one subdivision in seconds
  local beat_dur = 60 / state.tempo
  local p = state.proc_params[state.proc_name]
  local sdiv = 8
  for _, pp in ipairs(p) do
    if pp.key == "sdiv" then sdiv = pp.val; break end
  end
  -- sdiv subdivisions per bar (4 beats)
  return (beat_dur * 4) / sdiv
end

local function build_proc_params()
  local raw = {}
  local p = state.proc_params[state.proc_name]
  for _, pp in ipairs(p) do
    raw[pp.key] = pp.val
  end
  return raw
end

local function cut_loop()
  while true do
    if not state.running then
      clock.sleep(0.05)
    else
      -- create/recreate proc if needed
      if state.proc == nil then
        state.proc = cutprocs.create(state.proc_name, build_proc_params())
        state.proc:init_phrase()
      end

      local subdiv_dur = get_subdiv_dur()
      local cuts = state.proc:next_block(subdiv_dur)

      -- update ui phrase state
      ui.phrase_pos = state.proc.phrase_pos
      ui.phrase_len = state.proc.phrase_length

      for _, cut in ipairs(cuts) do
        if state.running then
          send_cut(cut)
          ui.push_cut(cut)
          screen_dirty = true
          clock.sleep(cut.dur)
        end
      end
    end
  end
end

-- ============================================================
-- PARAMS
-- ============================================================

local function init_params()
  params:add_separator("shatter")

  params:add_option("cut_proc", "algorithm",
    cutprocs.PROC_LABELS, 1)
  params:set_action("cut_proc", function(v)
    state.proc_name = cutprocs.PROC_NAMES[v]
    state.proc_label = cutprocs.PROC_LABELS[v]
    ui.active_proc = state.proc_name
    state.proc = nil -- will recreate
    state.algo_sel = 1
  end)

  params:add_control("dry_wet", "dry/wet",
    controlspec.new(0, 1, "lin", 0.01, 0.8))
  params:set_action("dry_wet", function(v)
    state.dry_wet = v
  end)

  params:add_control("input_amp", "input level",
    controlspec.new(0, 2, "lin", 0.01, 1))
  params:set_action("input_amp", function(v)
    engine.capture_amp(v)
  end)

  -- fx params in norns param menu
  params:add_separator("fx")

  for _, fx in ipairs(state.fx) do
    params:add_control(fx.name .. "_mix", fx.name .. " mix",
      controlspec.new(0, 1, "lin", 0.01, 0))
    params:set_action(fx.name .. "_mix", function(v)
      fx.mix = v
      send_fx()
    end)
  end

  -- reverb specifics
  params:add_control("reverb_room", "reverb room",
    controlspec.new(0, 1, "lin", 0.01, 0.6))
  params:set_action("reverb_room", function(v)
    state.fx[1].params.room = v; send_fx()
  end)
  params:add_control("reverb_damp", "reverb damp",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("reverb_damp", function(v)
    state.fx[1].params.damp = v; send_fx()
  end)

  -- comb specifics
  params:add_control("comb_freq", "comb freq",
    controlspec.new(50, 5000, "exp", 1, 800))
  params:set_action("comb_freq", function(v)
    state.fx[2].params.freq = v; send_fx()
  end)
  params:add_control("comb_decay", "comb decay",
    controlspec.new(0.01, 2, "lin", 0.01, 0.2))
  params:set_action("comb_decay", function(v)
    state.fx[2].params.decay = v; send_fx()
  end)

  -- bitcrush specifics
  params:add_control("crush_bits", "crush bits",
    controlspec.new(1, 16, "lin", 1, 12))
  params:set_action("crush_bits", function(v)
    state.fx[3].params.bits = v; send_fx()
  end)
  params:add_control("crush_downsample", "crush downsamp",
    controlspec.new(1, 64, "lin", 1, 1))
  params:set_action("crush_downsample", function(v)
    state.fx[3].params.downsample = v; send_fx()
  end)

  -- ringmod specifics
  params:add_control("ringmod_freq", "ringmod freq",
    controlspec.new(20, 2000, "exp", 1, 440))
  params:set_action("ringmod_freq", function(v)
    state.fx[4].params.freq = v; send_fx()
  end)
  params:add_control("ringmod_depth", "ringmod depth",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("ringmod_depth", function(v)
    state.fx[4].params.depth = v; send_fx()
  end)

  -- brf specifics
  params:add_control("brf_freq", "brf freq",
    controlspec.new(50, 10000, "exp", 1, 1200))
  params:set_action("brf_freq", function(v)
    state.fx[5].params.freq = v; send_fx()
  end)
  params:add_control("brf_rq", "brf rq",
    controlspec.new(0.05, 2, "lin", 0.01, 0.5))
  params:set_action("brf_rq", function(v)
    state.fx[5].params.rq = v; send_fx()
  end)
end

-- ============================================================
-- NORNS CALLBACKS
-- ============================================================

screen_dirty = true

function init()
  math.randomseed(os.time())

  init_params()
  params:default()

  state.tempo = clock.get_tempo()
  state.proc_name = cutprocs.PROC_NAMES[1]
  state.proc_label = cutprocs.PROC_LABELS[1]
  ui.active_proc = state.proc_name

  -- start cut scheduler clock
  state.cut_clock = clock.run(cut_loop)

  -- screen redraw clock
  clock.run(function()
    while true do
      clock.sleep(1 / 15) -- 15fps
      ui.age_cuts(1 / 15)
      if screen_dirty or state.running then
        redraw()
        screen_dirty = false
      end
    end
  end)

  -- tempo sync
  clock.run(function()
    while true do
      state.tempo = clock.get_tempo()
      clock.sleep(0.5)
    end
  end)
end

function cleanup()
  if state.cut_clock then clock.cancel(state.cut_clock) end
end

-- ============================================================
-- ENCODERS & KEYS
-- ============================================================

function enc(n, d)
  if n == 1 then
    -- page navigation
    if d > 0 then ui.next_page()
    elseif d < 0 then ui.prev_page() end
    screen_dirty = true

  elseif n == 2 then
    if ui.page == 1 then
      -- dry/wet
      state.dry_wet = util.clamp(state.dry_wet + d * 0.02, 0, 1)
      params:set("dry_wet", state.dry_wet)
      screen_dirty = true
    elseif ui.page == 2 then
      -- select algo parameter
      local p = state.proc_params[state.proc_name]
      state.algo_sel = util.clamp(state.algo_sel + d, 1, #p)
      screen_dirty = true
    elseif ui.page == 3 then
      -- select fx
      ui.selected_fx = util.clamp(ui.selected_fx + d, 1, #state.fx)
      screen_dirty = true
    end

  elseif n == 3 then
    if ui.page == 1 then
      -- tempo
      state.tempo = util.clamp(state.tempo + d, 20, 300)
      params:set("clock_tempo", state.tempo)
      screen_dirty = true
    elseif ui.page == 2 then
      -- adjust selected algo parameter
      local p = state.proc_params[state.proc_name]
      local pp = p[state.algo_sel]
      if pp then
        pp.val = util.clamp(pp.val + d * pp.step, pp.min, pp.max)
        -- update live proc
        if state.proc then
          state.proc[pp.key] = pp.val
        end
        screen_dirty = true
      end
    elseif ui.page == 3 then
      -- adjust fx mix
      local fx = state.fx[ui.selected_fx]
      fx.mix = util.clamp(fx.mix + d * 0.02, 0, 1)
      params:set(fx.name .. "_mix", fx.mix)
      send_fx()
      screen_dirty = true
    end
  end
end

function key(n, z)
  if z == 0 then return end

  if n == 2 then
    -- start/stop
    state.running = not state.running
    ui.is_running = state.running
    if state.running then
      state.proc = nil -- fresh start
    end
    screen_dirty = true

  elseif n == 3 then
    if ui.page == 1 then
      -- retrigger phrase
      if state.proc then
        state.proc:init_phrase()
      end
    elseif ui.page == 2 then
      -- cycle algorithm
      local idx = 1
      for i, name in ipairs(cutprocs.PROC_NAMES) do
        if name == state.proc_name then idx = i; break end
      end
      idx = (idx % #cutprocs.PROC_NAMES) + 1
      params:set("cut_proc", idx)
    elseif ui.page == 3 then
      -- toggle fx on/off (mix to 0 or 0.5)
      local fx = state.fx[ui.selected_fx]
      if fx.mix > 0 then
        fx.mix = 0
      else
        fx.mix = 0.5
      end
      params:set(fx.name .. "_mix", fx.mix)
      send_fx()
    end
    screen_dirty = true
  end
end

-- ============================================================
-- REDRAW
-- ============================================================

function redraw()
  -- build state for ui
  local p = state.proc_params[state.proc_name]
  local algo_params = {}
  for _, pp in ipairs(p) do
    local display_val = pp.val
    if pp.scale then display_val = display_val * pp.scale end
    table.insert(algo_params, {
      name = pp.name,
      display = string.format(pp.fmt, display_val)
    })
  end

  local fx_states = {}
  for _, fx in ipairs(state.fx) do
    table.insert(fx_states, {
      active = fx.mix > 0,
      mix = fx.mix
    })
  end

  ui.redraw({
    tempo = state.tempo,
    proc_label = state.proc_label,
    algo_params = algo_params,
    algo_sel = state.algo_sel,
    fx_states = fx_states,
  })
end
