# List and connect MIDI ports from the audio panel

> **Moved to Backline.** Not proposed to Omarchy: this is now part of [Backline](https://github.com/manuaudio/backline-audio)'s Omarchy plugin. Kept as a record.

Branch `audio-midi`, on `audio-panel-pro`. The command half doesn't depend on it; the panel half does.

## What changes

The only ways to see or connect MIDI ports today are `aconnect -l` and `/proc/asound/seq/clients`. A keyboard plugged in sends nowhere until an app connects it, and nothing shows whether a device speaks MIDI 1.0 or 2.0. This is the MIDI half of macOS's Audio MIDI Setup, over the ALSA sequencer, whose ports PipeWire's MIDI bridge already mirrors to JACK and PipeWire apps.

- `omarchy audio midi` lists the ports: address, client, kind (hardware, app, virtual), protocol (MIDI 1.0, MIDI 1.0 over UMP, MIDI 2.0), direction and where each sends. `--json` for the panel, `--all` to include the sequencer's own client and PipeWire's bridge.
- `connect <source> <destination>` and `disconnect` wrap `aconnect`. `connect <source>` opens the menu with every destination, the current ones ticked, and what is ticked on Apply becomes its connections. Connections to PipeWire's MIDI bridge, which the menu doesn't offer, are never touched, and a failed change notifies. `connect` alone asks for the source first.
- The audio panel gets a MIDI section, shown only when a device or app has a port that sends: one row per port with its protocol and destinations ("MIDI 2.0 · to Surge XT"). Enter or a click hands it to the picker above, closing the panel first. The rows join the panel's cursor.
- The list is read when the panel opens, and the command pushes a refresh after each change.

## Verification

- `test/shell.d/audio-midi-test.sh` (new, a sequencer fixture through `OMARCHY_SEQ_CLIENTS_PATH`, as the `hw-` commands take theirs): a MIDI 2.0 keyboard with a `[real:0]` connection and one to PipeWire's bridge (left out of its `sendsTo` and never disconnected), destinations, plumbing left out; the picker opened with the connection ticked and without the source itself, and the picks applied as one disconnect and one connect.
- `audio-test.sh`: which ports the panel lists and in what order, labels, captions. `audio-panel-runtime-test.sh` gains the MIDI row: up from the pro audio switch reaches it, Enter runs `omarchy-audio-midi connect 24:0` and closes the panel.
- `i18n-test.sh`, `extract-scan --check`, `qml-text-format-test.sh`, `test/cli` and the rest of the panel checks: pass.
- On this machine's sequencer, with a stand-in keyboard app and `aseqdump`: `connect 14:0 <aseqdump>` and a note sent into Midi Through arrived (`Note on … note 60`); after `disconnect` nothing did. The menu flow (picker stubbed) replaced the keyboard's connection to Midi Through with aseqdump. Each change pushed `omarchy.audio refresh`.
- The real panel on a headless layer-shell surface with real key presses listed "OA Keys MIDI 1 · MIDI 1.0 · to aseqdump"; Enter handed it to the picker with aseqdump ticked and the panel closed.

Not checked: real MIDI hardware, a MIDI 2.0 device (parsing is covered by the fixture), Bluetooth MIDI, and the desktop's real menu picker. Ports that appear while the panel is open show on its next open, since the sequencer has no change signal the shell listens to.

## Screenshots

`screenshots/midi/1-midi-row.png`: the MIDI section above PRO AUDIO, the cursor on a keyboard that sends to aseqdump.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
