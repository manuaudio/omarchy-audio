# Roadmap

Omarchy gets a small audio **core**: invisible defaults and fixes that make audio better for every Omarchy user, with no new mode, toggle or menu row. Everything pro lives in [Backline](https://github.com/manuaudio/backline-audio), an Omarchy plugin.

## How core PRs go upstream

- One at a time, in Omarchy's own style ([STANDARDS.md](STANDARDS.md)): the smallest diff, their checks green, a short measured PR text.
- Only when a maintainer engages, or for a clear bug fix with a reproduction.
- Nothing is opened while it would duplicate someone else's open PR; a tested review of theirs is better.
- Anything that could be read as a feature goes to Backline instead.

## Core, ranked

Checked against `quattro` on 2026-11-12.

| # | Change | Why everyone gains | Upstream status | Next |
|---|---|---|---|---|
| 1 | Let PipeWire follow the source's sample rate: `default.clock.allowed-rates = [ 44100 48000 88200 96000 ]`, the list PipeWire itself ships disabled | 44.1 kHz music and 88.2/96 kHz files reach the device without resampling, as on a Mac | Open as omacom/omarchy#17520; rebased on current `quattro`, +29 lines; refs #10534 | Wait for a maintainer; text in [prs/0-sample-rate-follow.md](prs/0-sample-rate-follow.md) |
| 2 | Convert transparently when the rate can't follow: `resample.quality = 10` for streams and ALSA/Bluetooth devices | PipeWire's default quality 4 is −13 dB at 20 kHz converting 44.1 ↔ 48 kHz; quality 10 is flat within 0.002 dB with artefacts below −140 dBFS, for 0.1% of a core per stereo stream (measured, `research/resample-quality/`) | Branch `resample-quality` (`config/` drop-ins + migration, +73 lines); not opened: the open-PR cap is full | Open after #17520 moves; text in [prs/5-resample-quality.md](prs/5-resample-quality.md) |
| 3 | Switching the input doesn't move a recording of the desktop: `omarchy-audio-input-set-default` moves every capture stream that isn't a filter's own, including one recording an output's monitor (wf-recorder's desktop track) | A screen recording's desktop audio stays desktop audio | Not fixed, not proposed | Reproduce on a private PipeWire with null sinks first; then a 2-line fix and a case in `audio-pactl-test.sh` |
| 4 | Volume keys keep the left/right balance: `omarchy-audio-output-volume` sets every channel to the first channel's level | Balance set elsewhere survives a key press | Not fixed, not proposed | Low priority; only after 1 or 2 lands |

Already proposed by others, so supported with a tested review rather than a duplicate: USB interfaces shown by name instead of all as "USB Audio" (#17807), unplugged inputs (#18725), mic mute with no microphone (#18559, #18208), no default output (#18560), realtime for apps that don't use rtkit (#7971), realtime with login linger (#18128).

Already in Omarchy: rtkit and the realtime repair (#16824), `pipewire-jack` and `pipewire-alsa` (also on ARM, #15782), `alsa-utils`, the ALSA sequencer modules.

Left out of core: buffer, headroom and suspend-timeout defaults (no measured defect, and some cost battery), and anything with a switch.

## Moved to Backline

| Was (branch here) | Now in Backline's Omarchy plugin |
|---|---|
| `audio-pro`: `omarchy audio pro` | `omarchy-backline-pro`, Trigger › Toggle › Pro Audio, `Super + Ctrl + Alt + A` |
| `audio-panel-pro`: PRO AUDIO in the audio panel | The Audio Setup panel's PRO AUDIO section |
| `audio-aggregate`: `omarchy audio aggregate` | `omarchy-backline-aggregate`, Setup › Audio |
| `audio-midi`: `omarchy audio midi` and the MIDI section | `omarchy-backline-midi`, Setup › Audio › MIDI Connections, the Audio Setup panel's MIDI section |

Still to come in Backline: keeping devices awake in pro audio mode, IAC-style MIDI buses, MIDI connections restored at login, network MIDI, and a mixing console.
