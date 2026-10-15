"""Synthesizes the typewriter clack and the title sting as 16-bit mono WAVs."""
import math, random, struct, sys, wave

RATE = 44100

def write(path, samples):
    peak = max(abs(s) for s in samples) or 1.0
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(s / peak * 0.98 * 32767)) for s in samples))

def clack(seed):
    """A loud metal type bar: the key, the bar slamming the platen, the carriage ratchet."""
    rnd = random.Random(seed)
    n = int(RATE * 0.16)
    second = rnd.uniform(0.014, 0.022)                 # the bar lands
    ratchet = second + rnd.uniform(0.030, 0.040)        # the carriage steps on
    modes = [(rnd.uniform(2300, 2700), 0.016), (rnd.uniform(3600, 4200), 0.011),
             (rnd.uniform(5200, 6000), 0.008), (rnd.uniform(1300, 1600), 0.022),
             (rnd.uniform(7400, 8200), 0.005)]
    hits = ((0.0, 0.55, 1.0), (second, 1.0, 1.0), (ratchet, 0.35, 0.5))
    out, hp_prev, hp, low = [], 0.0, 0.0, 0.0
    for i in range(n):
        t = i / RATE
        noise = rnd.uniform(-1, 1)
        hp = 0.92 * (hp + noise - hp_prev); hp_prev = noise    # high-passed noise
        low += 0.04 * (noise - low)                             # band of low noise
        x = 0.0
        for k, (onset, gain, ring) in enumerate(hits):
            if t < onset: continue
            u = t - onset
            x += gain * 1.4 * hp * math.exp(-u / 0.0025)        # the crack
            for f, tau in modes:                                # ringing metal
                x += gain * ring * 0.45 * math.sin(2 * math.pi * f * u + k) * math.exp(-u / tau)
            if k == 1:
                x += 6.0 * low * math.exp(-u / 0.012)           # the slam's weight, noisy not tonal
        out.append(math.tanh(2.2 * x))                          # drive it hard: louder, punchier
    return out

def boom(seed, length=0.55):
    """An explosion: a crack, a low noise blast and a sub thump falling in pitch."""
    rnd = random.Random(seed)
    n = int(RATE * length)
    out, lp1, lp2, hp_prev, hp, phase = [], 0.0, 0.0, 0.0, 0.0, 0.0
    for i in range(n):
        t = i / RATE
        noise = rnd.uniform(-1, 1)
        hp = 0.9 * (hp + noise - hp_prev); hp_prev = noise
        cut = 0.02 + 0.25 * math.exp(-t / 0.05)                 # blast darkens as it dies
        lp1 += cut * (noise - lp1); lp2 += cut * (lp1 - lp2)
        blast = 5.0 * lp2 * min(1.0, t / 0.002) * math.exp(-t / (length * 0.32))
        crack = 1.2 * hp * math.exp(-t / 0.006)
        phase += 2 * math.pi * (38 + 90 * math.exp(-t / 0.04)) / RATE
        thump = 1.1 * math.sin(phase) * math.exp(-t / 0.12)
        out.append(math.tanh(1.8 * (blast + crack + thump)))
    return out

def saw(phase):
    return 2.0 * (phase - math.floor(phase + 0.5))

def sting():
    """Ja! Ja! Jaaan!: brass stabs on an E7#9, the last one held, swelling and falling off,
    each landing on an explosion with a crash cymbal over the top."""
    rnd = random.Random(3)
    notes = [41.20, 82.41, 123.47, 164.81, 207.65, 293.66, 392.00, 493.88, 659.26]
    hits = [(0.00, 0.13), (0.17, 0.13), (0.36, 2.1)]
    n = int(RATE * 2.9)
    out = [0.0] * n
    for start, length in hits:
        s0 = int(start * RATE)
        held = length > 0.5
        for f in notes:
            for det in (-0.006, 0.0, 0.006):
                lp = lp2 = 0.0
                ph = rnd.random()
                for i in range(int((length + 0.08) * RATE)):
                    if s0 + i >= n: break
                    t = i / RATE
                    if held:
                        env = min(1.0, t / 0.008) * (0.75 + 0.25 * math.exp(-t / 0.15))
                        env *= 1.0 if t < length - 0.5 else math.exp(-(t - (length - 0.5)) / 0.18)
                        fall = 1.0 if t < length - 0.6 else 2 ** (-3.5 / 12 * ((t - (length - 0.6)) / 0.6) ** 2)  # falls 3.5 semitones
                        bright = 0.12 + 0.5 * math.exp(-t / 0.12) + 0.18 * (0.5 + 0.5 * math.sin(2 * math.pi * 6 * t)) * min(1, t / 0.5)
                    else:
                        env = min(1.0, t / 0.006) * math.exp(-t / 0.07)
                        fall, bright = 1.0, 0.55
                    vib = 1 + 0.004 * math.sin(2 * math.pi * 5.8 * t) * min(1.0, t / 0.3)
                    ph += f * (1 + det) * vib * fall / RATE
                    x = saw(ph)
                    lp += bright * (x - lp); lp2 += bright * (lp - lp2)
                    out[s0 + i] += 0.5 * lp2 * env
        bang = boom(50 + int(start * 100), 1.6 if held else 0.35)
        for i, b in enumerate(bang):
            if s0 + i < n: out[s0 + i] += (7.0 if held else 4.5) * b
        crash_hp = crash_prev = 0.0
        for i in range(int((1.8 if held else 0.3) * RATE)):
            if s0 + i >= n: break
            t = i / RATE
            noise = rnd.uniform(-1, 1)
            crash_hp = 0.97 * (crash_hp + noise - crash_prev); crash_prev = noise
            out[s0 + i] += (3.0 if held else 1.8) * crash_hp * math.exp(-t / (0.7 if held else 0.06))
    peak = max(abs(x) for x in out)
    return [math.tanh(5.0 * x / peak) for x in out]  # pushed hard into the limiter: loud

def groove():
    """An original 8-bar up-tempo swing loop (152 BPM, E minor): drums, walking
    bass, brass stabs and a muted lead. Tails wrap round so it loops seamlessly."""
    rnd = random.Random(9)
    beat = 60 / 152
    n = int(round(32 * beat * RATE))
    out = [0.0] * n

    def mf(m): return 440.0 * 2 ** ((m - 69) / 12)

    def add(start_beats, dur_s, voice, gain):
        s0 = int(start_beats * beat * RATE)
        for i in range(int(dur_s * RATE)):
            out[(s0 + i) % n] += gain * voice(i / RATE)

    def sw(b):  # swing the off-beat eighths
        whole = math.floor(b)
        return whole + (0.64 if b - whole >= 0.5 else 0.0)

    # --- drums
    def kick(t): return math.sin(2 * math.pi * (45 * t + 75 * 0.03 * (1 - math.exp(-t / 0.03)))) * math.exp(-t / 0.16)
    def noise_env(tau, hp_amt):
        st = {'p': 0.0, 'h': 0.0}
        def v(t):
            x = rnd.uniform(-1, 1)
            st['h'] = hp_amt * (st['h'] + x - st['p']); st['p'] = x
            return st['h'] * math.exp(-t / tau)
        return v
    def snare(t): return 0.6 * math.sin(2 * math.pi * 190 * t) * math.exp(-t / 0.05) + noise_env(0.11, 0.6)(t)
    for bar in range(8):
        b0 = bar * 4
        for k in (0, 2.5 if bar % 2 else 2):
            add(b0 + k, 0.4, kick, 1.0)
        for k in (1, 3):
            add(b0 + k, 0.25, noise_env(0.10, 0.55), 0.55)
            add(b0 + k, 0.15, lambda t: 0.5 * math.sin(2 * math.pi * 190 * t) * math.exp(-t / 0.05), 0.5)
        for e in range(8):
            pos = sw(b0 + e / 2)
            open_hat = e == 7
            add(pos, 0.25 if open_hat else 0.06, noise_env(0.12 if open_hat else 0.022, 0.95), 0.32 if e % 2 else 0.22)

    # --- harmony: (beat, root midi for bass, chord tones for stabs)
    chords = [(0, 40, [64, 67, 71, 74]), (4, 45, [61, 64, 67, 71]), (8, 38, [62, 65, 69, 72]),
              (12, 43, [62, 65, 67, 71]), (16, 36, [64, 67, 71, 72]), (20, 42, [60, 64, 66, 69]),
              (22, 35, [63, 66, 69, 71]), (24, 40, [64, 67, 71, 74]), (28, 35, [63, 66, 69, 72])]

    def chord_at(b):
        cur = chords[0]
        for c in chords:
            if c[0] <= b: cur = c
        return cur

    # --- walking bass
    def pluck(f):
        st = {'lp': 0.0}
        def v(t):
            x = saw(f * t)
            st['lp'] += 0.12 * (x - st['lp'])
            return st['lp'] * math.exp(-t / 0.3) * min(1.0, t / 0.004)
        return v
    for b in range(32):
        start, root, tones = chord_at(b)
        minor = (tones[1] - tones[0]) % 12 == 3
        next_root = chord_at(start + (2 if start in (20, 22) else 4))[1] if start + 4 < 32 else 40
        approach = next_root + (1 if b % 2 else -1)          # a half step into the next chord
        line = [root, root + (3 if minor else 4), root + 7, approach]
        add(b, beat * 0.92, pluck(mf(line[b % 4])), 0.9)

    # --- brass stabs on the off-beats of 2 and 4
    def brass(f, length):
        st = {'lp': 0.0, 'ph': rnd.random()}
        def v(t):
            env = min(1.0, t / 0.008) * math.exp(-t / (length * 0.6))
            st['ph'] += f / RATE
            x = saw(st['ph'])
            st['lp'] += (0.15 + 0.4 * env) * (x - st['lp'])
            return st['lp'] * env
        return v
    for bar in range(8):
        for k in (1.5, 3.5):
            b = sw(bar * 4 + k)
            _, _, tones = chord_at(bar * 4 + k + 0.5)
            for m in tones:
                for det in (-0.005, 0.005):
                    add(b, 0.22, brass(mf(m) * (1 + det), 0.22), 0.14)

    # --- muted lead line
    phrase = [(0, 71, .5), (.5, 74, .4), (1, 76, .9), (2.5, 79, .4), (3, 76, .5), (3.5, 74, .6),
              (4.5, 73, .4), (5, 76, .5), (5.5, 79, .5), (6.5, 81, .4), (7, 79, 1.0)]
    lead = phrase + [(b + 8, m - 2, d) for b, m, d in phrase] + [
        (16, 72, .5), (16.5, 76, .4), (17, 79, 1), (18.5, 76, .5), (19, 74, .5), (19.5, 72, .6),
        (20, 69, .5), (20.5, 72, .4), (21, 66, .5), (22, 75, .5), (22.5, 71, .4), (23, 69, .9)] + [
        (b + 24, m, d) for b, m, d in phrase[:6]] + [
        (28, 75, .5), (28.5, 78, .4), (29, 81, .5), (29.5, 83, 1.4)]
    def trumpet(f, length):
        st = {'lp': 0.0, 'ph': 0.0}
        def v(t):
            vib = 1 + 0.006 * math.sin(2 * math.pi * 6 * t) * min(1.0, t / 0.2)
            st['ph'] += f * vib / RATE
            frac = st['ph'] - math.floor(st['ph'])
            x = 1.0 if frac < 0.3 else -0.45
            st['lp'] += 0.22 * (x - st['lp'])
            rel = 1.0 if t < length else math.exp(-(t - length) / 0.04)
            return st['lp'] * min(1.0, t / 0.015) * rel
        return v
    for b, m, d in lead:
        add(sw(b), d * beat + 0.12, trumpet(mf(m), d * beat), 0.42)

    peak = max(abs(x) for x in out)
    return [math.tanh(1.6 * x / peak) for x in out]

if __name__ == '__main__':
    d = sys.argv[1]
    for v in range(4):
        write(f'{d}/clack{v}.wav', clack(11 + v))
        write(f'{d}/boom{v}.wav', boom(31 + v))
    write(f'{d}/sting.wav', sting())
    write(f'{d}/groove.wav', groove())
