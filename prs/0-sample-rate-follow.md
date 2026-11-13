## What changes

PipeWire's `clock.allowed-rates` is `[ 48000 ]` on a stock install, so every 44.1 kHz track and every 88.2/96 kHz recording is resampled on its way to the device. On macOS, CoreAudio follows the source's rate.

- `config/pipewire/pipewire.conf.d/10-sample-rates.conf` sets `default.clock.allowed-rates = [ 44100 48000 88200 96000 ]`. When a stream starts on an idle device, PipeWire switches the device to the stream's rate if the hardware supports it; otherwise it resamples as today. 48 kHz sources are unaffected.
- The migration installs the drop-in under `${XDG_CONFIG_HOME:-$HOME/.config}` and sets the same list on the running graph with `pw-metadata`, since PipeWire reads `conf.d` only at startup. Nothing restarts and playback isn't interrupted. Anyone who already set `allowed-rates` in a user or `/etc/pipewire` config is left alone.

The list is the one PipeWire ships, disabled, as `/usr/share/pipewire/pipewire.conf.avail/10-rates.conf`. Its docs say it is off by default "because of various kernel and Bluetooth issues", and #10534 lists pops on a rate switch with some Bluetooth, HDMI and cheap USB devices as the reason to keep it opt-in. I haven't hit that on the output below, but it is the only one I've tested. Screen recordings keep their fixed 48 kHz from #11092.

Refs #10534 (the rate half; the soft-mixer half is separate). Step one of #13832, rebuilt from the closed #13834.

## Verification

- On Omarchy 4.0.4, PipeWire 1.6.8, Intel HDA HDMI output, I played a 44.1 kHz file with `pw-play` before and after the migration and read `pw-top`:

  ```
  before: clock.allowed-rates [ 48000 ]
  R   44   2048  48000  12.2us  55.6us  0.00  0.00   22    S32LE 2 48000 alsa_output.pci-0000_00_1f.3.hdmi-stereo
  R   74   4410  44100  36.0us  41.8us  0.00  0.00    0    S16LE 2 44100  = pw-play

  after:  clock.allowed-rates [ 44100 48000 88200 96000 ]
  R   44   1024  44100   7.4us  10.0us  0.00  0.00   22    S32LE 2 44100 alsa_output.pci-0000_00_1f.3.hdmi-stereo
  R   74   4410  44100   9.5us  14.1us  0.00  0.00    0    S16LE 2 44100  = pw-play
  ```

  The device itself switched to 44100, so the stream is no longer resampled. `pw-config --name pipewire.conf merge context.properties` reported the drop-in's list, so it holds after a restart.
- The migration, run with `bash -euo pipefail` against a scratch `HOME` and `PIPEWIRE_CONFIG_DIR` with `pw-metadata` stubbed: installs and sets the rates on a fresh home and under a custom `XDG_CONFIG_HOME`; does nothing on a second run, or when the rates are already set in `~/.config/pipewire` or `/etc/pipewire`; still installs when the only setting is commented out; exits 0 when PipeWire isn't running.
- `shellcheck` is clean. No test added: config values and migrations don't get one.
- Not checked: USB DACs, Bluetooth outputs, and hardware that can't do 44.1 kHz.

## Screenshots

No visible change: this only changes PipeWire's sample-rate selection.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
