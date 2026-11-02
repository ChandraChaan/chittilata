"""Synthesises Chittilata's original sounds and music (no third-party assets).

Run: python3 -m pip install numpy && python3 tool/make_sounds.py
     -> writes assets/sounds/*.wav

Everything is built from oscillators, filtered noise and a small convolution
reverb, so the app ships no sampled or licensed audio. UI sounds are short and
crisp (a tactile click with a bright metallic tick, like big mobile games);
the two music loops are a festive "menu" theme and a lighter in-game groove
with tabla-style drums, a plucked santoor-like lead and a bansuri-like flute.
"""
import os
import struct
import wave

import numpy as np

SR = 44100  # UI sounds
MSR = 32000  # music loops (smaller files, still full and warm)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
rng = np.random.default_rng(7)


# --------------------------------------------------------------- building blocks
def t_axis(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def env_exp(dur, decay, attack=0.002, sr=SR):
    t = t_axis(dur, sr)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    e = a * np.exp(-t / decay)
    # Always land on silence: an envelope that stops short of zero clicks.
    k = max(int(0.005 * sr), len(e) // 6)
    e[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    return e


def env_adsr(dur, a=0.01, d=0.1, s=0.7, r=0.2, sr=SR):
    n = int(dur * sr)
    t = np.arange(n) / sr
    e = np.where(t < a, t / a, s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = int(r * sr)
    if rel and rel < n:
        e[-rel:] *= np.linspace(1, 0, rel) ** 2
    return e


def osc(freq, dur, shape="sine", sr=SR, phase=0.0, vibrato=(0, 0)):
    """freq may be a number or an array (for pitch sweeps)."""
    n = int(dur * sr)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,)).copy()
    if vibrato[1]:
        f *= 1 + vibrato[1] * np.sin(2 * np.pi * vibrato[0] * np.arange(n) / sr)
    ph = 2 * np.pi * np.cumsum(f) / sr + phase
    if shape == "sine":
        return np.sin(ph)
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if shape == "saw":  # band-limited-ish: 12 harmonics
        return sum(np.sin(k * ph) / k for k in range(1, 13)) * 0.6
    if shape == "square":
        return sum(np.sin(k * ph) / k for k in range(1, 14, 2)) * 0.9
    raise ValueError(shape)


def sweep(f0, f1, dur, curve=3.0, sr=SR):
    t = np.linspace(0, 1, int(dur * sr))
    return f1 + (f0 - f1) * np.exp(-curve * t) if curve else np.linspace(f0, f1, len(t))


def noise(dur, sr=SR):
    return rng.uniform(-1, 1, int(dur * sr))


def onepole_lp(x, cutoff, sr=SR):
    """Simple low-pass; cutoff may be a number or an array."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / sr)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def hp(x, cutoff, sr=SR):
    return x - onepole_lp(x, cutoff, sr)


def bandnoise(dur, lo, hi, sr=SR):
    n = noise(dur, sr)
    return hp(onepole_lp(onepole_lp(n, hi, sr), hi, sr), lo, sr)


def at(x, secs, sr=SR):
    return np.concatenate([np.zeros(int(secs * sr)), x])


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = np.zeros(n)
    for t in tracks:
        out[: len(t)] += t
    return out


def reverb(x, secs=0.6, wet=0.2, bright=6000, sr=SR, loop=False):
    """Convolution with decaying filtered noise: a soft, roomy tail."""
    n = int(secs * sr)
    ir = noise(secs, sr) * np.exp(-np.arange(n) / sr / (secs / 6.0))
    ir = onepole_lp(ir, bright, sr)
    ir[: int(0.012 * sr)] = 0  # pre-delay
    ir /= np.sqrt(np.sum(ir**2)) + 1e-9
    size = len(x) + n
    nfft = 1 << (size - 1).bit_length()
    tail = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[:size]
    if loop:  # wrap the tail onto the start so the loop is seamless
        body = tail[: len(x)].copy()
        body[: n] += tail[len(x):]
        return x * (1 - wet) + body * wet * 1.6
    out = np.zeros(size)
    out[: len(x)] += x * (1 - wet)
    return out + tail * wet * 1.6


def fade_out(x, secs, sr=SR):
    n = min(len(x), int(secs * sr))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n) ** 2
    return x


def trim(x, thresh=1e-4, sr=SR):
    idx = np.nonzero(np.abs(x) > thresh * np.max(np.abs(x)))[0]
    return fade_out(x[: idx[-1] + 1 if len(idx) else len(x)], 0.01, sr)


def write(name, x, peak=0.89, sr=SR, loud=0.3):
    """Normalises to `peak`, then caps the loudest 100 ms at `loud` RMS so
    dense sounds (horns, buzzes) don't jump out over clicks and bells."""
    x = np.asarray(x, dtype=float)
    x = x - np.mean(x)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    win = int(0.1 * sr)
    if len(x) >= win:
        k = len(x) // win
        top = np.sqrt(np.mean(x[: k * win].reshape(k, win) ** 2, 1)).max()
        if top > loud:
            x *= loud / top
    pcm = np.clip(x * 32767, -32768, 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def note(n):
    """MIDI note number -> Hz."""
    return 440.0 * 2 ** ((n - 69) / 12)


# ------------------------------------------------------------------ instruments
def click_transient(vol=1.0, sr=SR):
    return hp(noise(0.006, sr), 2500, sr) * np.linspace(1, 0, int(0.006 * sr)) ** 2 * vol


def metal(freq, dur=0.12, vol=0.3, sr=SR):
    """Inharmonic partials: the bright 'ting' on top of a game button."""
    parts = [(1.0, 1.0), (2.76, 0.5), (5.40, 0.25), (8.93, 0.12)]
    return sum(osc(freq * r, dur, sr=sr) * a for r, a in parts) * env_exp(dur, dur / 4, sr=sr) * vol


def thump(f0=170, f1=70, dur=0.09, vol=0.6, sr=SR):
    return osc(sweep(f0, f1, dur, 8, sr), dur, sr=sr) * env_exp(dur, dur / 3, sr=sr) * vol


def bell(freq, dur=1.0, vol=0.4, sr=SR):
    parts = [(1, 1), (2.0, 0.45), (3.0, 0.2), (4.2, 0.12), (5.4, 0.08)]
    return sum(
        osc(freq * r, dur, sr=sr) * a * env_exp(dur, dur / (2 + i * 1.6), sr=sr)
        for i, (r, a) in enumerate(parts)
    ) * vol


def brass(freq, dur, vol=0.3, sr=SR):
    """Saw through an opening filter: a short heroic horn."""
    raw = osc(freq, dur, "saw", sr) + 0.5 * osc(freq * 1.003, dur, "saw", sr)
    cutoff = 600 + 3500 * env_adsr(dur, 0.05, 0.25, 0.45, 0.1, sr)
    return onepole_lp(onepole_lp(raw, cutoff, sr), cutoff, sr) * env_adsr(dur, 0.03, 0.2, 0.75, 0.12, sr) * vol


def pluck(freq, dur=0.6, vol=0.3, bright=1.0, sr=SR):
    """Santoor-like hammered string: bright attack, quick shimmering decay."""
    parts = [(1, 1), (2, 0.55 * bright), (3, 0.35 * bright), (4.01, 0.2 * bright), (5.02, 0.1 * bright)]
    body = sum(
        osc(freq * r * 1.0015, dur, sr=sr) * a * env_exp(dur, dur / (3 + i * 2.5), 0.001, sr)
        for i, (r, a) in enumerate(parts)
    )
    return body * vol


def flute(freq, dur, vol=0.25, sr=SR):
    """Bansuri-ish: sine + soft octave, vibrato that grows, breath noise."""
    vib = np.clip(t_axis(dur, sr) / 0.35, 0, 1) * 0.006
    n = int(dur * sr)
    f = freq * (1 + vib * np.sin(2 * np.pi * 5.2 * np.arange(n) / sr))
    tone = osc(f, dur, sr=sr) + 0.18 * osc(f * 2, dur, sr=sr) + 0.05 * osc(f * 3, dur, sr=sr)
    breath = bandnoise(dur, freq * 0.8, freq * 3, sr) * 0.08
    return (tone + breath) * env_adsr(dur, 0.06, 0.2, 0.8, min(0.15, dur / 3), sr) * vol


def pad(freqs, dur, vol=0.12, sr=SR):
    out = np.zeros(int(dur * sr))
    for f in freqs:
        for det in (0.997, 1.0, 1.004):
            out += osc(f * det, dur, "tri", sr)
    out = onepole_lp(out, 1800, sr)
    return out * env_adsr(dur, dur * 0.25, 0.4, 0.85, dur * 0.3, sr) * vol / len(freqs)


def bass(freq, dur, vol=0.35, sr=SR):
    tone = osc(freq, dur, sr=sr) + 0.35 * osc(freq * 2, dur, "tri", sr)
    return tone * env_exp(dur, dur / 2.2, 0.004, sr) * vol


# Tabla-style drums: pitched membranes with bends.
def tabla_ge(dur=0.5, vol=0.6, sr=SR):  # bass "ge/dha" with upward glide
    f = 85 + 45 * (1 - np.exp(-t_axis(dur, sr) * 9))
    return osc(f, dur, sr=sr) * env_exp(dur, 0.16, 0.002, sr) * vol


def tabla_na(dur=0.3, vol=0.35, pitch=520, sr=SR):  # sharp ringing "na/ta"
    ring = osc(pitch, dur, sr=sr) + 0.5 * osc(pitch * 2.02, dur, sr=sr) + 0.25 * osc(pitch * 3.01, dur, sr=sr)
    return ring * env_exp(dur, 0.07, 0.001, sr) * vol


def tabla_ti(vol=0.18, sr=SR):  # dry closed stroke
    return hp(noise(0.05, sr), 1800, sr) * env_exp(0.05, 0.012, 0.001, sr) * vol + \
        osc(1100, 0.05, sr=sr) * env_exp(0.05, 0.01, 0.001, sr) * vol * 0.6


def shaker(vol=0.07, sr=SR):
    return hp(noise(0.06, sr), 5000, sr) * env_exp(0.06, 0.018, 0.008, sr) * vol


def kick(vol=0.8, sr=SR):
    dur = 0.35
    return osc(sweep(140, 45, dur, 14, sr), dur, sr=sr) * env_exp(dur, 0.11, 0.001, sr) * vol


def boom(vol=1.0, dur=1.4, sr=SR):
    sub = osc(sweep(80, 32, dur, 5, sr), dur, sr=sr) * env_exp(dur, 0.45, 0.002, sr)
    crack = onepole_lp(noise(0.4, sr), 900, sr) * env_exp(0.4, 0.09, 0.001, sr) * 0.9
    return mix(sub, crack) * vol


def riser(dur=0.45, sr=SR):
    t = np.linspace(0, 1, int(dur * sr))
    n = onepole_lp(noise(dur, sr), 300 + 7000 * t**2, sr)
    tone = osc(sweep(200, 900, dur, 0, sr), dur, "saw", sr) * 0.08
    return (n * 0.5 + tone) * t**2.2


def whoosh(dur, f0, f1, vol=0.5, sr=SR):
    t = np.linspace(0, 1, int(dur * sr))
    cutoff = f0 * (f1 / f0) ** t
    n = noise(dur, sr)
    body = hp(onepole_lp(onepole_lp(n, cutoff, sr), cutoff, sr), cutoff * 0.35, sr)
    shape = np.sin(np.pi * t) ** 1.5
    return body * shape * vol


def crinkle(dur, vol=0.35, bursts=6, lowpass=6000):
    out = np.zeros(int(SR * dur))
    for _ in range(bursts):
        s = int(rng.uniform(0, dur * 0.8) * SR)
        bd = rng.uniform(0.015, 0.06)
        b = hp(onepole_lp(noise(bd), lowpass), 700) * env_exp(bd, bd / 3, 0.001) * vol * rng.uniform(0.5, 1)
        out[s: s + len(b)] += b[: len(out) - s]
    return out


# --------------------------------------------------------------------- UI sounds
def ui_sounds():
    # Primary button: tactile thock + crisp tick + metallic ting.
    button = mix(
        click_transient(0.9),
        thump(190, 80, 0.08, 0.55),
        osc(sweep(2100, 1300, 0.05, 10), 0.05) * env_exp(0.05, 0.012) * 0.45,
        at(metal(3200, 0.14, 0.18), 0.003),
    )
    write("button.wav", trim(reverb(button, 0.2, 0.06, 4000)))

    # Small controls (icons, chips, list rows): lighter, higher click.
    tap = mix(
        click_transient(0.6),
        osc(sweep(2600, 1800, 0.035, 10), 0.035) * env_exp(0.035, 0.008) * 0.5,
        thump(260, 140, 0.04, 0.25),
    )
    write("tap.wav", trim(reverb(tap, 0.15, 0.05, 4000)))

    # Back / close: lower, softer, falling.
    back = mix(
        click_transient(0.5),
        osc(sweep(1300, 700, 0.06, 8), 0.06) * env_exp(0.06, 0.016) * 0.45,
        thump(150, 70, 0.07, 0.4),
    )
    write("back.wav", trim(reverb(back, 0.15, 0.05, 4000)))

    # Switch / segmented toggles: two quick rising ticks.
    tick_a = osc(1500, 0.03) * env_exp(0.03, 0.007) * 0.5
    tick_b = osc(2250, 0.04) * env_exp(0.04, 0.009) * 0.5
    write("toggle.wav", trim(mix(click_transient(0.4), tick_a, at(tick_b, 0.045))))

    # Panels, sheets, dialogs opening / closing.
    write("open.wav", trim(reverb(mix(whoosh(0.22, 500, 5000, 0.45), at(metal(2600, 0.15, 0.12), 0.17)), 0.35, 0.18)))
    write("close.wav", trim(reverb(whoosh(0.16, 3500, 500, 0.35), 0.25, 0.12)))

    # Chat bubble pop.
    pop = mix(
        osc(sweep(380, 1250, 0.07, 0), 0.07) * env_exp(0.07, 0.03, 0.002) * 0.6,
        at(osc(1650, 0.05) * env_exp(0.05, 0.012) * 0.25, 0.05),
    )
    write("pop.wav", trim(reverb(pop, 0.25, 0.12)))

    # Someone joined / left.
    write("join.wav", trim(reverb(mix(bell(note(91), 0.5, 0.3), at(bell(note(98), 0.7, 0.32), 0.09)), 0.6, 0.22)))
    write("leave.wav", trim(reverb(mix(bell(note(93), 0.4, 0.25), at(bell(note(86), 0.6, 0.25), 0.1)), 0.6, 0.22)))

    # Not allowed / error: two soft low pulses.
    def pulse():
        return onepole_lp(osc(196, 0.08, "square"), 1200) * env_adsr(0.08, 0.004, 0.03, 0.6, 0.03) * 0.5
    write("error.wav", trim(reverb(mix(pulse(), at(pulse(), 0.11)), 0.2, 0.1)))

    # Points / score count.
    coin = mix(
        onepole_lp(osc(note(83), 0.07, "square"), 5000) * env_exp(0.07, 0.04) * 0.3,
        at(onepole_lp(osc(note(88), 0.3, "square"), 5000) * env_exp(0.3, 0.09) * 0.3, 0.07),
        at(metal(5200, 0.2, 0.08), 0.07),
    )
    write("coin.wav", trim(reverb(coin, 0.4, 0.18)))

    # Knock-knock: someone nudged you.
    def knock():
        return mix(osc(sweep(420, 260, 0.08, 10), 0.08) * env_exp(0.08, 0.02, 0.001) * 0.7,
                   onepole_lp(noise(0.03), 2500) * env_exp(0.03, 0.006, 0.0005) * 0.6)
    write("nudge.wav", trim(reverb(mix(knock(), at(knock(), 0.16)), 0.3, 0.15)))

    # Timer ticks: woody tick, and a sharper one for the last seconds.
    tick = mix(click_transient(0.5), osc(1850, 0.04) * env_exp(0.04, 0.008) * 0.55, thump(600, 400, 0.03, 0.2))
    write("tick.wav", trim(tick))
    urgent = mix(click_transient(0.7), osc(2500, 0.05) * env_exp(0.05, 0.012) * 0.6,
                 at(osc(2500, 0.04) * env_exp(0.04, 0.01) * 0.35, 0.07))
    write("tick_urgent.wav", trim(urgent))

    # Time's up: a falling two-tone horn with a thump.
    timeout = mix(
        brass(note(76), 0.16, 0.35),
        at(brass(note(69), 0.42, 0.38), 0.17),
        at(thump(120, 50, 0.25, 0.5), 0.17),
    )
    write("timeout.wav", trim(reverb(timeout, 0.6, 0.2)))

    # Game / round start: riser -> boom + bright chord stab.
    stab = mix(*(brass(note(n), 0.75, 0.22) for n in (60, 64, 67, 72)))
    start = mix(riser(0.45), at(boom(0.9, 1.4), 0.45), at(stab, 0.45), at(metal(2100, 0.6, 0.15), 0.45))
    write("start.wav", trim(reverb(start, 1.2, 0.25)))

    # Selecting a slip / item.
    select = mix(click_transient(0.5), osc(sweep(1200, 1700, 0.06, 0), 0.06) * env_exp(0.06, 0.02) * 0.5,
                 at(metal(3600, 0.1, 0.1), 0.02))
    write("select.wav", trim(reverb(select, 0.25, 0.12)))

    # A slip arrives in your hand: paper swish + soft bell.
    receive = mix(whoosh(0.18, 1500, 600, 0.35), at(bell(note(79), 0.5, 0.35), 0.06))
    write("receive.wav", trim(reverb(receive, 0.5, 0.18)))

    # You pass a slip: swish away.
    pass_ = mix(whoosh(0.22, 700, 4500, 0.45), osc(sweep(400, 900, 0.18, 0), 0.18) * env_exp(0.18, 0.06) * 0.12,
                at(crinkle(0.12, 0.25, 3), 0.02))
    write("pass.wav", trim(reverb(pass_, 0.35, 0.14)))

    # Round won by you: arpeggio + shimmer + boom.
    arp = mix(*(at(bell(note(n), 0.9, 0.35), i * 0.09) for i, n in enumerate((72, 76, 79, 84))))
    shimmer = at(mix(*(at(metal(note(n) * 2, 0.35, 0.06), i * 0.04) for i, n in enumerate((84, 88, 91, 96, 100)))), 0.3)
    win = mix(arp, shimmer, at(boom(0.35, 0.9), 0.27), at(stab * 0.7, 0.27))
    write("win.wav", trim(reverb(win, 1.2, 0.25)))

    # Magic reveal: upward bell gliss + chord.
    gl = mix(*(at(bell(note(n), 0.4, 0.18), i * 0.035) for i, n in enumerate((79, 81, 84, 86, 88, 91, 93, 96))))
    reveal = mix(gl, at(pad([note(67), note(72), note(76)], 0.9, 0.5), 0.15), at(bell(note(84), 1.0, 0.3), 0.3))
    write("reveal.wav", trim(reverb(reveal, 1.0, 0.28)))

    # Round over.
    round_end = mix(pluck(note(79), 0.4, 0.4), at(pluck(note(84), 0.9, 0.45), 0.12), at(thump(110, 50, 0.3, 0.4), 0.12))
    write("round_end.wav", trim(reverb(round_end, 0.8, 0.22)))

    # Champion fanfare: horn call over timpani roll and a cymbal swell.
    call = mix(
        brass(note(67), 0.16, 0.3), at(brass(note(67), 0.16, 0.3), 0.18), at(brass(note(72), 0.18, 0.32), 0.36),
        at(brass(note(76), 0.22, 0.34), 0.56), at(mix(*(brass(note(n), 1.4, 0.24) for n in (72, 76, 79, 84))), 0.8),
    )
    roll = mix(*(at(thump(110, 70, 0.12, 0.25 + 0.02 * i), i * 0.06) for i in range(13)))
    cym = at(hp(noise(1.8), 4000) * env_adsr(1.8, 0.6, 0.6, 0.5, 0.9) * 0.18, 0.2)
    fanfare = mix(call, roll, cym, at(boom(0.6, 1.4), 0.8), at(arp * 0.6, 0.8))
    write("fanfare.wav", trim(reverb(fanfare, 1.6, 0.28)))

    # Paper sounds.
    write("fold.wav", trim(mix(crinkle(0.28, 0.45, 5), thump(320, 200, 0.08, 0.15))))
    write("shuffle.wav", trim(reverb(mix(crinkle(1.0, 0.35, 22, 5000), at(whoosh(0.5, 400, 1500, 0.15), 0.25)), 0.4, 0.12)))
    write("pick.wav", trim(mix(click_transient(0.7), crinkle(0.07, 0.4, 2), at(osc(1600, 0.04) * env_exp(0.04, 0.01) * 0.25, 0.01))))
    write("unfold.wav", trim(reverb(mix(crinkle(0.35, 0.32, 6), at(bell(note(88), 0.6, 0.25), 0.28)), 0.6, 0.2)))


# ------------------------------------------------------------------------- music
def place(buf, x, secs, sr=MSR):
    """Adds x into buf at secs, wrapping past the end (loops stay seamless)."""
    s = int(secs * sr) % len(buf)
    end = s + len(x)
    if end <= len(buf):
        buf[s:end] += x
    else:
        k = len(buf) - s
        buf[s:] += x[:k]
        rest = x[k:]
        buf[: len(rest)] += rest[: len(buf)]


def music_menu():
    """Festive, warm and a little heroic: 96 BPM, D major pentatonic, 16 bars."""
    sr, bpm, bars = MSR, 96, 16
    beat = 60 / bpm
    total = bars * 4 * beat
    buf = np.zeros(int(total * sr))

    chords = [(50, 57, 62, 66), (47, 54, 59, 62), (43, 50, 55, 59), (45, 52, 57, 61)]  # D Bm G A
    for bar in range(bars):
        ch = chords[bar % 4]
        t0 = bar * 4 * beat
        place(buf, pad([note(n + 12) for n in ch[1:]], 4 * beat + 0.4, 0.5, sr), t0)
        # Bass: root on 1, fifth on the "and" of 2, root on 3.
        for off, n in ((0, ch[0] - 12), (1.5, ch[1] - 12), (2, ch[0] - 12), (3.5, ch[0])):
            place(buf, bass(note(n), beat * 0.9, 0.55, sr), t0 + off * beat)
        # Tabla groove (dha . ti na | dha dha ti na).
        groove = [(0, "ge"), (0, "na"), (1, "ti"), (1.5, "na"), (2, "ge"), (2.5, "ge"), (3, "ti"), (3.5, "na")]
        for off, kind in groove:
            x = tabla_ge(vol=0.55, sr=sr) if kind == "ge" else tabla_na(vol=0.28, sr=sr) if kind == "na" else tabla_ti(sr=sr)
            place(buf, x, t0 + off * beat)
        for k in range(8):
            place(buf, shaker(0.05 if k % 2 else 0.035, sr), t0 + k * beat / 2)
        if bar % 4 == 0:
            place(buf, kick(0.6, sr), t0)

    # Flute melody (D major pentatonic), two 8-bar phrases.
    D = 74
    pent = {"d": 0, "e": 2, "f": 4, "a": 7, "b": 9, "D": 12, "E": 14, "F": 16}
    phrase_a = [("f", 1), ("a", 1), ("b", 1.5), ("a", .5), ("f", 2), ("e", 1), ("d", 1),
                ("e", 1), ("f", 1), ("a", 2), ("-", 2),
                ("b", 1), ("D", 1), ("b", 1), ("a", 1), ("f", 1.5), ("e", .5), ("f", 2),
                ("e", 1), ("d", 1), ("e", 1.5), ("f", .5), ("d", 2), ("-", 2)]
    phrase_b = [("a", 1), ("b", 1), ("D", 2), ("E", 1), ("D", 1), ("b", 2),
                ("a", 1), ("b", 1), ("D", 1), ("E", 1), ("F", 3), ("-", 1),
                ("E", 1), ("D", 1), ("b", 1), ("a", 1), ("b", 1.5), ("a", .5), ("f", 2),
                ("e", 1), ("f", 1), ("a", 1), ("e", 1), ("d", 3), ("-", 1)]
    t = 0.0
    for name, beats in phrase_a + phrase_b:
        if name != "-":
            place(buf, flute(note(D + pent[name]), beats * beat * 0.98 + 0.08, 0.32, sr), t)
        t += beats * beat
    # Santoor sparkle answering the flute every other bar.
    for bar in range(1, bars, 2):
        ch = chords[bar % 4]
        for i, n in enumerate((ch[1] + 24, ch[2] + 24, ch[3] + 24, ch[2] + 24)):
            place(buf, pluck(note(n), 0.5, 0.11, 1.0, sr), bar * 4 * beat + (2 + i * 0.5) * beat)

    out = reverb(buf, 1.6, 0.22, 5000, sr, loop=True)
    write("music_menu.wav", out, 0.85, sr)


def music_game():
    """Light, bouncy groove that stays out of the way: 108 BPM, 16 bars."""
    sr, bpm, bars = MSR, 108, 16
    beat = 60 / bpm
    total = bars * 4 * beat
    buf = np.zeros(int(total * sr))
    chords = [(45, 52, 57, 60), (41, 48, 53, 57), (43, 50, 55, 59), (40, 47, 52, 55)]  # Am F G Em
    # A minor pentatonic ostinato for the santoor.
    ost = [69, 72, 76, 72, 74, 76, 79, 76]
    for bar in range(bars):
        ch = chords[bar % 4]
        t0 = bar * 4 * beat
        place(buf, pad([note(n + 12) for n in ch[1:]], 4 * beat + 0.3, 0.35, sr), t0)
        for off in (0, 1.5, 2.5):
            place(buf, bass(note(ch[0] - 12 if off != 1.5 else ch[1] - 12), beat * 0.7, 0.5, sr), t0 + off * beat)
        groove = [(0, "ge"), (0.75, "ti"), (1, "na"), (1.5, "ti"), (2, "ge"), (2.25, "ge"), (3, "na"), (3.5, "ti"), (3.75, "na")]
        for off, kind in groove:
            x = tabla_ge(vol=0.5, sr=sr) if kind == "ge" else tabla_na(vol=0.24, pitch=600, sr=sr) if kind == "na" else tabla_ti(0.15, sr)
            place(buf, x, t0 + off * beat)
        for k in range(8):
            place(buf, shaker(0.045 if k % 2 else 0.03, sr), t0 + k * beat / 2)
        # Ostinato: transposed with the chord, thinned out in quiet bars.
        shift = {45: 0, 41: -4, 43: -2, 40: -5}[ch[0]]
        for i, n in enumerate(ost):
            if bar % 8 in (3, 7) and i % 2:
                continue
            place(buf, pluck(note(n + shift), 0.45, 0.12 if i % 2 else 0.15, 0.9, sr), t0 + i * beat / 2)
    out = reverb(buf, 1.3, 0.2, 5000, sr, loop=True)
    write("music_game.wav", out, 0.85, sr)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for old in ("music_loop.wav",):
        p = os.path.join(OUT, old)
        if os.path.exists(p):
            os.remove(p)
    ui_sounds()
    music_menu()
    music_game()
    print("wrote", sorted(os.listdir(OUT)))
