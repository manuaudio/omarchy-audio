# Omarchy Audio — design

Goal: give Omarchy what macOS gives through CoreAudio, CoreMIDI and Audio MIDI Setup, built into the OS as small, opinionated Omarchy pieces rather than as an extra app. Written 2026-11-11 on ai-nab6 (Omarchy 4.0.4 package, upstream `quattro` at `ea79ff24b`, kernel 7.2.5-3-omarchy, PipeWire 1.6.8, WirePlumber 0.5.17).

Short version: the Linux engine is already there. PipeWire is one graph with one clock and adaptive resampling, it speaks the JACK API, the kernel speaks MIDI 2.0, and ALSA has a full sequencer. What's missing is the *system layer*: one place and one command set that make those pieces behave like a Mac. Here that means buffer and rate control, aggregate devices, MIDI ports and realtime that just works.

Revision 2, the same day, follows Manu's steer to be strategic about what Omarchy is built from:

- The system layer stays bash, as more of the existing `omarchy-audio-*` family.
- The one UI is a Quickshell panel plugin.
- There is no separate C library.

## Revision 4 (2026-11-12): a core for Omarchy, the rest in Backline

Omarchy's maintainers merge small, measured, invisible improvements, and rarely merge new modes, toggles or menus. So the work is split in two:

- **Omarchy audio core** goes upstream: defaults and fixes that make audio better for every Omarchy user, with no new mode, toggle or menu row, each one small PR in Omarchy's own style. The list, ranked, is in [ROADMAP.md](ROADMAP.md). An item that might be a feature goes to the plugin, not the core.
- **Everything "pro"** moved into [Backline](https://github.com/manuaudio/backline-audio)'s Omarchy plugin: pro audio mode (`omarchy-backline-pro`), aggregate and multi-output devices (`omarchy-backline-aggregate`), the MIDI manager (`omarchy-backline-midi`) and the PRO AUDIO and MIDI sections, now Backline's Audio Setup panel. They keep Omarchy's command, menu, panel, keyboard, theme and notification conventions, so they feel like stock Omarchy, and their tests moved with them.

Sections 3 to 6 below describe the pro pieces as they were first designed for Omarchy itself. The branches in section 6 are kept as a record and are not proposed upstream.

## Principle: sample rate is agnostic to the user (2026-11-12)

Manu, verbatim:

> "sample rate should be agnostic to the user, just letting you know in a subtle way as a user if you look for it that SRC is on, and that is a conversion process, but you should be able to play at whatever sample rate and digital audio should flow and flow cleanly"

Nobody picks a sample rate to play something. Three things follow, one per layer:

1. **The rate follows the source wherever the hardware allows.** Core: `default.clock.allowed-rates = [ 44100 48000 88200 96000 ]`, so an idle device switches to the stream's rate (#17520, ROADMAP item 1). As Manu put it later: "force the sample rate of the hardware to the sample rate of the file that's playing if it's available."
2. **When conversion is unavoidable, it is transparent and silent.** That happens with a second stream at another rate, hardware that lacks the rate, or a Bluetooth link. Core: `resample.quality = 10` for streams and for ALSA and Bluetooth device nodes (ROADMAP item 2, `prs/5-resample-quality.md`).
   - Measured with PipeWire's own resampler, PipeWire's default quality 4 is −13 dB at 20 kHz between 44.1 and 48 kHz.
   - Quality 10 is flat within 0.002 dB to 20 kHz with every artefact below −140 dBFS. It costs 0.1% of one core per stereo stream on this box (0.27% when adapting to clock drift), and its filter delay is 1.9 ms.
   - It has no toggle and no warning, and it is one value, not one per stream. JACK and pro-audio work run at the graph rate and are never resampled, so a cheaper setting for "realtime" streams would save nothing that matters.
3. **The user sees that SRC is on only if they look for it.** Plugin: Backline's `omarchy-backline-src` lists each stream whose rate differs from its device's. The Audio Setup panel shows "SRC 44.1 → 48 kHz · Spotify" in muted caption text under the pro-audio header, and on a combined device's row, only while it is happening. There's no colour, bar icon or notification. This is Backline's D11. Omarchy itself gets no indicator: that would be a new visible element, which belongs in the plugin.

Pro audio's locked rate (Backline) is the one deliberate exception, and the user chooses it for recording.


## 1. macOS → this box

Each row was checked on the live system: `pw-dump`, `wpctl`, `pw-metadata`, `pw-top`, `aconnect`, `/proc/asound`, `/proc/config.gz`, `ps -L`.

| macOS layer | What users and developers get there | What this box has | Gap |
|---|---|---|---|
| **CoreAudio HAL: devices** | Every device is an object with properties (channels, rates, latency, buffer size) and change notifications | PipeWire nodes from ALSA, BlueZ and virtual sinks, enumerable with `pw-dump`. 1 card (HDA Intel PCH): HDMI out, analog in | No friendly device view with channels and kind. Latency and headroom are buried in node params |
| **Aggregate device** | Stack interfaces into one N-channel device, choose the clock source, drift correction | `libpipewire-module-combine-stream` is shipped, with `combine.latency-compensate`. PipeWire already drives everything from one clock and resamples followers, which is CoreAudio's drift correction | Not exposed at all. Using it means writing a config file and restarting PipeWire. No clock-source choice (`priority.driver`) |
| **Multi-output device** | Same audio on several outputs | Same module, mirroring mode | Same as above |
| **Clock, sample rate, buffer** | Per-device rate and buffer size in Audio MIDI Setup and in each DAW | Global graph clock in the `settings` metadata (`clock.rate`, `clock.allowed-rates`, `clock.force-quantum`, `clock.force-rate`), switchable live. Measured: a client that asks for no latency runs the graph at **2048 frames (43 ms)** | No user control except `pw-metadata` by hand. Sample-rate following is Manu's open #17520 |
| **Realtime scheduling** | Every IOProc thread is realtime, no setup | **Not working on this box.** No rtkit, so `mod.rt: RTKit error: ServiceUnknown`, and the data loop runs `TS` (SCHED_OTHER). `ulimit -r` is 0, memlock is 8 MB, and there's no `realtime-privileges`. Kernel: `PREEMPT_DYNAMIC` booted `full`, HZ=1000, no `threadirqs` | Fixed upstream in #16824 (rtkit plus `omarchy-realtime-repair`, in packages ≥ 4.5), but this box runs 4.0.4. The rlimit path for JACK-style apps is still open in #7971. The login-linger case is #18110/#18128 |
| **Device power behaviour** | Devices stay hot while an audio app is open | WirePlumber suspends idle ALSA nodes after 5 s, so the first note after a pause re-opens the device | No "keep devices awake while recording" |
| **AudioToolbox / AudioUnits** | One plugin format (AU) with system-wide discovery (`auval`, AudioComponentRegistrar) | LV2 (`lilv` 0.28, `lv2` 1.18), CLAP and VST3 by convention. User dirs only: `~/.lv2` (17 bundles), `~/.clap` (14), `~/.vst3`. No `/usr/lib/{clap,vst3}`, and no host or scanner tool installed | No system plugin index or validator. The search paths are the formats' own standard dirs, so no env vars are needed |
| **AVAudioEngine** | An in-app node graph engine with a simple API | PipeWire filter-chain (config-level LV2/builtin graphs; Omarchy's speaker tuning uses it). JACK API through `pipewire-jack` | No simple app-level engine API. That belongs in a library, not in Omarchy |
| **CoreMIDI: devices and endpoints** | Device → entity → source/destination model, change notifications, unique IDs | The ALSA sequencer: client → port, with R/W caps. PipeWire's `Midi-Bridge` mirrors every port into the graph, so JACK and PipeWire apps see the same ports | No manager. The only views are `aconnect -l` and `/proc/asound/seq/clients` |
| **Virtual ports, IAC Driver** | Apps create virtual sources and destinations; IAC gives named buses | Kernel `snd-seq-dummy` ("Midi Through") is loaded with **1 port**, and works as a bus (proved below). Any app can create user seq ports. `snd-virmidi` is available as a module | No named buses. A persistent user-made port needs a process to hold it, or the root module option `snd-seq-dummy ports=N` |
| **Network MIDI** | RTP-MIDI (AppleMIDI) sessions in Audio MIDI Setup | PipeWire implements AppleMIDI in `module-rtp-session`, but it ships in **`pipewire-zeroconf`, which isn't installed**. `aseqnet` (non-standard TCP) is present | Package, firewall ports and a session UI |
| **MIDI 2.0 / UMP** | MIDI 2.0 in CoreMIDI (UMP event lists, MIDI-CI) | Kernel: `SND_UMP=m`, `SND_UMP_LEGACY_RAWMIDI=y`, `SND_SEQ_UMP=y`, `SND_SEQ_UMP_CLIENT=m`, `SND_USB_AUDIO_MIDI_V2=y`. `aplaymidi2`/`arecordmidi2` are installed. `/proc/asound/seq/clients` reports each client's protocol. PipeWire 1.6 bridges UMP, and the JACK API has `jack.flag-midi2` | Nothing shows the protocol to users, and no API exposes UMP simply |
| **Bluetooth MIDI** | Supported | `bluez_midi.server` node present | None |
| **Audio MIDI Setup.app** | One place for all of the above | Omarchy has the shell audio panel (volume, output picker, per-app mixer), `omarchy audio tuning`, and `omarchy restart audio`. There is no Setup > Audio | **The main gap**: no single place |
| **Pro networking (AVB, NetJACK, VBAN)** | AVB in Audio MIDI Setup | `module-avb`, `netjack2-*` and `vban-*` are shipped | Fine for later; no UI needed now |

### The real gaps, in order of value

1. **Realtime isn't on.** On this box it's fixed by `omarchy update` (root): 4.5 brings rtkit and the repair script. Upstream, the remaining cases are #7971 (rlimits/memlock for apps that don't use rtkit) and #18110 (linger).
2. **No buffer-size or rate control.** The single most common pro-audio action, "drop the buffer to record", has no UI.
3. **No aggregate or multi-output devices**, although the engine (combine-stream plus PipeWire's single clock) does them well.
4. **No MIDI view or manager**: ports, connections, protocol (1.0 vs 2.0), monitoring.
5. **No IAC-style buses and no network MIDI.** Both are small root-level steps on top of shipped code.
6. **No single "Audio MIDI Setup" entry.**
7. **For developers, no CoreAudio/CoreMIDI-shaped API.** The JACK API covers the IOProc part. Device enumeration and hotplug, settings, aggregates and UMP MIDI are scattered across libpipewire and alsa-lib.
8. **No system plugin index** across LV2, CLAP and VST3.


## 2. What Omarchy is built from, and how it ships

Learned from a read-only clone of upstream and from its issues and PRs. Canonical repo: `omacom/omarchy`, branch `quattro`.

### What it's written in (counted on `quattro`)

| Layer | What Omarchy uses | Count / evidence |
|---|---|---|
| System commands | Bash, `#!/bin/bash`, with `gum` for prompts | 554 of 593 `bin/` scripts (29 Python, 10 `bash -p`) |
| Desktop UI | The Omarchy shell, Quickshell QML: `shell/plugins/{bar,panels,…}`, shared `shell/Commons` (incl. `AudioNodes.qml`) and `shell/Ui` | Volume, outputs and the app mixer already live in `shell/plugins/panels/audio` |
| Omarchy's own apps | C++ and Qt Quick/QML with CMake, one binary per app, packaged for Arch | Hype, Monologue, Omacut, Omacalc, Omawrite, Plain, Signed. The repo's `omarchy-app` agent skill makes this *the* way to build an Omarchy app |
| Rust and Go | No longer an Omarchy pattern | Quattro retired wiremix, walker, elephant, swayosd, impala and bluetui (`omarchy-upgrade-to-quattro` removes them; dhh's commit a157b98d5 "No longer need wiremix" moved audio into the shell panel). Rust remains only in third-party tools it ships, such as herdr and gliff |

So the strategic shape is **bash commands plus a QML panel**, with C++/Qt only if a real app is ever needed. A Rust or C library would be a third language with no home in Omarchy.

### How features ship

- **Commands.** One `bin/omarchy-<group>-<name>` per feature, with `# omarchy:summary/args/examples` headers that drive the `omarchy <group> <name>` router. The audio family today is `omarchy-audio-{input-mute, input-set-default, output-set-default, output-sink, output-switch, output-volume, sink-availability, source-switch, tuning}`; `omarchy-audio-tuning` is the multi-action precedent (`on|off|status`).
- **Shell plugins.**
  - First-party plugins live in `shell/plugins/panels/<name>/` with `manifest.json`, `Panel.qml` and a pure `Model.js` that Node tests load.
  - Bar popups extend `Ui/Panel.qml` and use `KeyboardPanel` with `PanelKeyCatcher` content.
  - Live state comes from Quickshell services (`Pipewire`), never polling. When only Omarchy commands change something, they push `omarchy-shell -q <target> refresh`.
  - Strings live in `default/i18n/en/shell.json` and are read with literal `I18n.t("…")` keys.
- **Everything else.**
  - Data files go in `default/`, user config is copied from `config/`, and one-shot changes go in `migrations/`.
  - Packages are listed in `install/*.packages`.
  - Menus are data in `default/omarchy/omarchy-menu.jsonc`, plus `default/i18n/en/menu.json`.
- **Audio prior art to copy.** `omarchy-audio-tuning` hosts its graph in its own PipeWire client (`pipewire -c …` as a user service), so it never restarts audio. It also verifies its result and rolls back.
- **Contribution rules.** There's no CONTRIBUTING file and no AI ban; `AGENTS.md` and `agents/skills/*.md` are the rulebook. The PR template asks for one problem per PR, real verification output, and screenshots or a "No visible change" line. Tests only for real logic: none for config values, menu rows or migrations. `omarchybot` verifies PRs on a VM and labels them `verified`/`ready`.
- **Maintainer behaviour on audio.**
  - Merged: bug-framed fixes with evidence (rtkit #16824, #12958, pipewire-jack on ARM #15782) and hardware data (speaker tunings).
  - Ignored or rejected: niche config, vendor fixes that belong upstream or in the AUR, and new toggles without a maintainer yes. Manu's Discussion #13832 has had no maintainer reply in 6 weeks.
  - Lesson: frame each PR as a measured defect or obvious Mac parity, keep it to one problem, and don't self-close verified PRs.

## 3. Design

### Principles

- **Runtime first.** Anything that can be done live through PipeWire metadata or a separate PipeWire client is done live. Never restart `pipewire-pulse`: it drops every client.
- **The commands are the API.** Three more members of the `omarchy-audio-*` family: `omarchy audio pro`, `omarchy audio aggregate`, `omarchy audio midi`. The menu, the shell panel, scripts and agents all drive the same commands, and `--json` gives machines the same facts people see.
- **The shell panel is the one place** a person looks: Omarchy's Audio MIDI Setup.
- **Verify and roll back. Never take over someone else's state.**
- **Root only where the kernel or packages demand it**, each such step its own small PR.

### 3.1 Pro audio: `omarchy-audio-pro` (built)

- `on [--quantum N] [--rate R]`:
  - Forces the graph quantum (default 128 frames) and locks the rate (default: the current graph rate), both through `pw-metadata -n settings`. The change is live and needs no restart.
  - Sets the `performance` power profile for the session through `powerprofilesctl`, which works as a normal user (verified).
  - Warns when PipeWire's data loop isn't realtime.
  - Re-running while on changes only what's given.
- `off` restores PipeWire's defaults and the previous power profile.
- `status [--json]` gives a human report, or the panel's JSON.
- `--status [quantum=N|rate=R]` is the quiet form, for menu checkmarks.
- After `on` and `off` it pushes `omarchy-shell -q omarchy.audio-setup refresh`.
- **Runtime-only by design.** It writes a marker in `$XDG_RUNTIME_DIR`, nothing in `~/.config`, so a PipeWire restart or a new login returns to defaults (as #13838 proposed). A buffer forced by anything else is never switched off.
- Later:
  - Keep ALSA nodes awake in pro mode (a WirePlumber rule).
  - Device headroom.
- Root steps: rtkit (already upstream), realtime-privileges (#7971), and optionally `threadirqs`, but only if measured to help.

### 3.2 Aggregate and multi-output devices: `omarchy-audio-aggregate` (built)

Renamed from `omarchy-audio-devices`: the family already covers picking and switching devices (`output-switch`, `set-default`), and the shell panel lists them. This command does the one thing missing.

- `create <name> <device>...` stacks channels in member order into one N-channel sink or source (`AUX0..N-1`). This is Audio MIDI Setup's Aggregate Device.
- `create --mirror <name> <device>...` mirrors stereo onto every member. This is the Multi-Output Device.
- `create` with no arguments is the guided `gum` flow, for the menu and the panel's **+** button.
- `remove [name]` (a `gum` picker without a name). `list` shows candidate devices with node names, and the devices made here.
- **Mechanism.**
  - Each device is a `combine-stream` module (with `combine.latency-compensate`), hosted by its own PipeWire client: `omarchy-audio-aggregate@<slug>.service` running `pipewire -c omarchy-audio-aggregate-<slug>.conf`. This is the same pattern as the speaker tuning.
  - Creating or removing one never restarts audio. Members can be unplugged and replugged.
  - PipeWire's single driver plus adaptive resampling plays the part of CoreAudio's drift correction.
- Later: a clock source (`priority.driver` WirePlumber rule), and pro-audio card profiles for USB interfaces.

### 3.3 MIDI: `omarchy-audio-midi` (built: list, connect, disconnect, monitor)

- `list [--all] [--json]` covers every ALSA sequencer port. For each it gives:
  - address, client and kind (hardware, virtual, app);
  - **protocol** (MIDI 1.0, MIDI 1.0 over UMP, MIDI 2.0 UMP);
  - CoreMIDI direction (source, destination) and connections.

  It also reports MIDI 2.0 UMP endpoints and PipeWire's MIDI bridge.
- `connect` and `disconnect` wrap `aconnect`, and push a panel refresh. `monitor` wraps `aseqdump`.
- Later, in order:
  1. IAC-style named buses (root: `options snd-seq-dummy ports=4`).
  2. Connections restored at login, driven by sequencer announce events.
  3. Network MIDI (root: `pipewire-zeroconf` for AppleMIDI `module-rtp-session`, plus ufw rules).
  4. MIDI 2.0 function blocks in the list.

  User-named virtual ports without root need a process holding a sequencer client. Unless (1) turns out not to be enough, that isn't worth a compiled helper.

### 3.4 The one UI: an Audio MIDI Setup shell panel (prototype built)

`shell/plugins/panels/audio-setup/` is a first-party-shaped bar-widget plugin, `omarchy.audio-setup`, next to the existing audio panel. Left click opens it, right click toggles pro audio, and `p` toggles it from the keyboard.

| File | Job |
|---|---|
| `manifest.json` | `bar-widget`, category Audio |
| `Panel.qml` | `Ui/Panel` + `BarIconButton` + `KeyboardPanel`/`PanelKeyCatcher`. Answers its own IPC target, adding `refresh` |
| `SetupState.qml` | The data and the actions. **Devices come live from Quickshell's `Pipewire` service** through `PwObjectTracker`, filtered by `Commons/AudioNodes` (the shell's own meters, platform nodes) and snapshotted to primitive rows, as the audio panel does to avoid dangling `PwNode`s. **Clock settings and MIDI ports**, which no Quickshell service exposes, come from `omarchy-audio-pro status --json` and `omarchy-audio-midi list --json`, read on open and on pushed refreshes; there is no timer polling. Actions queue in order, so a click is never dropped |
| `Card.qml` | The visible card: a hero with the pro-audio `ToggleSwitch` and a live clock summary (mode · frames · kHz · ms); a realtime warning; `ButtonGroup`s for buffer (64–1024) and rate (44.1–96 kHz); devices with channels and kind, aggregates highlighted with a remove button, and **+** for the guided create; MIDI ports with protocol, direction and connections |
| `Model.js` | Pure rules (status and MIDI parsing, chosen chips, kind, sort), Node-tested |
| `shell/i18n/en/shell.audio-setup.json` | 25 `audioSetup.*` strings, to merge into `default/i18n/en/shell.json` |

The Setup › Audio menu rows (`default/omarchy/omarchy-menu-audio.jsonc`) stay as keyboard entry points, now with an "Audio MIDI Setup" row that opens the panel.

**Question for upstream:** a separate bar widget, or a "Setup" section folded into the existing audio panel? Folding in is less to add to the bar. The separate plugin is easier to review and to opt into (see section 7).

### 3.5 Developer layer: no new library

The commands with `--json`, plus Quickshell's PipeWire service, are the developer surface Omarchy itself needs. Its shell, menu, agents and scripts all consume them. Every macOS concept in scope maps to one:
- `AudioObject` devices: the PipeWire service or `pw-dump`.
- Buffer and rate: `omarchy-audio-pro`.
- `AudioHardwareCreateAggregateDevice`: `omarchy-audio-aggregate`.
- CoreMIDI endpoints and connections: `omarchy-audio-midi`.
- IOProc: the JACK API through `pipewire-jack`, already shipped.

The C library (`pwhal`) from revision 1 is dropped. If an *app* ever needs this (an Omarchy-made DAW-side utility, a MIDI monitor app), build it the way Omarchy builds apps: C++ and Qt Quick, perhaps with a small QML module (`Omarchy.Audio`) wrapping libpipewire and alsa-lib for QML, which the shell could later reuse. Rust (pipewire-rs) only makes sense for contributing to Rust tools outside Omarchy; see wiremix below.

**wiremix.** It's a good Rust PipeWire TUI (1.1k stars, Apache-2.0, active), but Quattro removed it from Omarchy, so features added there don't reach Omarchy users.
- It has no CONTRIBUTING, AGENTS or PR-template file, so there's no stated AI policy; ask in the issue before sending AI-assisted code.
- There's one open request for MIDI views (tsowell/wiremix#17, "Show JACK, MIDI, video connections").
- Verdict: a worthwhile goodwill contribution for the wider Linux audio community, especially MIDI ports in its graph view, but **not** the strategic path into Omarchy.

### 3.6 Plugin hosting

- **Paths.** The formats' standard dirs (`~/.lv2` and `/usr/lib/lv2`, `~/.clap` and `/usr/lib/clap`, `~/.vst3` and `/usr/lib/vst3`). No env vars needed.
- **System plugin index.** A separate project for later, written in the language of whatever consumes it. Most likely a small bash or Python scanner emitting JSON that a shell panel reads, since lilv ships `lv2ls` and VST3 bundles carry `moduleinfo.json`.
- **In Omarchy.** At most Install › Audio (DAWs and plugin bundles), following Install › Gaming, and only if maintainers want it.

## 4. What needs root (later steps; none were done here)

| Step | Why | Where |
|---|---|---|
| `omarchy update` to ≥ 4.5 on this box | rtkit and `omarchy-realtime-repair` (#16824). The panel warns until then | Already upstream |
| `realtime-privileges`, `realtime` group, limits | Apps that use rlimits rather than rtkit | #7971 |
| `options snd-seq-dummy ports=4` in `/etc/modprobe.d/` | IAC-style MIDI buses | install step + migration |
| `pipewire-zeroconf` + ufw UDP 5004/5005 | Network MIDI (AppleMIDI) | `omarchy-pkg-add` on first use |
| `threadirqs` | Only if measured | Probably out of scope |
| DAW and plugin packages | Install › Audio | `omarchy-pkg-add` |

Everything else is user space: metadata, power profile, user units, `~/.config/pipewire`, `aconnect`, the shell plugin.

## 5. Roadmap of small upstream PRs (superseded)

Superseded by revision 4: the current plan is [ROADMAP.md](ROADMAP.md). Items 3 to 11 below are in Backline now.

First, no code: update Discussion #13832 with section 1's measurements, the panel screenshots and this list, and ask for a yes on items 3–7. Keep #17520 open.

| # | PR (one problem) | Size | Framing | Root? |
|---|---|---|---|---|
| 1 | *Let PipeWire follow the source's sample rate* (open **#17520**) | +29 | Mac parity, measured resampling | no |
| 2 | Help land **#7971** and **#18128** with evidence | small | Bug: no RT for some apps and boots | yes |
| 3 | *Add pro audio mode for recording* (`bin/omarchy-audio-pro`, a Setup › Audio row, i18n, a manual line) | ~180 + a small test of the marker and foreign-quantum logic | Measured: a 2048-frame (43 ms) graph with no way down; supersedes #13838 | no |
| 4 | *Add an Audio MIDI Setup panel* (`shell/plugins/panels/audio-setup`, strings, Node test), showing pro audio, buffer, rate and devices | ~600 QML/JS | The one place, with screenshots. Alternatively fold it into the audio panel if maintainers prefer | no |
| 5 | *Keep audio devices awake in pro audio mode* | ~20 | Bug: late or popping first note after 5 s idle | no |
| 6 | *Play on several outputs at once* (`omarchy-audio-aggregate create --mirror`, host config, unit, the panel's **+**) | ~250 | Broad appeal (speakers + headphones) | no |
| 7 | *Record from several interfaces as one device* (`create` without `--mirror`) | ~60 | Pro parity | no |
| 8 | *List and connect MIDI ports* (`omarchy-audio-midi`, the panel's MIDI section) | ~150 | Mac parity; shows MIDI 2.0 | no |
| 9 | *Give MIDI four virtual buses like macOS's IAC Driver* | ~15 | Parity | yes |
| 10 | *Restore MIDI connections at login* | ~120 | Connections are lost on replug and login | no |
| 11 | *Add network MIDI sessions* | ~150 | Macs and iPads on the LAN | yes |
| 12 | *Add an audio production page to the manual* | docs | Discoverability | no |
| 13 | *Add Install › Audio*, only on a yes | ~40 | Precedent: Install › Gaming | yes |

Items 3 and 4 can ship together if a maintainer wants to see the toggle *in* the panel. Otherwise 3 lands first with a menu row, and the panel follows.

**Outside Omarchy:**
- MIDI views in wiremix (#17), as a community contribution, after asking about AI-assisted PRs.
- A plugin index, if and when a panel needs it.
- A C++/Qt app or QML module, only if a real app needs one.
- Kernel tuning notes.
- Hardware UCM fixes go to alsa-ucm-conf.

## 6. The slice (this repo; moved to Backline)

Revision 3 (2026-11-11) reworked the prototype to upstream's standards (`STANDARDS.md`) and split it into local branches, each based on `quattro` at `e485c6224`, with its PR description in `prs/`:

| Branch | Base | Roadmap item |
|---|---|---|
| `audio-pro` | `quattro` | 3: pro audio mode, persisted across logins, 256 frames until realtime works, 128 after |
| `audio-panel-pro` | `audio-pro` | 4: a PRO AUDIO section folded into the existing audio panel (no separate bar widget) |
| `audio-aggregate` | `quattro` | 6 and 7 together: aggregate and multi-output devices, _Setup > Audio_ rows |
| `audio-midi` | `audio-panel-pro` | 8: MIDI ports, connect/disconnect, and a MIDI section in the audio panel |

Decisions taken in revision 3: the panel is a section of `omarchy.audio`; pro mode persists through a toggle flag and a user unit; pro mode no longer touches the power profile (Omarchy already keeps one per AC and battery); `monitor` was dropped from the MIDI command; desktop prompts use `omarchy-menu-select`, not `gum`.

The harness, kept out of this repository: `headless` (a private headless sway for Quickshell tests), `panel-shot` (the real panel on real layer-shell with real key presses, screenshots in `dev/screenshots/`), `live-pro`, `live-aggregate`, `live-midi` (live tests on a PipeWire and sequencer) and `seq-port`.

## 7. Open questions for Manu

Answered by revision 4 where they concern Omarchy itself (no new modes, toggles or panels upstream). The rest are Backline's questions now.

1. Should pro mode **persist across logins**, or stay **runtime-only** (as #13838 proposed)?
2. **Default buffer**: 128, or 256 (safer without rtkit)?
3. **Panel placement**: propose a separate Audio MIDI Setup bar widget, or a Setup section inside the existing audio panel?
4. **Order of asks** in #13832: lead with pro mode plus the panel, or with multi-output?
5. **wiremix**: worth a community PR for MIDI views (#17), knowing it no longer reaches Omarchy users?
6. Do you want **DAW and plugin installers** (Install › Audio) at all?
