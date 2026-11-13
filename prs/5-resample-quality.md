## What changes

With #17520, PipeWire follows the source's sample rate when it can. When it can't (a second stream at another rate, a device that doesn't do 44.1 kHz, a Bluetooth headset), it converts, and its default resampler quality 4 isn't transparent: it rolls the treble off from about 17 kHz, to −13 dB at 20 kHz converting between 44.1 and 48 kHz. Quality 10 is flat to 20 kHz, and the CPU it costs is negligible on current machines.

- `config/pipewire/client.conf.d/10-resample-quality.conf` and `config/pipewire/pipewire-pulse.conf.d/10-resample-quality.conf` set `stream.properties = { resample.quality = 10 }` for native and Pulse apps.
- `config/wireplumber/wireplumber.conf.d/resample-quality.conf` sets the same on ALSA and Bluetooth device nodes, which convert when the hardware can't run at the graph's rate.
- The migration installs the three drop-ins unless a `resample.quality` is already set in `~/.config/pipewire`, `~/.config/wireplumber`, `/etc/pipewire` or `/etc/wireplumber`. Nothing restarts: new apps get it at once, and the rest at the next login.

Together with #17520: PipeWire follows the source when it can, and converts transparently when it can't.

## Measurements

PipeWire 1.6.8's own resampler (`spa-resample`, the same code as the audioconvert plugin, run on files without an audio server), with f32 in and out, analysed with numpy/scipy. Each cell gives 44.1→48 / 48→44.1 / 96→48 kHz.

| Quality | Gain at 20 kHz (dB) | Flat within 0.1 dB up to | THD+N, 997 Hz at −1 dBFS (dBFS) | Worst spur, 20 Hz to Nyquist sweep (dBFS) | CPU per stereo stream | Filter delay |
|---|---|---|---|---|---|---|
| 4 (default) | −13.2 / −13.7 / −2.2 | 16.9 / 17.0 / 18.4 kHz | −145 / −145 / −147 | −161 / −160 / −162 | 0.04% | 0.6 ms |
| 6 | −5.4 / −5.4 / −0.03 | 18.6 / 18.6 / 20.3 kHz | −145 / −145 / −146 | −160 / −160 / −162 | 0.05% | 1.0 ms |
| 8 | −0.31 / −0.27 / 0.00 | 19.9 / 19.9 / 21.6 kHz | −144 / −143 / −146 | −159 / −158 / −157 | 0.07% | 1.5 ms |
| **10** | **−0.002 / −0.002 / 0.000** | **20.4 / 20.4 / 22.2 kHz** | **−144 / −143 / −145** | **−159 / −159 / −157** | **0.10%** | **1.9 ms** |
| 14 | 0.000 / 0.000 / 0.000 | 21.8 / 21.8 / 23.7 kHz | −138 / −138 / −139 | −155 / −155 / −152 | 0.62% | 11.8 ms |

- **Ripple** below 10 kHz is under 0.001 dB at every quality, so the only audible difference is the roll-off near 20 kHz.
- **Aliasing.** 96→48 tones from 24.1 to 47 kHz alias below 20 kHz at −136 to −147 dB re the tone, at every quality.
- **The sweep** at −1 dBFS gives the worst component in 0 to 20 kHz that isn't the tone; it covers aliasing, imaging and distortion together. Every quality keeps it near the f32 floor.
- **CPU** was measured on an i7-12650H with PipeWire's AVX2 path, as the share of one core for real-time stereo at a fixed 44.1↔48 ratio. When PipeWire adapts to clock drift, it uses its interpolated filter bank: q10 then costs 0.27% per stereo stream, q4 0.07% and q14 1.5%. The interpolated path is as clean, with its worst spur at −145 dBFS.
- **Filter delay** is half the filter length at the input rate, for 44.1→48 kHz.

**Quality 10** is the smallest step that is flat within 0.01 dB to 20 kHz with every artefact below −140 dBFS. Quality 9 is −0.045 dB at 20 kHz. Quality 14 adds bandwidth above 20 kHz but costs six times the CPU and 12 ms of filter delay, and its longer filter raises the f32 noise floor by about 5 dB.

**Why one value, not one per stream.**
- JACK clients and pro-audio work at a locked rate run at the graph rate and are never resampled, so this setting never touches them.
- The 1.3 ms of filter delay q10 adds over q4 is small next to a Pulse stream's own buffering.
- Splitting by application would mean `pulse.rules` and `stream.rules` matched on app names, for a CPU saving of a tenth of a percent.

## Verification

- Measured as above. The scripts and raw results are in `research/resample-quality/` of manuaudio/omarchy-audio (`measure.py`, `cpu.py`, `quality.json`, `cpu.txt`).
- `pw-config --name client.conf merge stream.properties` and `--name pipewire-pulse.conf` report `resample.quality: 10` from the drop-ins. `spa-json-dump` parses the WirePlumber rule.
- The migration, run with `bash -euo pipefail` against a scratch `HOME` and `PIPEWIRE_CONFIG_DIR`:
  - installs the three files on a fresh home, and under a custom `XDG_CONFIG_HOME`;
  - does nothing on a second run;
  - does nothing when a quality is already set: one-line or multi-line, in user PipeWire, WirePlumber or `/etc/pipewire` config;
  - still installs when the only setting is commented out.
- `shellcheck` is clean. No test was added: config values and migrations don't get one.
- Not checked yet: a live PipeWire picking the drop-ins up (`pw-dump` showing `resample.quality` on a Pulse stream and on an ALSA node), and a Bluetooth output.

## Screenshots

No visible change: this only changes PipeWire's resampler quality.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
