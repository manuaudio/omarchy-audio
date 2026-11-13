#!/usr/bin/env python3
"""Measure PipeWire's native resampler (spa-resample) offline, no audio server.

For each rate pair and resample.quality:
  ripple   max-min gain over 20 Hz..20 kHz, stepped sines at -6 dBFS (dB)
  g20k     gain at 20 kHz (dB)
  thdn     THD+N of a 997 Hz sine at -1 dBFS, 20 Hz..20 kHz (dBFS)
  spur     worst component in 0..20 kHz that is not the tone, during a
           log sweep at -1 dBFS from 20 Hz to 0.99 x input Nyquist (dBFS);
           covers aliasing (down), imaging (up) and distortion
  alias    worst output, anywhere in 0..20 kHz, for stepped sines above
           the output Nyquist, re the tone (dB); n/a when no alias can land
           below 20 kHz
Usage: measure.py <workdir> <q> [<q>...]
"""
import json, os, subprocess, sys
import numpy as np
import scipy.io.wavfile as wav
from scipy import signal

PAIRS = [(44100, 48000), (48000, 44100), (96000, 48000)]
RAMP, SEG, KEEP = 0.05, 0.6, 0.3  # seconds: fade, segment, analysed middle


def run(q, fin, fout, src, dst):
    subprocess.run(["spa-resample", "-c", "0xffffffff", "-q", str(q), "-r", str(fout),
                    "-f", "f32", src, dst], check=True, capture_output=True)
    r, y = wav.read(dst)
    assert r == fout
    return y.astype(np.float64)


def ramp(n, fs):
    w = np.ones(n)
    k = int(RAMP * fs)
    h = 0.5 - 0.5 * np.cos(np.pi * np.arange(k) / k)
    w[:k], w[-k:] = h, h[::-1]
    return w


def tones(freqs, amp, fs):
    n = int(SEG * fs)
    t = np.arange(n) / fs
    return np.concatenate([amp * np.sin(2 * np.pi * f * t) * ramp(n, fs) for f in freqs])


def middle(y, i, fs):
    n = int(SEG * fs)
    a = i * n + int((SEG - KEEP) / 2 * fs)
    return y[a:a + int(KEEP * fs)]


def fit(x, f, fs):
    t = np.arange(len(x)) / fs
    m = np.stack([np.sin(2 * np.pi * f * t), np.cos(2 * np.pi * f * t), np.ones_like(t)], 1)
    c, *_ = np.linalg.lstsq(m, x, rcond=None)
    return np.hypot(c[0], c[1]), x - m @ c


def band(x, fs, lo=20.0, hi=20000.0):
    hi = min(hi, 0.499 * fs)
    sos = signal.butter(8, [lo, hi], "bandpass", fs=fs, output="sos")
    return signal.sosfiltfilt(sos, x)


def db(x):
    return 20 * np.log10(max(x, 1e-12))


def rms(x):
    return float(np.sqrt(np.mean(x ** 2)))


def sweep_spur(q, fin, fout, d):
    T, f1 = 10.0, 0.99 * fin / 2
    f0, A = 20.0, 10 ** (-1 / 20)
    t = np.arange(int(T * fin)) / fin
    k = np.log(f1 / f0)
    x = A * np.sin(2 * np.pi * f0 * T / k * (np.exp(t * k / T) - 1)) * ramp(len(t), fin)
    wav.write(f"{d}/sw.wav", fin, x.astype(np.float32))
    y = run(q, fin, fout, f"{d}/sw.wav", f"{d}/sw-out.wav")
    N, H = 4096, 1024
    w = signal.windows.kaiser(N, 20)
    scale = w.sum() / 2
    freqs = np.fft.rfftfreq(N, 1 / fout)
    lobe = 8 * fout / N
    worst = -300.0
    for s in range(int(0.2 * fout), len(y) - N - int(0.2 * fout), H):
        ta, tb = s / fout - 0.03, (s + N) / fout + 0.03
        fa, fb = (f0 * np.exp(np.clip(tt, 0, T) * k / T) for tt in (ta, tb))
        spec = np.abs(np.fft.rfft(y[s:s + N] * w)) / scale
        mask = (freqs <= 20000) & (freqs >= 10)
        mask &= ~((freqs >= fa - lobe) & (freqs <= fb + lobe))
        if mask.any():
            worst = max(worst, db(spec[mask].max()))
    return worst


def measure(q, fin, fout, d):
    out = {}
    # passband: stepped sines at -6 dBFS
    pf = list(np.geomspace(20, 20000, 31))
    amp = 0.5
    wav.write(f"{d}/pb.wav", fin, tones(pf, amp, fin).astype(np.float32))
    y = run(q, fin, fout, f"{d}/pb.wav", f"{d}/pb-out.wav")
    g = [db(fit(middle(y, i, fout), f, fout)[0] / amp) for i, f in enumerate(pf)]
    out["ripple"] = max(g) - min(g)
    out["g20k"] = g[-1]
    # band edge: first frequency where the gain leaves +-0.1 dB
    ef = list(np.arange(10000, 0.995 * min(fin, fout) / 2, 50.0))
    wav.write(f"{d}/ed.wav", fin, tones(ef, amp, fin).astype(np.float32))
    y = run(q, fin, fout, f"{d}/ed.wav", f"{d}/ed-out.wav")
    ge = [db(fit(middle(y, i, fout), f, fout)[0] / amp) for i, f in enumerate(ef)]
    out["f01"] = next((f for f, x in zip(ef, ge) if abs(x) > 0.1), ef[-1])
    out["f3"] = next((f for f, x in zip(ef, ge) if x < -3), None)
    # THD+N at 997 Hz, -1 dBFS
    a1 = 10 ** (-1 / 20)
    wav.write(f"{d}/thd.wav", fin, tones([997.0], a1, fin).astype(np.float32))
    y = run(q, fin, fout, f"{d}/thd.wav", f"{d}/thd-out.wav")
    seg = middle(y, 0, fout)
    _, res = fit(seg, 997.0, fout)
    out["thdn"] = db(rms(band(res, fout)) * np.sqrt(2))  # dBFS, sine-peak referenced
    # alias: stepped sines above the output Nyquist whose alias lands below 20 kHz
    af = [f for f in np.linspace(fout / 2 + 100, 0.98 * fin / 2, 25) if fout - f < 20000]
    if af and fout < fin:
        wav.write(f"{d}/al.wav", fin, tones(af, amp, fin).astype(np.float32))
        y = run(q, fin, fout, f"{d}/al.wav", f"{d}/al-out.wav")
        out["alias"] = max(db(rms(band(middle(y, i, fout), fout)) * np.sqrt(2) / amp)
                           for i in range(len(af)))
    else:
        out["alias"] = None
    out["spur"] = sweep_spur(q, fin, fout, d)
    return out


def main():
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)
    res = {}
    for q in map(int, sys.argv[2:]):
        for fin, fout in PAIRS:
            r = measure(q, fin, fout, d)
            res[f"{q} {fin} {fout}"] = r
            print(q, fin, fout, json.dumps({k: (None if v is None else round(v, 2)) for k, v in r.items()}), flush=True)
    json.dump(res, open(f"{d}/quality.json", "w"), indent=1)


if __name__ == "__main__":
    main()
