# Add pro audio mode for recording

Branch `audio-pro`, on `quattro` (`e485c6224`). Supersedes omacom/omarchy#13838.

## What changes

PipeWire sizes its buffer for whatever is playing, and there is no way to bring it down short of `pw-metadata` by hand. On an Omarchy desktop with nothing else asking, a player runs the graph at 2048 frames, 43 ms per cycle at 48 kHz (`pw-top`, below), which is far too late to play an instrument or monitor a recording through.

`omarchy audio pro on` forces a small buffer and locks the sample rate in PipeWire's `settings` metadata, the buffer size and format settings of macOS's Audio MIDI Setup. It applies at once and nothing restarts.

- **Default buffer: 256 frames, or 128 once PipeWire runs realtime.** Smaller buffers drop out on a non-realtime audio thread. Realtime is read the way `omarchy-realtime-repair` reads it.
- **Pick your own:** `on --buffer 64 --rate 96000`. Each choice changes only itself, and only what was picked is saved, so an unpicked buffer keeps following realtime.
- **It stays on across logins.** The choice is a toggle flag, `~/.local/state/omarchy/toggles/audio-pro`. PipeWire forgets forced settings when it restarts, so `on` installs a small oneshot unit, `WantedBy=pipewire.service`, that sets them again each time PipeWire starts. `off` removes it.
- **`off` never clears what something else forced.** If a DAW forced its own buffer since, that one stays. It also works with PipeWire down, forgetting the choice and the unit.
- _Trigger > Toggle_ gets Pro Audio On / Off, guarded by `omarchy-toggle-enabled audio-pro`, and the toggle notifies like the others. The manual's toggles chapter gets a row and a short section.

No power-profile change: Omarchy already keeps a profile per AC and battery, and a second owner would fight it.

## Verification

- `test/shell.d/audio-pro-test.sh` (new, stubbed `pw-metadata`, `systemctl`, `ps`): the 256 and 128 defaults, choices kept apart and restored after a PipeWire restart, `off` leaving a foreign buffer, `off` with PipeWire down, a bad buffer refused with nothing changed, `status --json`. Two of its checks were confirmed to fail with the logic they guard removed.
- `test/cli`, `i18n-test.sh` (and `I18N_STRUCTURAL=1`), `scripts/i18n-sync.py extract-scan --check`, `menu-test.sh` (toggle pair rules), `menu-guards-test.sh`: pass.
- On a running desktop (PipeWire 1.6.8, WirePlumber 0.5.17, not realtime), with silence playing into a null sink and `pw-top` reading the driver:

  | Step | Graph runs at |
  |---|---|
  | before | 2048 frames, 48000 Hz |
  | `on` | 256, 48000 |
  | `on --buffer 64`, then `on --rate 96000` | 64, 96000 |
  | settings cleared, as a PipeWire restart does | 2048, 48000 |
  | the unit started | 64, 96000 |
  | `off` | 2048, 48000 |
  | `on`, a buffer of 512 forced by hand, `off` | 512 kept |

Not checked: an actual PipeWire restart or a new login (the unit was started by hand after clearing the settings, which is what it sees), and a realtime PipeWire, which this machine doesn't have.

## Screenshots

No visible change in the shell: two rows under _Trigger > Toggle_ and a notification. The audio panel section is the next PR.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
