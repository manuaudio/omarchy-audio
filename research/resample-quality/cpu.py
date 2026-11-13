#!/usr/bin/env python3
"""CPU cost of spa-resample per channel: 300 s of mono f32 noise, min of 5 runs,
minus a same-rate pass (file I/O). Reported as % of one core per channel of
real time, and ns per output sample. Usage: cpu.py <workdir> <q>..."""
import os, resource, subprocess, sys
import numpy as np
import scipy.io.wavfile as wav

D, SECS = sys.argv[1], 300
CASES = [(44100, 48000), (48000, 44100), (96000, 48000), (44100, 48001)]


def cpu(args):
    best = 1e9
    for _ in range(5):
        r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
        subprocess.run(["taskset", "-c", "3", "spa-resample", "-c", "0xffffffff", *args],
                       check=True, capture_output=True)
        r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
        best = min(best, (r1.ru_utime - r0.ru_utime) + (r1.ru_stime - r0.ru_stime))
    return best


os.makedirs(D, exist_ok=True)
rng = np.random.default_rng(1)
for fin in {c[0] for c in CASES}:
    p = f"{D}/n{fin}.wav"
    if not os.path.exists(p):
        wav.write(p, fin, (0.25 * rng.standard_normal(SECS * fin)).astype(np.float32))
base = {fin: cpu(["-q", "4", "-r", str(fin), f"{D}/n{fin}.wav", f"{D}/o.wav"]) for fin in {c[0] for c in CASES}}
for q in sys.argv[2:]:
    row = []
    for fin, fout in CASES:
        t = cpu(["-q", q, "-r", str(fout), f"{D}/n{fin}.wav", f"{D}/o.wav"]) - base[fin]
        row.append(f"{fin}->{fout}: {100 * t / SECS:.3f}% ({1e9 * t / (SECS * fout):.1f} ns/smp)")
    print(f"q{q}", " | ".join(row), flush=True)
os.remove(f"{D}/o.wav")
