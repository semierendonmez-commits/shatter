# shatter

*algorithmic fractures in the stream of now*

---

shatter listens. shatter cuts. shatter reassembles.

a live audio cutting instrument for monome norns, inspired by nick collins' [bbcut2](https://composerprogrammer.com/bbcut2.html) library — the foundational work on algorithmic breakbeat science. feed it any sound through the inputs and shatter will dissect it in real-time using four distinct cutting algorithms, each with its own personality and set of controllable parameters.

unlike static beat slicers that chop audio into equal pieces, shatter works with the bbcut concept of **phrase → block → cut** hierarchy. cuts are context-aware: their length, repetition count, and probability distributions shift as a phrase progresses. the result is something alive — patterns that breathe, fills that arrive with purpose, and silences that create space.

## requirements

- **norns** (shield, standard, or fates)
- **audio input** (line-in, microphone, or instrument)
- grid not required

## install

from maiden:

```
;install https://github.com/semierendonmez-commits/shatter
```

after installation, restart norns to compile the supercollider engine.

## how it works

shatter continuously captures live audio into a circular buffer (4 seconds). when activated, a cutting algorithm selects slices from this buffer and triggers their playback — sometimes normally, sometimes stuttered, sometimes reversed, sometimes pitch-shifted. five effects processors (reverb, comb filter, bitcrusher, ring modulator, band reject filter) shape the output.

the four cutting algorithms are faithful lua ports of the core bbcut2 procedures:

| algorithm | character | origin |
|-----------|-----------|--------|
| **BBCutProc11** | the original. structured phrases, controllable stutter probability, classic jungle/dnb cutting. predictable yet musical. | collins 2001 |
| **WarpCut** | probability-warped block sizes. distributions shift during the phrase, creating evolving patterns from small granular cuts to wide sweeps. | WarpCutProc1 |
| **SQPusher1** | aggressive. rapid fills that intensify toward phrase endings. acceleration, rolls, mid-fill offset jumps. think drill and bass. | SQPusher1 |
| **SQPusher2** | textural variant. adds grain bursts, pitch shifting, intentional silences. more experimental, bordering on granular territory. | SQPusher2 |

## controls

### global

| control | function |
|---------|----------|
| **E1** | navigate pages (CUT → ALGO → FX) |
| **K2** | start / stop cutting |
| **K3** | context-dependent (see below) |

### page 1: CUT

the main performance view. a real-time visualization of cut events flows across the screen — block widths represent duration, height represents amplitude, hatched blocks indicate stutters, and small triangles mark reversed cuts.

| control | function |
|---------|----------|
| **E2** | dry/wet mix (output level of cuts) |
| **E3** | tempo (syncs to norns global clock) |
| **K3** | retrigger phrase (reset to phrase start) |

the bottom bar shows phrase progress. the thin vertical line shows the circular buffer's current capture position.

### page 2: ALGO

algorithm parameters — what makes each cutting procedure unique.

| control | function |
|---------|----------|
| **E2** | scroll through parameters |
| **E3** | adjust selected parameter |
| **K3** | cycle to next algorithm |

#### BBCutProc11 parameters

| parameter | range | description |
|-----------|-------|-------------|
| subdiv | 2–32 | rhythmic resolution. 8 = quavers, 16 = semiquavers, 32 = demisemiquavers. higher = faster potential cuts |
| bars | 1–16 | phrase length in bars. shorter phrases cycle faster |
| repeats | 1–8 | maximum block repetitions. higher = more stutter potential |
| stut.prob | 0–100% | probability that a block stutters (rapid repeat of a sub-slice) |
| stut.spd | 0.5–4.0 | playback speed multiplier during stutter |
| offset | 0–100% | probability of jumping to a random buffer position (vs. sequential reading) |

#### WarpCut parameters

| parameter | range | description |
|-----------|-------|-------------|
| subdiv | 2–32 | rhythmic resolution |
| bars | 1–16 | phrase length |
| warp | 0–100% | distribution bias. 0% = mostly small cuts, 100% = mostly large cuts |
| deform | 0–100% | how much the distribution shifts as the phrase progresses |
| offset | 0–100% | random jump probability |

#### SQPusher1 parameters

| parameter | range | description |
|-----------|-------|-------------|
| subdiv | 4–32 | rhythmic resolution (default 16 for fast cutting) |
| bars | 1–8 | phrase length |
| fill | 0–100% | probability of a rapid-fire fill section. increases toward phrase end |
| accel | 0–100% | chance of speed changes within fills |
| roll | 0–100% | chance of roll/stutter within fills |
| offset | 0–100% | random jump probability |

#### SQPusher2 parameters

| parameter | range | description |
|-----------|-------|-------------|
| subdiv | 4–32 | rhythmic resolution |
| bars | 1–8 | phrase length |
| grain | 0–100% | probability of micro-grain burst events |
| pitch | 0–100% | chance of pitch-shifted playback (0.5x, 0.75x, 1.5x, 2x) |
| silence | 0–100% | probability of intentional rests (negative space) |
| offset | 0–100% | random jump probability |

### page 3: FX

five effect processors in series. each has an independent mix control.

| control | function |
|---------|----------|
| **E2** | select effect slot |
| **E3** | adjust mix (0–100%) |
| **K3** | toggle effect on/off (0% ↔ 50%) |

| effect | description | additional params (in norns param menu) |
|--------|-------------|----------------------------------------|
| **REV** | stereo reverb | room size, damping |
| **COMB** | comb filter — metallic resonance | frequency, decay time |
| **CRUSH** | bitcrusher + sample rate reduction | bit depth (1–16), downsample factor |
| **RING** | ring modulator — bell/metallic tones | modulation frequency, depth |
| **BRF** | band reject filter — notch/phaser-like | center frequency, bandwidth (rq) |

all effect parameters are also available in the norns global params menu (accessible via K1 > PARAMETERS) for midi mapping, pset saving, and fine control.

## screen guide

```
page 1 (CUT):
┌────────────────────────────────────┐
│ CUT           ■ □ □            ●   │  ← page dots, run indicator
│                                    │
│  │                    ▓▓ ░░ ▓▓▓▓   │  ← cut blocks (height=amp)
│  │              ▓▓▓▓ ▓▓ ░░ ▓▓▓▓   │     ▓ = normal, ░ = stutter
│  │        ▓▓▓▓ ▓▓▓▓ ▓▓ ░░ ▓▓▓▓   │     ▲ = reversed
│  │                                 │
│ ═══════════════════                │  ← phrase progress bar
│ PROC11                    120 bpm  │
└────────────────────────────────────┘

page 2 (ALGO):
┌────────────────────────────────────┐
│ ALGO          □ ■ □                │
│                                    │
│ proc: BBCutProc11                  │
│ │ subdiv                        8  │  ← selected param
│   bars                          4  │
│   repeats                       2  │
│   stut.prob                   20%  │
│   stut.spd                   2.00  │
└────────────────────────────────────┘

page 3 (FX):
┌────────────────────────────────────┐
│ FX            □ □ ■                │
│                                    │
│  REV   [████████░░░░░░░░░░]   40   │
│  COMB  [░░░░░░░░░░░░░░░░░░]    0   │
│  CRUSH [██████░░░░░░░░░░░░]   30   │  ← selected
│  RING  [░░░░░░░░░░░░░░░░░░]    0   │
│  BRF   [░░░░░░░░░░░░░░░░░░]    0   │
└────────────────────────────────────┘
```

## philosophy

the bbcut library originated from nick collins' research into algorithmic composition methods for breakbeat science. the core idea is the separation of **cut procedure** (the algorithm deciding what to cut) from **cut synthesis** (how the cut sounds). this separation means any algorithm can be applied to any source material.

shatter brings this philosophy to norns. the algorithms don't know or care what audio is passing through the inputs — a drum machine, a synthesizer, a guitar, a field recording, a voice. the cutting procedures operate on abstract rhythmic structures (phrases made of blocks made of cuts), and the results emerge from the collision of algorithm and material.

some starting points for exploration:

- feed a drum loop and use **BBCutProc11** for classic breakbeat manipulation
- feed a sustained pad or drone into **SQPusher2** for granular texture
- feed a voice into **WarpCut** with high deform for evolving vocal stutters
- combine **SQPusher1** with the bitcrusher for aggressive drill-and-bass
- set all algorithms to low subdivision (2–4) for slow, deliberate cuts
- set subdivision to 32 and increase stutter probability for pure granular territory

## file structure

```
shatter/
├── shatter.lua             main script
├── lib/
│   ├── Engine_Shatter.sc   supercollider engine (audio capture + playback + fx)
│   ├── cutprocs.lua        bbcut algorithm implementations (proc11, warpcut, sqpush1/2)
│   └── ui.lua              screen drawing (128x64 oled)
└── README.md               this file
```

## credits & references

- **nick collins** — [bbcut2 library](https://composerprogrammer.com/bbcut2.html), the foundational research and code that made algorithmic breakbeat cutting possible. all four cutting algorithms in shatter are lua ports of concepts from the bbcut library.
- **nick collins** — *algorithmic composition methods for breakbeat science* (2001), *further automatic breakbeat cutting methods* (2001), *the bbcut library* (icmc 2002)
- **livecut** (mdsp/smartelectronix) — the vst plugin that first made bbcut-style cutting accessible outside supercollider, and direct inspiration for this project's "live audio processing" approach
- **monome** / **norns community** — for the platform and the ecosystem
- **@schollz** — [amen](https://github.com/schollz/amen) script, for demonstrating elegant loop mangling on norns with supercollider
- **lines community** — for the ongoing conversation about sound, code, and art

## license

gpl-3.0 (in keeping with the bbcut2 library's gnu gpl license)

---

*"the library is based upon a specific hierarchy of phrase/block/cut sufficient to implement a wide variety of cut procedures."*
— nick collins, the bbcut library (2002)
