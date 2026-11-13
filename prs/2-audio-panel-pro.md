# Add pro audio to the audio panel

> **Moved to Backline.** Not proposed to Omarchy: this is now part of [Backline](https://github.com/manuaudio/backline-audio)'s Omarchy plugin. Kept as a record.

Branch `audio-panel-pro`, on `audio-pro` (the previous PR).

## What changes

The audio panel gets a PRO AUDIO section at the bottom, so the buffer and sample rate are changed where volume and outputs already are, rather than in a separate window.

- The switch sits on the section's header line, as the network panel's Automatic band switch does. While pro audio is on, the header says how long one buffer takes (`PRO AUDIO · 2.7 ms`), and two rows of pills appear: buffer (64 to 1024 frames) and sample rate (44.1 to 96 kHz). They collapse with the switch, the way the band pills do.
- When PipeWire isn't running realtime, one line in the urgent colour says small buffers may drop out.
- Keyboard: the section joins the panel's one cursor. j/k reach the switch and the two pill rows, h/l walk a row, Enter or Space activates. The cursor parks on the value in force, and moves to the switch when switching off takes the pills away. `m` does nothing here rather than muting the output.
- The values come from `omarchy-audio-pro status --json`, read when the panel opens and after each change it makes; the command pushes `omarchy-shell -q omarchy.audio refresh` when the menu or a terminal changes them, and a closed panel ignores it and reads on open. No timer. The audio panel answers its own IPC target to add `refresh`.
- A click while a change is still running waits, and only the latest one does.
- The section hides when PipeWire isn't answering.

## Verification

- `audio-test.sh`: status parsing (nothing, an error, or a zero buffer hide the section), the header, the rate labels, where the cursor parks.
- `audio-panel-runtime-test.sh` (new, modelled on `network-panel-runtime-test.sh`): the real `Panel.qml` against a stub `omarchy-audio-pro`, driven through its key catcher: Enter on the switch, j to the buffer pills parked on 256, h, Enter sets 128; the rate row; down stops at the last row; three clicks in a row run the first and the last only; switching off moves the cursor to the switch. Removing the cursor clamp fails it.
- `i18n-test.sh`, `qml-text-format-test.sh`, `motion-test.sh`, `keyboard-panel-lazy-test.sh`, `plugin-manifest-scan-test.sh`, `plugin-registry-contract-test.sh`, `test/cli`: pass.
- The real panel, on a real layer-shell surface (a headless sway, so nothing mapped on the desktop in use), with real key presses through a virtual keyboard, against this machine's PipeWire: j×31, Enter turned pro audio on; j h Enter set 128 frames; j l l Enter set 96 kHz and kept 128; `omarchy audio pro on --buffer 512` from a terminal reached the open panel through the push; k k Enter turned it off; Esc closed the panel.

Not checked: the panel inside Hyprland's real bar (the tests ran it under sway with a stand-in bar strip), and the bar's Tab switching between panels.

## Screenshots

Before: the audio panel ends with the app mixer.

After, from the run above (`screenshots/pro/`):
- `1-pro-off.png`: the section with the switch off.
- `2-pro-on.png`: on at 256 frames, 48 kHz, with the realtime warning.
- `3-128-at-96k.png`: 128 frames at 96 kHz, `PRO AUDIO · 1.3 ms`.
- `4-pushed-512.png`: after `omarchy audio pro on --buffer 512` in a terminal.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
