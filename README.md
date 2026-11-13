# Omarchy audio

Better audio for [Omarchy](https://github.com/omacom/omarchy), in two parts:

- **The core, for Omarchy itself.** Small defaults and fixes that make audio better for every Omarchy user, with no new mode, toggle or menu row, each sent upstream as one small PR in Omarchy's style. The ranked list and how they go upstream: [ROADMAP.md](ROADMAP.md).
- **Pro audio, as a plugin.** Pro audio mode, aggregate and multi-output devices, and the MIDI manager now live in [Backline](https://github.com/manuaudio/backline-audio), an Omarchy plugin: Mac-style pro audio for Omarchy Linux.

## The core

| # | Change | Status |
|---|---|---|
| 1 | Let PipeWire follow the source's sample rate | Open upstream as [omacom/omarchy#17520](https://github.com/omacom/omarchy/pull/17520); PR text in [prs/0-sample-rate-follow.md](prs/0-sample-rate-follow.md) |
| 2 | Convert transparently when the rate can't follow (`resample.quality = 10`) | Measured, branch ready, not opened (PR cap); PR text in [prs/5-resample-quality.md](prs/5-resample-quality.md) |
| 3 | Switching the input leaves a recording of the desktop alone | To reproduce first |
| 4 | Volume keys keep the left/right balance | Later |

## Moved to Backline

These four branches were first written for Omarchy itself, on `quattro` (`e485c6224`). They stay here as a record and are not proposed upstream; the code, with its tests, is in Backline's `omarchy/` plugin.

| Branch | What it added | Now |
|---|---|---|
| [`audio-pro`](../../compare/quattro...audio-pro) | `omarchy audio pro on/off`: a small PipeWire buffer and a locked sample rate | `omarchy-backline-pro` |
| [`audio-panel-pro`](../../compare/audio-pro...audio-panel-pro) | A PRO AUDIO section in the audio panel | Backline's Audio Setup panel |
| [`audio-aggregate`](../../compare/quattro...audio-aggregate) | Aggregate and multi-output devices on PipeWire's `combine-stream` | `omarchy-backline-aggregate` |
| [`audio-midi`](../../compare/audio-panel-pro...audio-midi) | List and connect ALSA sequencer ports | `omarchy-backline-midi` |

Their PR texts are in [prs/](prs/), and the screenshots below are from them.

| Pro audio, 256 frames at 48 kHz | 128 frames at 96 kHz | MIDI port | Multi-output device |
|---|---|---|---|
| ![](screenshots/pro/2-pro-on.png) | ![](screenshots/pro/3-128-at-96k.png) | ![](screenshots/midi/1-midi-row.png) | ![](screenshots/aggregate/1-output-list.png) |

## Also here

- [DESIGN.md](DESIGN.md): the design, from macOS's CoreAudio, CoreMIDI and Audio MIDI Setup to this split.
- [STANDARDS.md](STANDARDS.md): Omarchy's conventions as this work follows them.
- [research/PARITY.md](research/PARITY.md): parity with CoreAudio, CoreMIDI and Audio Units.

The code in the branches is Omarchy's, under its [MIT license](https://github.com/omacom/omarchy/blob/quattro/LICENSE).
