// lib/Engine_Shatter.sc
// shatter: bbcut-inspired live audio cutting engine for norns
// audio capture -> circular buffer -> algorithmic slice playback -> fx chain

Engine_Shatter : CroneEngine {

  var <capture_synth, <play_synth;
  var <capture_buf;
  var <fx_group, <play_group, <capture_group;
  var <fx_reverb, <fx_comb, <fx_bitcrush, <fx_ringmod, <fx_brf;
  var <fx_bus;
  var <buf_dur = 4.0; // seconds of circular buffer
  var <capture_pos_bus;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  alloc {
    var server = context.server;

    // -- buses --
    fx_bus = Bus.audio(server, 2);
    capture_pos_bus = Bus.control(server, 1);

    // -- groups (order matters for signal flow) --
    capture_group = Group.new(context.xg, \addToHead);
    play_group = Group.new(context.xg, \addAfter, capture_group);
    fx_group = Group.new(context.xg, \addAfter, play_group);

    // -- buffer: circular capture --
    capture_buf = Buffer.alloc(server, server.sampleRate * buf_dur, 2);

    // -- SynthDefs --

    // capture live input into circular buffer
    SynthDef(\shatter_capture, { |in_l, in_r, buf, rate=1, amp=1|
      var sig = [In.ar(in_l), In.ar(in_r)] * amp;
      var phase = Phasor.ar(0, BufRateScale.kr(buf) * rate,
        0, BufFrames.kr(buf));
      BufWr.ar(sig, buf, phase);
      Out.kr(capture_pos_bus.index, phase / BufFrames.kr(buf));
    }).add;

    // slice playback from buffer with envelope
    SynthDef(\shatter_play, { |out, buf, start=0, dur=0.125,
      rate=1, amp=1, pan=0, attack=0.002, release=0.005,
      reverse=0, gate=1|
      var frames = BufFrames.kr(buf);
      var play_rate = rate * BufRateScale.kr(buf) *
        Select.kr(reverse, [1, -1]);
      var start_frame = start * frames;
      var phase = Phasor.ar(0, play_rate, 0,
        dur * SampleRate.ir * rate.abs);
      var read_phase = Wrap.ar(start_frame + phase, 0, frames);
      var sig = BufRd.ar(2, buf, read_phase, 0, 4);
      var env = EnvGen.kr(
        Env.linen(attack, dur - attack - release, release, 1, \sin),
        gate, doneAction: 2);
      sig = sig * env * amp;
      sig = Balance2.ar(sig[0], sig[1], pan);
      Out.ar(out, sig);
    }).add;

    // stutter: rapid repeat of tiny slice
    SynthDef(\shatter_stutter, { |out, buf, start=0, grain_dur=0.03125,
      repeats=4, rate=1, amp=1, pan=0, total_dur=0.125|
      var frames = BufFrames.kr(buf);
      var play_rate = rate * BufRateScale.kr(buf);
      var start_frame = start * frames;
      var grain_frames = grain_dur * SampleRate.ir;
      var phase = Phasor.ar(0, play_rate, 0, grain_frames);
      var read_phase = Wrap.ar(start_frame + phase, 0, frames);
      var sig = BufRd.ar(2, buf, read_phase, 0, 4);
      var env = EnvGen.kr(
        Env.linen(0.001, total_dur - 0.002, 0.001, 1, \sin),
        doneAction: 2);
      sig = sig * env * amp;
      sig = Balance2.ar(sig[0], sig[1], pan);
      Out.ar(out, sig);
    }).add;

    // -- FX SynthDefs --

    // reverb fx
    SynthDef(\shatter_fx_reverb, { |in_bus, out, mix=0.2,
      room=0.6, damp=0.5, amp=1|
      var sig = In.ar(in_bus, 2);
      var wet = FreeVerb2.ar(sig[0], sig[1], mix, room, damp);
      ReplaceOut.ar(in_bus, wet * amp);
    }).add;

    // comb filter fx
    SynthDef(\shatter_fx_comb, { |in_bus, freq=800,
      decay=0.2, mix=0.3|
      var sig = In.ar(in_bus, 2);
      var wet = CombL.ar(sig, 0.2,
        freq.reciprocal.clip(0.0001, 0.2), decay);
      ReplaceOut.ar(in_bus, XFade2.ar(sig, wet, mix * 2 - 1));
    }).add;

    // bitcrusher fx
    SynthDef(\shatter_fx_bitcrush, { |in_bus, bits=12,
      downsample=1, mix=0.5|
      var sig = In.ar(in_bus, 2);
      var crushed = sig.round(2.pow(bits.neg));
      var decimated = Latch.ar(crushed,
        Impulse.ar(SampleRate.ir / downsample.max(1)));
      ReplaceOut.ar(in_bus, XFade2.ar(sig, decimated, mix * 2 - 1));
    }).add;

    // ring modulator fx
    SynthDef(\shatter_fx_ringmod, { |in_bus, freq=440,
      depth=0.5, mix=0.3|
      var sig = In.ar(in_bus, 2);
      var mod = SinOsc.ar(freq, 0, depth, 1 - depth);
      var wet = sig * mod;
      ReplaceOut.ar(in_bus, XFade2.ar(sig, wet, mix * 2 - 1));
    }).add;

    // band reject filter fx
    SynthDef(\shatter_fx_brf, { |in_bus, freq=1200,
      rq=0.5, mix=0.5|
      var sig = In.ar(in_bus, 2);
      var wet = BRF.ar(sig, freq.clip(20, 18000), rq.clip(0.01, 2));
      ReplaceOut.ar(in_bus, XFade2.ar(sig, wet, mix * 2 - 1));
    }).add;

    // output mixer: fx_bus -> main out
    SynthDef(\shatter_mixer, { |in_bus, out, amp=1, dry_wet=0.8|
      var fx_sig = In.ar(in_bus, 2);
      Out.ar(out, fx_sig * amp);
    }).add;

    server.sync;

    // -- instantiate capture --
    // context.in_b is an Array of two Bus objects [left, right]
    capture_synth = Synth(\shatter_capture, [
      \in_l, context.in_b[0].index,
      \in_r, context.in_b[1].index,
      \buf, capture_buf,
      \amp, 1
    ], target: capture_group);

    // -- instantiate fx chain (all start bypassed) --
    fx_reverb = Synth(\shatter_fx_reverb, [
      \in_bus, context.out_b,
      \mix, 0, \room, 0.6, \damp, 0.5, \amp, 1
    ], target: fx_group);

    fx_comb = Synth(\shatter_fx_comb, [
      \in_bus, context.out_b,
      \freq, 800, \decay, 0.2, \mix, 0
    ], target: fx_group, addAction: \addAfter);

    fx_bitcrush = Synth(\shatter_fx_bitcrush, [
      \in_bus, context.out_b,
      \bits, 12, \downsample, 1, \mix, 0
    ], target: fx_group, addAction: \addAfter);

    fx_ringmod = Synth(\shatter_fx_ringmod, [
      \in_bus, context.out_b,
      \freq, 440, \depth, 0.5, \mix, 0
    ], target: fx_group, addAction: \addAfter);

    fx_brf = Synth(\shatter_fx_brf, [
      \in_bus, context.out_b,
      \freq, 1200, \rq, 0.5, \mix, 0
    ], target: fx_group, addAction: \addAfter);

    server.sync;

    // =====================
    // COMMANDS (Lua -> SC)
    // =====================

    // -- play a slice --
    // args: start(0-1), dur(sec), rate, amp, pan, reverse(0/1)
    this.addCommand("play_slice", "ffffff", { |msg|
      Synth(\shatter_play, [
        \out, context.out_b,
        \buf, capture_buf,
        \start, msg[1],
        \dur, msg[2],
        \rate, msg[3],
        \amp, msg[4],
        \pan, msg[5],
        \reverse, msg[6]
      ], target: play_group);
    });

    // -- stutter slice --
    this.addCommand("play_stutter", "fffff", { |msg|
      Synth(\shatter_stutter, [
        \out, context.out_b,
        \buf, capture_buf,
        \start, msg[1],
        \grain_dur, msg[2],
        \rate, msg[3],
        \amp, msg[4],
        \total_dur, msg[5]
      ], target: play_group);
    });

    // -- capture control --
    this.addCommand("capture_amp", "f", { |msg|
      capture_synth.set(\amp, msg[1]);
    });

    // -- fx: reverb --
    this.addCommand("fx_reverb_mix", "f", { |msg|
      fx_reverb.set(\mix, msg[1]);
    });
    this.addCommand("fx_reverb_room", "f", { |msg|
      fx_reverb.set(\room, msg[1]);
    });
    this.addCommand("fx_reverb_damp", "f", { |msg|
      fx_reverb.set(\damp, msg[1]);
    });

    // -- fx: comb --
    this.addCommand("fx_comb_freq", "f", { |msg|
      fx_comb.set(\freq, msg[1]);
    });
    this.addCommand("fx_comb_decay", "f", { |msg|
      fx_comb.set(\decay, msg[1]);
    });
    this.addCommand("fx_comb_mix", "f", { |msg|
      fx_comb.set(\mix, msg[1]);
    });

    // -- fx: bitcrush --
    this.addCommand("fx_bitcrush_bits", "f", { |msg|
      fx_bitcrush.set(\bits, msg[1]);
    });
    this.addCommand("fx_bitcrush_downsample", "f", { |msg|
      fx_bitcrush.set(\downsample, msg[1]);
    });
    this.addCommand("fx_bitcrush_mix", "f", { |msg|
      fx_bitcrush.set(\mix, msg[1]);
    });

    // -- fx: ringmod --
    this.addCommand("fx_ringmod_freq", "f", { |msg|
      fx_ringmod.set(\freq, msg[1]);
    });
    this.addCommand("fx_ringmod_depth", "f", { |msg|
      fx_ringmod.set(\depth, msg[1]);
    });
    this.addCommand("fx_ringmod_mix", "f", { |msg|
      fx_ringmod.set(\mix, msg[1]);
    });

    // -- fx: brf --
    this.addCommand("fx_brf_freq", "f", { |msg|
      fx_brf.set(\freq, msg[1]);
    });
    this.addCommand("fx_brf_rq", "f", { |msg|
      fx_brf.set(\rq, msg[1]);
    });
    this.addCommand("fx_brf_mix", "f", { |msg|
      fx_brf.set(\mix, msg[1]);
    });

    // -- poll: capture position --
    this.addPoll("capture_pos", {
      capture_pos_bus.getSynchronous;
    });

    postln("Engine_Shatter: loaded.");
  }

  free {
    capture_synth.free;
    fx_reverb.free;
    fx_comb.free;
    fx_bitcrush.free;
    fx_ringmod.free;
    fx_brf.free;
    capture_buf.free;
    fx_bus.free;
    capture_pos_bus.free;
    capture_group.free;
    play_group.free;
    fx_group.free;
  }
}
