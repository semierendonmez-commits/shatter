-- lib/ui.lua
-- shatter: screen drawing module
-- minimalist oled aesthetic, 128x64

local ui = {}

local screen = screen

-- state
ui.page = 1
ui.pages = {"cut", "algo", "fx"}
ui.page_labels = {"CUT", "ALGO", "FX"}
ui.NUM_PAGES = 3

-- animation state
ui.cut_history = {}    -- ring buffer of recent cut events for visualization
ui.cut_hist_max = 32
ui.capture_pos = 0
ui.phrase_pos = 0
ui.phrase_len = 1
ui.blink = false
ui.frame = 0
ui.active_proc = "proc11"
ui.is_running = false
ui.selected_fx = 1

-- fx names for page 3
ui.fx_names = {"reverb", "comb", "bitcrush", "ringmod", "brf"}
ui.fx_labels = {"REV", "COMB", "CRUSH", "RING", "BRF"}

-- ============================================================
-- CUT HISTORY (for visualization)
-- ============================================================

function ui.push_cut(cut_data)
  table.insert(ui.cut_history, {
    dur = cut_data.dur or 0.125,
    stutter = cut_data.stutter or false,
    offset = cut_data.offset or 0,
    rate = cut_data.rate or 1,
    reverse = cut_data.reverse == 1,
    amp = cut_data.amp or 1,
    age = 0
  })
  while #ui.cut_history > ui.cut_hist_max do
    table.remove(ui.cut_history, 1)
  end
end

function ui.age_cuts(dt)
  for i = #ui.cut_history, 1, -1 do
    ui.cut_history[i].age = ui.cut_history[i].age + dt
    if ui.cut_history[i].age > 3 then
      table.remove(ui.cut_history, i)
    end
  end
end

-- ============================================================
-- DRAW FUNCTIONS
-- ============================================================

local function draw_header()
  -- page indicator dots
  for i = 1, ui.NUM_PAGES do
    local x = 56 + (i - 1) * 8
    if i == ui.page then
      screen.level(15)
      screen.rect(x, 1, 5, 3)
      screen.fill()
    else
      screen.level(3)
      screen.rect(x, 1, 5, 3)
      screen.stroke()
    end
  end

  -- page label
  screen.level(12)
  screen.move(1, 6)
  screen.font_size(8)
  screen.text(ui.page_labels[ui.page])

  -- running indicator
  if ui.is_running then
    screen.level(ui.blink and 15 or 5)
    screen.rect(122, 1, 4, 4)
    screen.fill()
  end
end

-- page 1: CUT visualization
local function draw_page_cut(state)
  -- waveform-like cut history display
  local base_y = 38
  local w = 128
  local h = 24

  -- draw buffer position indicator (thin line)
  screen.level(2)
  local cap_x = math.floor(ui.capture_pos * w)
  screen.move(cap_x, 12)
  screen.line(cap_x, 60)
  screen.stroke()

  -- draw cut blocks
  if #ui.cut_history > 0 then
    local total_w = 0
    -- first pass: calculate total width
    for _, c in ipairs(ui.cut_history) do
      total_w = total_w + math.max(2, math.floor(c.dur * 40))
    end

    local x = math.max(0, w - total_w)
    for _, c in ipairs(ui.cut_history) do
      local bw = math.max(2, math.floor(c.dur * 40))
      local bh = math.floor(c.amp * h * 0.8)
      local brightness = math.floor(math.max(1, 15 - c.age * 5))

      if c.amp > 0 then
        screen.level(brightness)

        if c.stutter then
          -- stutter: hatched pattern
          local grain_w = math.max(1, math.floor(bw * 0.3))
          for gx = x, x + bw - 1, grain_w + 1 do
            screen.rect(gx, base_y - bh, math.min(grain_w, x + bw - gx), bh)
            screen.fill()
          end
        else
          -- normal block
          screen.rect(x, base_y - bh, bw - 1, bh)
          screen.fill()
        end

        -- reverse indicator: small triangle
        if c.reverse then
          screen.level(math.floor(brightness * 0.7))
          screen.move(x + bw - 2, base_y - bh - 2)
          screen.line(x + bw - 5, base_y - bh)
          screen.line(x + bw - 2, base_y - bh + 2)
          screen.fill()
        end

        -- rate indicator: dot above if rate ~= 1
        if math.abs(c.rate - 1) > 0.01 then
          screen.level(math.floor(brightness * 0.5))
          local ry = base_y - bh - 3
          if c.rate > 1 then
            screen.pixel(x + math.floor(bw / 2), ry)
            screen.pixel(x + math.floor(bw / 2) + 1, ry)
          else
            screen.pixel(x + math.floor(bw / 2), ry + 1)
          end
          screen.fill()
        end
      end

      x = x + bw
      if x > w then break end
    end
  end

  -- phrase progress bar
  screen.level(4)
  screen.rect(0, 58, 128, 1)
  screen.fill()
  if ui.phrase_len > 0 then
    local pw = math.floor((ui.phrase_pos / ui.phrase_len) * 128)
    screen.level(12)
    screen.rect(0, 57, pw, 3)
    screen.fill()
  end

  -- bottom: algo name + tempo
  screen.level(7)
  screen.move(1, 63)
  screen.font_size(8)
  screen.text(string.upper(ui.active_proc))
  if state then
    screen.move(128, 63)
    screen.text_right(string.format("%.0f bpm", state.tempo or 120))
  end
end

-- page 2: ALGO parameters
local function draw_page_algo(state)
  if not state then return end

  screen.level(10)
  screen.move(1, 18)
  screen.font_size(8)
  screen.text("proc: " .. (state.proc_label or "BBCutProc11"))

  local params = state.algo_params or {}
  local y = 28
  for i, p in ipairs(params) do
    local is_sel = (state.algo_sel == i)
    screen.level(is_sel and 15 or 5)
    screen.move(3, y)
    screen.text(p.name)
    screen.move(80, y)
    screen.text_right(p.display)

    -- selection bracket
    if is_sel then
      screen.level(12)
      screen.move(0, y - 5)
      screen.line(0, y + 1)
      screen.stroke()
    end
    y = y + 10
  end
end

-- page 3: FX chain
local function draw_page_fx(state)
  if not state then return end

  local fx_states = state.fx_states or {}
  local y = 16
  for i, name in ipairs(ui.fx_labels) do
    local is_sel = (ui.selected_fx == i)
    local fx = fx_states[i] or {active = false, mix = 0}
    local mix = fx.mix or 0

    -- selection highlight
    if is_sel then
      screen.level(2)
      screen.rect(0, y - 7, 128, 10)
      screen.fill()
    end

    -- fx name
    screen.level(is_sel and 15 or 5)
    screen.move(3, y)
    screen.text(name)

    -- mix bar
    local bar_x = 40
    local bar_w = 70
    screen.level(3)
    screen.rect(bar_x, y - 5, bar_w, 5)
    screen.stroke()
    if mix > 0 then
      screen.level(is_sel and 12 or 7)
      screen.rect(bar_x, y - 5, math.floor(bar_w * mix), 5)
      screen.fill()
    end

    -- value
    screen.level(is_sel and 15 or 6)
    screen.move(125, y)
    screen.text_right(string.format("%.0f", mix * 100))

    y = y + 10
  end
end

-- ============================================================
-- MAIN DRAW
-- ============================================================

function ui.redraw(state)
  screen.clear()
  ui.frame = ui.frame + 1
  ui.blink = (ui.frame % 20) < 10

  draw_header()

  if ui.page == 1 then
    draw_page_cut(state)
  elseif ui.page == 2 then
    draw_page_algo(state)
  elseif ui.page == 3 then
    draw_page_fx(state)
  end

  screen.update()
end

-- ============================================================
-- PAGE NAVIGATION
-- ============================================================

function ui.next_page()
  ui.page = (ui.page % ui.NUM_PAGES) + 1
end

function ui.prev_page()
  ui.page = ((ui.page - 2) % ui.NUM_PAGES) + 1
end

return ui
