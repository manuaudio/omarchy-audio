# Combine audio devices into aggregate and multi-output devices

> **Moved to Backline.** Not proposed to Omarchy: this is now part of [Backline](https://github.com/manuaudio/backline-audio)'s Omarchy plugin. Kept as a record.

Branch `audio-aggregate`, on `quattro` (`e485c6224`).

## What changes

There is no way to play on two outputs at once (speakers and headphones), or to record from two interfaces as one device, without writing PipeWire config and restarting audio. macOS has both in Audio MIDI Setup as Multi-Output and Aggregate devices. PipeWire already ships the mechanism, `combine-stream`, and clocks every member from one driver while resampling the rest, which is macOS's drift correction.

`omarchy audio aggregate` makes them:

- `create Studio <input-1> <input-2>` stacks the members' channels in order into one device (interface A on 1-2, B on 3-6). Members are all inputs or all outputs.
- `create --mirror Everywhere <output-1> <output-2>` plays the same stereo on every output.
- `remove Studio`, and `list` for the device names to use.
- _Setup > Audio_ gets Aggregate Device, Multi-Output Device and Remove Combined Device. They pick the members with `omarchy-menu-select --multiple` and ask for a name with `omarchy-menu-input`, so no terminal opens.

Each device is hosted by its own PipeWire client in a user unit (`omarchy-audio-aggregate@<name>`), the way the speaker tuning is, with the tuning's minimal host config: making or removing one restarts nothing, and a broken one stops only itself. A device that never appears in PipeWire is removed again. A mono member of a multi-output device gets the stereo mixed down. Names are kept to letters, digits, spaces, dots, dashes and underscores, since they go into PipeWire config. Latency between members is compensated. An unplugged member drops out and comes back when replugged.

The device's own streams to its members are kept out of the audio panel's app mixer, like the tuning's.

## Verification

- `test/shell.d/audio-aggregate-test.sh` (new, stubbed `pw-dump` and `systemctl`): channel stacking with a member that has no positions, mirroring, mixed directions, mirrored inputs and a name with a quote refused with nothing written, a device that never appears removed again, the menu flow's picks becoming the members in order, the last removal taking the unit with it.
- `test/cli`, `i18n-test.sh`, `extract-scan --check`, `menu-test.sh`, `menu-guards-test.sh`, `audio-test.sh`, `qml-text-format-test.sh`: pass.
- On a running desktop, with null sinks and virtual sources as members:
  - A 4-channel aggregate of two stereo outputs: a 1 kHz tone on channel 3 measured RMS 0.190 on member B's left channel and 0.000 on every other channel.
  - Member B unloaded: the device stayed. Reloaded under the same name: linked back in within 2 s.
  - A multi-output device played a tone on both members (RMS 0.192 each).
  - An aggregate of two stereo virtual sources has 4 channels.
  - A multi-output device with a mono member linked its stream to the mono port and the stereo one to FL and FR.
  - Removing all three left no node, unit or config behind, and the default output and input never moved.

Not checked: real USB interfaces with their own clocks, and the menu flow itself (it needs the desktop's menu; its parsing is covered by the test with a stubbed picker).

## Screenshots

`screenshots/aggregate/1-output-list.png`: "Everywhere" in the audio panel's output list, and no stray "Everywhere output" streams in the mixer (before the filter, its two member streams showed there).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
