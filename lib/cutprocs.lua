-- lib/cutprocs.lua
-- faithful lua port of bbcut2 cut procedures
-- phrase/block/cut hierarchy from nick collins' bbcut library

local cutprocs = {}

-- ============================================================
-- UTILITY
-- ============================================================

local function coin(prob)
  return math.random() < prob
end

local function choose(t)
  return t[math.random(#t)]
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- ============================================================
-- BASE CUT PROCEDURE
-- ============================================================
-- all procedures follow the bbcut hierarchy:
--   phrase -> blocks -> cuts
-- a phrase has N bars, each bar has M subdivisions.
-- a block is a contiguous chunk whose size is measured in subdivs.
-- each block may repeat (stutter) or be a single play.

local CutProc = {}
CutProc.__index = CutProc

function CutProc:new()
  local o = setmetatable({}, self)
  o.sdiv = 8           -- subdivisions per bar
  o.barlength = 4      -- beats per bar (in subdivs of a beat, usually 4)
  o.phrasebars = 4     -- bars per phrase
  o.phrase_pos = 0      -- current position in phrase (in subdivs)
  o.phrase_length = 0   -- total subdivs in phrase
  o.block_remaining = 0
  o.cut_list = {}       -- generated list of {dur, repeats, offset, rate, reverse}
  return o
end

function CutProc:init_phrase()
  self.phrase_length = self.sdiv * self.barlength * self.phrasebars
  self.phrase_pos = 0
end

function CutProc:is_phrase_done()
  return self.phrase_pos >= self.phrase_length
end

-- ============================================================
-- BBCutProc11 (the original breakbeat cutter)
-- ============================================================
-- parameters:
--   sdiv:           subdivision (8 = quaver resolution)
--   barlength:      bar length in subdivisions (default 4)
--   phrasebars:     bars per phrase (default 4)
--   numrepeats:     max repeats of a block (default 2)
--   stutterchance:  probability of stutter (0..1)
--   stutterspeed:   speed multiplier for stutter (default 2)
--   stutterarea:    fraction of block available for stutter (default 0.5)

local Proc11 = setmetatable({}, {__index = CutProc})
Proc11.__index = Proc11

function Proc11:new(params)
  local o = CutProc.new(self)
  params = params or {}
  o.sdiv = params.sdiv or 8
  o.barlength = params.barlength or 4
  o.phrasebars = params.phrasebars or 4
  o.numrepeats = params.numrepeats or 2
  o.stutterchance = params.stutterchance or 0.2
  o.stutterspeed = params.stutterspeed or 2
  o.stutterarea = params.stutterarea or 0.5
  o.offset_chance = params.offset_chance or 0.3
  return o
end

-- generate next block of cuts
-- returns table: { {dur_subdivs, repeats, offset, playrate, reverse}, ... }
function Proc11:next_block(subdiv_dur)
  local cuts = {}
  if self:is_phrase_done() then
    self:init_phrase()
  end

  local remaining = self.phrase_length - self.phrase_pos

  -- choose block size: 1, 2, or 4 subdivisions (weighted)
  local sizes = {1, 1, 2, 2, 2, 4, 4}
  local block_size = choose(sizes)
  block_size = math.min(block_size, remaining)

  if block_size <= 0 then
    self:init_phrase()
    return self:next_block(subdiv_dur)
  end

  -- how many repeats?
  local reps = 1
  if self.numrepeats > 1 and coin(0.4) then
    reps = math.random(1, self.numrepeats)
    -- make sure we don't exceed phrase
    local total = block_size * reps
    while total > remaining and reps > 1 do
      reps = reps - 1
      total = block_size * reps
    end
  end

  -- stutter?
  local is_stutter = coin(self.stutterchance) and block_size >= 2
  local stutter_grain = nil
  if is_stutter then
    stutter_grain = math.max(1, math.floor(block_size * self.stutterarea))
  end

  -- random offset jump?
  local offset = 0
  if coin(self.offset_chance) then
    offset = math.random() -- 0..1 position in buffer
  end

  -- reverse chance
  local rev = coin(0.08) and 1 or 0

  for i = 1, reps do
    table.insert(cuts, {
      dur = block_size * subdiv_dur,
      stutter = is_stutter,
      stutter_grain = stutter_grain and (stutter_grain * subdiv_dur) or nil,
      offset = offset,
      rate = is_stutter and self.stutterspeed or 1,
      reverse = rev,
      amp = 1.0 - ((i - 1) / (reps * 3)) -- gentle fade on repeats
    })
  end

  self.phrase_pos = self.phrase_pos + (block_size * reps)
  return cuts
end

cutprocs.Proc11 = Proc11

-- ============================================================
-- WarpCutProc1 (probability-warped block sizes)
-- ============================================================
-- uses weighted probability distributions for block size
-- distributions shift during the phrase for evolving patterns

local WarpCut = setmetatable({}, {__index = CutProc})
WarpCut.__index = WarpCut

function WarpCut:new(params)
  local o = CutProc.new(self)
  params = params or {}
  o.sdiv = params.sdiv or 8
  o.barlength = params.barlength or 4
  o.phrasebars = params.phrasebars or 2
  o.warp = params.warp or 0.5        -- 0=small cuts, 1=large cuts
  o.deform = params.deform or 0.3    -- probability distortion amount
  o.offset_chance = params.offset_chance or 0.5
  return o
end

function WarpCut:next_block(subdiv_dur)
  local cuts = {}
  if self:is_phrase_done() then
    self:init_phrase()
  end

  local remaining = self.phrase_length - self.phrase_pos
  local position_ratio = self.phrase_pos / math.max(1, self.phrase_length)

  -- warp the probability distribution based on phrase position
  local w = self.warp + (position_ratio * self.deform)
  w = clamp(w, 0, 1)

  -- possible block sizes and their base weights
  local sizes =   {1,   2,   3,   4,   6,   8}
  local weights = {1-w, 0.8, 0.6, 0.5, 0.3*w, 0.2*w}

  -- weighted random selection
  local total_w = 0
  for _, v in ipairs(weights) do total_w = total_w + math.max(0.01, v) end
  local r = math.random() * total_w
  local acc = 0
  local block_size = sizes[1]
  for i, v in ipairs(weights) do
    acc = acc + math.max(0.01, v)
    if r <= acc then
      block_size = sizes[i]
      break
    end
  end

  block_size = math.min(block_size, remaining)
  if block_size <= 0 then
    self:init_phrase()
    return self:next_block(subdiv_dur)
  end

  -- repeats based on warp
  local reps = 1
  if coin(0.3 + w * 0.3) and block_size <= 2 then
    reps = math.random(2, 4)
    while block_size * reps > remaining do reps = reps - 1 end
    reps = math.max(1, reps)
  end

  local offset = coin(self.offset_chance) and math.random() or 0
  local rate = 1
  if coin(0.15) then
    rate = choose({0.5, 1, 1, 2, 1.5})
  end

  for i = 1, reps do
    table.insert(cuts, {
      dur = block_size * subdiv_dur,
      stutter = false,
      offset = offset,
      rate = rate,
      reverse = coin(0.06) and 1 or 0,
      amp = 1.0
    })
  end

  self.phrase_pos = self.phrase_pos + (block_size * reps)
  return cuts
end

cutprocs.WarpCut = WarpCut

-- ============================================================
-- SQPusher1 (squarepusher-inspired aggressive cutting)
-- ============================================================
-- characterized by rapid subdivisions, fills, and
-- sudden tempo-doubled bursts

local SQPush1 = setmetatable({}, {__index = CutProc})
SQPush1.__index = SQPush1

function SQPush1:new(params)
  local o = CutProc.new(self)
  params = params or {}
  o.sdiv = params.sdiv or 16       -- higher subdivision = faster cuts
  o.barlength = params.barlength or 4
  o.phrasebars = params.phrasebars or 2
  o.fill_chance = params.fill_chance or 0.35
  o.accel_chance = params.accel_chance or 0.2
  o.roll_chance = params.roll_chance or 0.25
  o.offset_chance = params.offset_chance or 0.6
  return o
end

function SQPush1:next_block(subdiv_dur)
  local cuts = {}
  if self:is_phrase_done() then
    self:init_phrase()
  end

  local remaining = self.phrase_length - self.phrase_pos
  local pos_ratio = self.phrase_pos / math.max(1, self.phrase_length)

  -- fill probability increases toward end of phrase
  local fill_p = self.fill_chance + (pos_ratio * 0.3)

  if coin(fill_p) and remaining >= 4 then
    -- FILL: rapid-fire small cuts
    local fill_len = math.min(math.random(4, 8), remaining)
    local offset = coin(self.offset_chance) and math.random() or 0
    for i = 1, fill_len do
      local rate = 1
      if coin(self.accel_chance) then
        rate = choose({1.5, 2, 0.5})
      end
      table.insert(cuts, {
        dur = subdiv_dur,
        stutter = coin(self.roll_chance),
        stutter_grain = subdiv_dur * 0.5,
        offset = offset,
        rate = rate,
        reverse = coin(0.1) and 1 or 0,
        amp = 0.8 + math.random() * 0.2
      })
      -- occasionally shift offset mid-fill
      if coin(0.3) then offset = math.random() end
    end
    self.phrase_pos = self.phrase_pos + fill_len
  else
    -- NORMAL: standard block
    local block_size = choose({1, 2, 2, 3, 4})
    block_size = math.min(block_size, remaining)
    if block_size <= 0 then
      self:init_phrase()
      return self:next_block(subdiv_dur)
    end

    local reps = 1
    if coin(0.3) and block_size <= 2 then
      reps = math.random(2, 3)
      while block_size * reps > remaining do reps = reps - 1 end
      reps = math.max(1, reps)
    end

    local offset = coin(self.offset_chance) and math.random() or 0

    for i = 1, reps do
      table.insert(cuts, {
        dur = block_size * subdiv_dur,
        stutter = false,
        offset = offset,
        rate = 1,
        reverse = coin(0.05) and 1 or 0,
        amp = 1.0
      })
    end
    self.phrase_pos = self.phrase_pos + (block_size * reps)
  end

  return cuts
end

cutprocs.SQPush1 = SQPush1

-- ============================================================
-- SQPusher2 (variation: more textural, granular tendencies)
-- ============================================================
-- adds pitch shifting, amplitude modulation, and
-- micro-grain bursts alongside the aggressive cutting

local SQPush2 = setmetatable({}, {__index = CutProc})
SQPush2.__index = SQPush2

function SQPush2:new(params)
  local o = CutProc.new(self)
  params = params or {}
  o.sdiv = params.sdiv or 16
  o.barlength = params.barlength or 4
  o.phrasebars = params.phrasebars or 2
  o.grain_chance = params.grain_chance or 0.3
  o.pitch_chance = params.pitch_chance or 0.25
  o.silence_chance = params.silence_chance or 0.1
  o.offset_chance = params.offset_chance or 0.7
  return o
end

function SQPush2:next_block(subdiv_dur)
  local cuts = {}
  if self:is_phrase_done() then
    self:init_phrase()
  end

  local remaining = self.phrase_length - self.phrase_pos

  -- silence (rest) chance
  if coin(self.silence_chance) then
    local rest_len = math.min(choose({1, 2}), remaining)
    table.insert(cuts, {
      dur = rest_len * subdiv_dur,
      stutter = false,
      offset = 0,
      rate = 1,
      reverse = 0,
      amp = 0, -- silence
      is_rest = true
    })
    self.phrase_pos = self.phrase_pos + rest_len
    return cuts
  end

  -- grain burst?
  if coin(self.grain_chance) and remaining >= 3 then
    local burst_len = math.min(math.random(3, 6), remaining)
    local offset = math.random()
    local base_rate = coin(self.pitch_chance) and choose({0.5, 0.75, 1.5, 2}) or 1
    for i = 1, burst_len do
      local rate = base_rate
      if coin(0.2) then rate = rate * choose({0.5, 1, 2}) end
      table.insert(cuts, {
        dur = subdiv_dur,
        stutter = true,
        stutter_grain = subdiv_dur * choose({0.25, 0.5, 0.33}),
        offset = offset,
        rate = clamp(rate, 0.25, 4),
        reverse = coin(0.15) and 1 or 0,
        amp = 0.6 + math.random() * 0.4
      })
    end
    self.phrase_pos = self.phrase_pos + burst_len
    return cuts
  end

  -- standard block with pitch variation
  local block_size = choose({1, 2, 2, 4})
  block_size = math.min(block_size, remaining)
  if block_size <= 0 then
    self:init_phrase()
    return self:next_block(subdiv_dur)
  end

  local offset = coin(self.offset_chance) and math.random() or 0
  local rate = 1
  if coin(self.pitch_chance) then
    rate = choose({0.5, 0.75, 1, 1, 1.5, 2})
  end

  local reps = 1
  if coin(0.35) and block_size <= 2 then
    reps = math.random(2, 4)
    while block_size * reps > remaining do reps = reps - 1 end
    reps = math.max(1, reps)
  end

  for i = 1, reps do
    table.insert(cuts, {
      dur = block_size * subdiv_dur,
      stutter = false,
      offset = offset,
      rate = rate,
      reverse = coin(0.08) and 1 or 0,
      amp = 1.0
    })
  end
  self.phrase_pos = self.phrase_pos + (block_size * reps)
  return cuts
end

cutprocs.SQPush2 = SQPush2

-- ============================================================
-- FACTORY
-- ============================================================

cutprocs.PROC_NAMES = {"proc11", "warpcut", "sqpush1", "sqpush2"}
cutprocs.PROC_LABELS = {"BBCutProc11", "WarpCut", "SQPusher1", "SQPusher2"}

function cutprocs.create(name, params)
  if name == "proc11" then return Proc11:new(params)
  elseif name == "warpcut" then return WarpCut:new(params)
  elseif name == "sqpush1" then return SQPush1:new(params)
  elseif name == "sqpush2" then return SQPush2:new(params)
  end
  return Proc11:new(params)
end

return cutprocs
