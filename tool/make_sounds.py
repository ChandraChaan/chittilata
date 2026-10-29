"""Synthesises Chittilata's original sound effects (no third-party assets).

Run: python3 tool/make_sounds.py  -> writes assets/sounds/*.wav
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")


def env(i, n, attack=0.01, release=0.6):
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = (1 - i / n) ** (1 / max(release, 1e-3) * 0.5)
    return a * r


def tone(freq, dur, vol=0.5, shape="sine", attack=0.005, release=0.5, bend=0.0):
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        f = freq * (1 + bend * i / n)
        phase += 2 * math.pi * f / RATE
        if shape == "sine":
            s = math.sin(phase)
        elif shape == "bell":
            s = math.sin(phase) + 0.35 * math.sin(2.76 * phase) + 0.15 * math.sin(5.4 * phase)
            s /= 1.5
        elif shape == "pluck":
            s = math.sin(phase) + 0.5 * math.sin(2 * phase) + 0.25 * math.sin(3 * phase)
            s /= 1.75
        else:
            s = math.sin(phase)
        out.append(s * vol * env(i, n, attack, release))
    return out


def noise(dur, vol=0.3, lowpass=0.2):
    n = int(RATE * dur)
    out, prev = [], 0.0
    for i in range(n):
        prev = prev + lowpass * (random.uniform(-1, 1) - prev)
        out.append(prev * vol * (1 - i / n) ** 2)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out += p + [0.0] * int(RATE * gap)
    return out


def delay(track, secs):
    return [0.0] * int(RATE * secs) + track


def write(name, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * scale * 32767)) for s in samples))


random.seed(7)
os.makedirs(OUT, exist_ok=True)

C5, D5, E5, G5, A5, C6, E6, G6 = 523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1318.5, 1568.0

write("tap.wav", tone(880, 0.06, 0.35, "sine", release=0.2))
write("select.wav", mix(tone(1200, 0.08, 0.3, "sine", bend=0.15), noise(0.04, 0.08, 0.6)))
write("receive.wav", mix(noise(0.18, 0.25, 0.08), delay(tone(G5, 0.18, 0.35, "bell"), 0.05)))
write("pass.wav", mix(noise(0.22, 0.35, 0.15), tone(500, 0.2, 0.15, "sine", bend=0.8)))
write("tick.wav", tone(1400, 0.05, 0.4, "sine", release=0.15))
write("timeout.wav", seq(tone(E5, 0.14, 0.4, "pluck"), tone(C5 * 0.75, 0.3, 0.4, "pluck")))
write("win.wav", mix(
    seq(tone(C5, 0.12, 0.4, "bell"), tone(E5, 0.12, 0.4, "bell"), tone(G5, 0.12, 0.4, "bell"),
        tone(C6, 0.5, 0.45, "bell", release=0.8)),
    delay(noise(0.6, 0.06, 0.5), 0.35)))
write("reveal.wav", mix(tone(A5, 0.5, 0.3, "bell", release=0.9), delay(tone(E6, 0.4, 0.2, "bell"), 0.08)))
write("round_end.wav", seq(tone(G5, 0.1, 0.35, "pluck"), tone(C6, 0.3, 0.35, "pluck", release=0.8)))
write("fanfare.wav", mix(
    seq(tone(G5, 0.14, 0.35, "bell"), tone(G5, 0.14, 0.35, "bell"), tone(C6, 0.14, 0.4, "bell"),
        tone(E6, 0.18, 0.4, "bell"), tone(G6, 0.7, 0.45, "bell", release=0.9)),
    seq(tone(C5, 0.42, 0.2, "sine"), tone(E5, 0.88, 0.2, "sine", release=0.9))))

# Paper sounds: crinkles are bursts of band-limited noise.
def crinkle(dur, vol=0.35, bursts=6, lowpass=0.35):
    out = [0.0] * int(RATE * dur)
    for _ in range(bursts):
        start = random.uniform(0, dur * 0.8)
        b = noise(random.uniform(0.02, 0.07), vol * random.uniform(0.5, 1.0), lowpass)
        o = int(RATE * start)
        for i, v in enumerate(b):
            if o + i < len(out): out[o + i] += v
    return out

write("fold.wav", mix(crinkle(0.28, 0.4, 5, 0.45), tone(320, 0.08, 0.12, "sine", bend=-0.3)))
write("shuffle.wav", mix(crinkle(1.0, 0.32, 22, 0.3), delay(noise(0.5, 0.08, 0.05), 0.25)))
write("pick.wav", mix(noise(0.05, 0.45, 0.7), delay(tone(1500, 0.04, 0.2, "sine", release=0.1), 0.01)))
write("unfold.wav", mix(crinkle(0.35, 0.3, 6, 0.4), delay(tone(E6, 0.45, 0.22, "bell", release=0.9), 0.28)))

# Gentle pentatonic music loop (~13 s), plucked melody over soft drone.
scale = [C5 / 2, D5 / 2, E5 / 2, G5 / 2, A5 / 2, C5, D5, E5, G5, A5]
melody = [5, 7, 8, 7, 5, 4, 3, 4, 5, 7, 9, 8, 7, 5, 4, 5,
          3, 4, 5, 7, 8, 7, 5, 4, 3, 2, 3, 4, 5, 4, 3, 5]
beat = 0.4
lead = []
for idx in melody:
    lead += tone(scale[idx], beat, 0.22, "pluck", attack=0.004, release=0.35)
drone = []
for root in [C5 / 4, A5 / 8 * 2, C5 / 4, G5 / 4]:
    drone += tone(root, beat * 8, 0.12, "sine", attack=0.4, release=3.0)
write("music_loop.wav", mix(lead, drone))
print("wrote", sorted(os.listdir(OUT)))
