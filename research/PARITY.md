# Omarchy Audio: parity with CoreAudio, CoreMIDI and Audio Units

Research and design, 2026-11-11, on ai-nab6: kernel 7.2.5-3-omarchy, PipeWire 1.6.8, WirePlumber 0.5.17, alsa-lib 1.2.16.1, lilv 0.28.0, lv2 1.18.10. It follows `../DESIGN.md`, which covers the system-layer commands (`omarchy-audio-pro`, `-aggregate`, `-midi`) and the Audio MIDI Setup panel. This document is about parity, and its main question is **what "Audio Units for Omarchy" should be**.

Tags used in the tables:
- **[live]** checked on this box.
- **[doc]** read in a primary source (listed in §7).
- **[unverified]** could not be confirmed.

The "Where" column says who builds each piece:
- **Omarchy**: bash commands, config, migrations or the Quickshell panel, as in DESIGN.md.
- **Upstream**: PipeWire, WirePlumber, ALSA or the kernel.
- **New**: a standalone project outside Omarchy.

---

## 0. Top findings

1. **The engine is at parity or better. The system layer isn't.**
   - PipeWire already gives CoreAudio's single clock, drift-corrected aggregates, per-node latency and exclusive links.
   - The kernel already speaks MIDI 2.0 (UMP rawmidi, sequencer UMP, the USB MIDI 2.0 host driver and the f_midi2 gadget).
   - The gaps are the user surface (DESIGN.md) and three real holes:
     - no plugin registry or validation;
     - no CLAP or VST3 in PipeWire's filter-chain;
     - no MIDI-CI anywhere in the stack.
2. **"Audio Units for Omarchy" should be CLAP as the preferred format, with a registry over all formats. It should not be a new format.**
   - CLAP is the only open format that covers everything AU does: instruments, effects, note effects (AU's `aumi`), preset discovery, a validator, and a wrapper that projects it into VST3/AU/AAX.
   - LV2 stays first-class, because it's what PipeWire can load today and is the most widely packaged format on Linux.
   - VST3 has been MIT since SDK 3.8.0 (Oct 2025) [doc], so its licensing objection is gone.
3. **There is no Linux equivalent of AudioComponent, and nobody owns one.**
   - There's no freedesktop spec and no shared scan daemon. Two LAD threads (2009, 2018) died.
   - Every host rescans every plugin in-process, with its own cache. The prototype shows a shared, out-of-process registry is small: 641 plugins, 3 formats, 1.7 s cached and 68 s with full validation.
4. **Validation needs two tiers.**
   - clap-validator 0.4.1 is strict. **0 of 214** installed CLAP plugins pass every test, and 177 have only conformance findings (mostly state round-trips).
   - 37 failed hard: the plugin crashed in the validator's sandbox (22 were LSP plugins when the sample rate or block size changed), or it failed basic processing, as Dexed did.
   - So like `auval`, gate on "crashes or can't process", and report the rest as conformance findings.
5. **A plugin can already be a system effect on a device, live, without restarting audio and without the app knowing**, through filter-chain plus a WirePlumber *smart filter*. The prototype measured an LV2 low-pass on a device:
   - 5 kHz dropped by **62 dB** (−15.1 → −77.1 dBFS);
   - system-level bypass through the `filters` metadata;
   - live control changes;
   - clean removal.

   macOS needs a HAL driver or a third-party app such as SoundSource or Audio Hijack to do this. Here it is the area where Linux can **exceed** macOS.
6. **The biggest single upstream contribution is a `clap` plugin type for PipeWire's filter-graph.** The loader already resolves `type = X` to `filter-graph/libspa-filter-graph-plugin-X.so` [live]. With that type, any CLAP effect becomes a system effect, and the shell and any app could load it. No MR or issue exists for it [doc]. The closest is #420, opened by CLAP's author, which is still open.
7. **MIDI: PipeWire 1.6.8 here carries MIDI 1.0 bytes, not UMP.** The bridge ports report `8 bit raw midi` and `api.alsa.seq.ump` is unset [live].
   - The 1.4 notes made UMP the default. The current docs say "Since 1.7, Midi1 is preferred again" [doc].
   - So MIDI 2.0 apps should use ALSA seq UMP clients or UMP rawmidi directly for now.
   - MIDI-CI (profiles, property exchange) exists only in user-space libraries (ni-midi2, AM_MIDI2.0Lib). Nothing on the system exposes it, which is a gap against macOS 15's `MIDICIDeviceManager` and `MIDIUMPEndpointManager`.

---

## 1. CoreAudio parity matrix

| macOS feature | Linux/PipeWire equivalent today | Gap | Where |
|---|---|---|---|
| **HAL object model**: AudioObject → AudioDevice / AudioStream / AudioControl / AudioClockDevice. Properties are addressed by selector, scope and element, and `AudioObjectAddPropertyListenerBlock` delivers changes [doc] | PipeWire globals: Device → Node → Port, each with *props* (static) and *params* (EnumFormat, Props, Latency, ProcessLatency, Route), and change events on the registry. Read with `pw-dump` or Quickshell's `Pipewire` service [live] | Same model, richer but unfriendly. There's no "device with N channels, rates, buffer range, latency" summary | Omarchy: the panel's device view (DESIGN 3.4) |
| **Aggregate device**: `AudioHardwareCreateAggregateDevice`, sub-device list, `MainSubDeviceKey`/`ClockDeviceKey`, per-sub-device `DriftCompensationKey` and quality 0–0x7F [doc] | `module-combine-stream` (`combine.mode`, `combine.latency-compensate`, `combine.on-demand-streams`) [doc]. PipeWire runs one driver per graph and resamples followers adaptively (the 0.3.52 notes; drift handling isn't on the module page [unverified]) | No per-member drift-quality knob. The resampler quality is global (`resample.quality`). Built as `omarchy-audio-aggregate` | Omarchy (built). Upstream: per-stream `resample.quality` in combine-stream, if ever needed |
| **Multi-output device**: primary device + "Use" set [doc] | combine-stream in mirror mode [live, DESIGN 6] | Done | Omarchy (built) |
| **Clock source**: `kAudioDevicePropertyClockSource` (internal/word clock/S/PDIF), `ClockDevice` [doc] | Two levels:<br>1. *Which device drives the graph*: `priority.driver` (sink here: 696 [live]), settable with a WirePlumber rule.<br>2. *The interface's own clock input*: an ALSA mixer control ("Clock Source", "Sync Source") on USB/PCIe interfaces, set with `amixer`/UCM | No UI for either. Level 2 differs per interface | Omarchy: a "clock" row in the panel (driver choice via a WP rule fragment; hardware clock via the card's ALSA control when one exists) |
| **Per-device buffer, rate, latency**: `BufferFrameSize` + `Range`, `NominalSampleRate` + `Available...`, `Latency`, `SafetyOffset`, stream latency [doc] | Graph-wide `clock.quantum`/`force-quantum`/`force-rate` (live: rate 48000, quantum 128, min 64, max 2048 [live]). Per-node `node.latency`, `node.lock-quantum`, `api.alsa.period-size`, `api.alsa.headroom`. Latency params per port, propagated through the graph [doc] | The buffer is per *graph*, not per device. That's fine for one interface and is how JACK users think. Latency is reported but nobody shows it | Omarchy: `omarchy-audio-pro` (built) and the panel. Show "round trip = in + out + quantum" from the Latency params |
| **Hog mode / exclusive access**: `kAudioDevicePropertyHogMode` = owning pid [doc] | `node.exclusive` (link a stream exclusively to a device) and `port.exclusive`, enforced since 1.5.81/1.6.0 [doc]. Raw `hw:` ALSA access when PipeWire releases the device | No "give this app the device" action, and no pid shown | Omarchy: a panel action that sets `node.exclusive` via a WP rule for the chosen app. Upstream: report the owner on the node |
| **IOProc realtime model**: `AudioDeviceCreateIOProcID`; the callback runs on the HAL IO thread, the primary thread of the device's workgroup [doc] | JACK API through `pipewire-jack` (process callback on the RT data thread), or `pw_filter`/`pw_stream` process callbacks. module-rt uses RLIMIT_RTPRIO, then rtkit, then the portal. Since 1.4 every client gets RT data threads [doc] | **RT is off on this box** (no rtkit: `RTKit error: ServiceUnknown` in the prototype's host log [live]). It's fixed by Omarchy ≥ 4.5 (#16824) | Omarchy (upstream already). DESIGN 4 |
| **Realtime workgroup** `os_workgroup`: `kAudioDevicePropertyIOThreadOSWorkgroup`, `AUAudioUnit.osWorkgroup`, `os_workgroup_join`, `max_parallel_threads` (macOS 11) [doc] | **No equivalent.** PipeWire has `pw_thread_utils_acquire_rt` (priority only), JACK has `jack_client_create_thread` (priority only), and CLAP has the `thread-pool` extension, where the host runs the plugin's jobs on host threads. Linux has no deadline group that ties a plugin's worker threads to the device cycle | Real gap, mostly for multi-threaded synths. The nearest Linux tools are SCHED_DEADLINE and uclamp (module-rt already sets `uclamp.min/max` [doc]) | Upstream/New: a "PipeWire workgroup" API (join the driver's cycle and deadline, uclamp hint). Long-term, design-only |
| **Default / system (alert) output**: `DefaultOutputDevice`, `DefaultSystemOutputDevice` ("Play alerts through") [doc] | `default.audio.sink` / `default.configured.audio.sink` metadata [live]. `media.role = Notification` exists [doc]. WirePlumber's role-based linking can route roles to role sinks (`policy.role-based.target`), but "may not work as expected on desktop" [doc] | No "alerts go to device X" | Omarchy: a WP rule that sends `media.role=Notification` (and event-sound streams) to a chosen sink, exposed in the panel. Small |
| **Process taps**: `AudioHardwareCreateProcessTap(CATapDescription)`, macOS 14.2 [doc] | Native: any node's monitor ports, or any app's output ports, can be linked to a recorder (`pw-record --target <app>`, `stream.capture.sink`). The prototype records a device monitor [live] | No gap in the engine (Linux is ahead). There's no "record this app" UI, and no permission model like `NSAudioCaptureUsageDescription` outside the portal | Omarchy: optional "record app" in the panel. Permissions are portal territory, out of scope |
| **Spatial audio**: PHASE, `AVAudioEnvironmentNode`, `AUSpatialMixer`, head tracking, personalized HRTF (macOS 15) [doc] | filter-chain `sofa` plugin (HRTF from SOFA files, Azimuth/Elevation/Radius live), installed [live]. Example graphs `sink-virtual-surround-*`, `sink-matrix-spatialiser` [live] | No head tracking, no personalized HRTF, no app-level object API | Omarchy: offer the virtual-surround graph as a device effect (same mechanism as the prototype). Head tracking is a New project and low priority |
| **Audio MIDI Setup › Audio**: format, volume, Configure Speakers, aggregate, multi-output, clock source, drift "Sync", alerts device, hardware rate converter [doc] | Covered piece by piece above | DESIGN 3.4's panel. Add: speaker layout (`audio.position` / pro-audio profile), alerts device, clock row | Omarchy |
| **AVAudioEngine** (in-app node graph, manual and offline render) / **AUGraph** (deprecated in favour of AVAudioEngine) [doc] | No system app-level graph API. PipeWire filter-chain is a *config-level* graph. In-app engines come from JUCE, Tracktion Engine and similar | Not a system concern. Keep it out of Omarchy (DESIGN 3.5) | — |
| **Audio server plug-ins** (HAL drivers in user space) [doc] | SPA plugins and PipeWire modules: virtual devices, network (RTP/AES67/AVB/VBAN/NetJACK2 [live]) | Equivalent | — |

---

## 2. CoreMIDI parity matrix

Linux columns: **seq** = ALSA sequencer; **UMP** = ALSA UMP rawmidi `/dev/snd/umpC*D*`; **PW** = PipeWire MIDI (seq bridge, control ports); **JACK** = JACK MIDI via pipewire-jack; **kernel** = gadget, dummy and virmidi modules.

| macOS feature | seq | UMP | PW | JACK | kernel | Gap / Where |
|---|---|---|---|---|---|---|
| **Device → entity → endpoint**, `kMIDIPropertyUniqueID`, setup-changed notifications [doc] | client → port, R/W caps, `SND_SEQ_PORT_SYSTEM_ANNOUNCE` for hotplug [doc][live: client 0:1 Announce] | one device per UMP Endpoint; Function Blocks via `SNDRV_UMP_IOCTL_BLOCK_INFO` [doc] | one `Midi-Bridge` node with a port per seq port [live] | ports per client | — | Seq client:port numbers aren't stable across reboots, so no unique ID. **Omarchy**: `omarchy-audio-midi` keys ports by client *name* + port name for restore (DESIGN 3.3 item 2) |
| **Virtual sources/destinations**: `MIDISourceCreateWithProtocol` / `MIDIDestinationCreateWithProtocol`, reusable unique ID [doc] | any client can create user ports, which live as long as the process [doc] | `snd_seq_create_ump_endpoint()` creates a virtual UMP endpoint (alsa-lib 1.2.13) [doc] | `pw_filter` control ports | `jack_port_register` | `snd-virmidi` (rawmidi-backed seq ports) [live: module present] | Equivalent API. A *named persistent* port needs a holder process. **Omarchy**: buses via `snd-seq-dummy ports=N` (root). **New** (optional): a tiny user service that holds named ports |
| **IAC Driver** (named buses) [doc] | `snd-seq-dummy` "Midi Through": `ports` (live: 1), `duplex`, and **`ump` (0/1/2)**, which makes it a MIDI 1.0 or MIDI 2.0 UMP loopback [live: modinfo] | — | bridged | bridged | the same module | **Omarchy** (root, one modprobe line): `options snd-seq-dummy ports=4 ump=1`. DESIGN 3.3 item 1, now with the `ump` option |
| **Network MIDI**: `MIDINetworkSession`, sessions "Network MIDI 2.0 or RTP" in AMS [doc] | `aseqnet` (non-standard) [live] | — | `module-rtp-session` = AppleMIDI with mDNS discovery, `sess.media = midi`, in **`pipewire-zeroconf`, not installed** [live][doc] | via PW | — | RTP-MIDI 1.0: package + ufw + session UI (**Omarchy**, root). **Network MIDI 2.0** (UDP, the MIDI Association's 2024 spec, which macOS 15 supports): nothing on Linux → **Upstream** PipeWire (a sibling of rtp-session) |
| **Bluetooth LE MIDI** [doc] | BlueZ's own MIDI plugin creates seq ports (bluetoothd here has MIDI strings; `--enable-midi` [unverified]) | — | `bluez_midi.server` node present [live]; WP `monitor.bluez-midi.servers` [doc] | via PW | — | Engine present. No pairing UI that says "MIDI". **Omarchy**: a panel row and doc. Two competing stacks (BlueZ seq vs PW): pick PW |
| **MIDI 2.0 UMP I/O**: `MIDIEventList`, `MIDISendEventList`, automatic protocol translation [doc] | UMP clients (`midi_version` 1/2), automatic legacy↔UMP conversion, ports 1–16 = groups [doc]. `/proc/asound/seq/clients` shows "Legacy"/"UMP" [live] | full UMP rawmidi [doc] | 1.4+ can carry UMP (`SPA_CONTROL_UMP`), but on this 1.6.8 the bridge ports are `8 bit raw midi` and `api.alsa.seq.ump` is unset [live]. pw-cat `--midi-clip` plays MIDI 2 clips [doc] | `jack.flag-midi2` (off by default) [doc] | USB MIDI 2.0 host driver (`midi2_enable`, `midi2_ump_probe`) [live] | Kernel and ALSA at parity. PipeWire defaults to MIDI 1.0 bytes. **Omarchy**: show the protocol (built in `omarchy-audio-midi`). **Upstream**: a documented UMP switch per client |
| **MIDI-CI**: discovery, profiles, property exchange. macOS 15 adds `MIDICIDeviceManager`, `MIDIUMPEndpointManager`, `MIDIUMPFunctionBlock`, and deprecates `MIDICISession`/`DiscoveryManager` [doc] | SysEx only; "MIDI-CI is supported in user-space over the standard SysEx" (kernel doc) [doc] | Endpoint/Function Block *info* only (UMP stream messages) | none [doc] | none | — | **Gap.** No system service answers MIDI-CI discovery or lists a device's profiles or properties. **New**: a MIDI-CI daemon on ni-midi2 or AM_MIDI2.0Lib that watches UMP endpoints and publishes results (JSON for the panel, plus a seq port). Long-term |
| **Function blocks / endpoint info** (`MIDIUMPEndpoint.functionBlocks`) [doc] | `SNDRV_SEQ_IOCTL_GET_CLIENT_UMP_INFO`; inactive groups marked [doc] | `SNDRV_UMP_IOCTL_ENDPOINT_INFO` / `BLOCK_INFO` [doc] | — | — | gadget: `ep.N/block.N/` configfs [doc] | **Omarchy**: show blocks in `omarchy-audio-midi list` (DESIGN 3.3 item 4) |
| **Timestamps and scheduling**: `MIDITimeStamp` = host time, future-timestamped events delivered on time [doc] | queues with tick and real-time (ns) scheduling, skew [doc] | raw, no scheduling | sample-accurate offsets inside a cycle [doc] | frame offsets inside a cycle | — | At parity (seq queues = CoreMIDI scheduling; PW/JACK = AU's sample-accurate events) |
| **MIDI Studio** view: devices, icons, ports, connections, MIDI-CI profiles, test setup [doc] | `aconnect -l` | — | `pw-link -l` | `jack_lsp -c` | — | **Omarchy**: the panel's MIDI section (built: list, connect, monitor). Add a "test" (send a note, watch for it) and saved configurations |
| **Per-app MIDI routing** (each app picks endpoints) | per-app subscriptions [live] | exclusive open | per-app links; WP doesn't auto-link control ports [doc] | per-app | — | At parity. **Omarchy**: restore connections at login (DESIGN 3.3 item 2) |
| **Be a USB MIDI 2.0 device** (Mac as a peripheral: not a macOS feature) | — | — | — | — | `f_midi2` gadget via configfs [doc]. **No UDC on this box**, and `dummy_hcd` is available as a module [live] | Linux exceeds macOS on device-mode hardware. On ai-nab6, only `dummy_hcd` (root) for testing UMP software end to end |

---

## 3. The Audio Units equivalent

### 3.1 What Audio Units actually give a Mac

| AU capability | Mechanism [doc] | Why it matters |
|---|---|---|
| **System-wide registry** | `AudioComponentDescription` (type/subtype/manufacturer: `aufx`, `aumu`, `aumf`, `aumi`, `augn`, …). Installed in `~/Library/Audio/Plug-Ins/Components` or `/Library/...`. The registrar rescans at boot, login and folder change. `AudioComponentFindNext`, `AVAudioUnitComponentManager` | Every host sees the same list, without scanning itself |
| **One format every app hosts** | AU is the OS format: Logic, GarageBand, AVAudioEngine and many small apps | A plugin bought once works everywhere, including non-DAW apps |
| **Out-of-process, sandboxed hosting** | AUv3 = app extension, out-of-process by default. `kAudioComponentInstantiation_LoadInProcess` opts in (macOS only) | A crashing plugin doesn't take the host down |
| **Validation** | `auval` ships with macOS (API conformance plus basic render). Logic refuses units that fail | A baseline before a plugin reaches users |
| **MIDI effects and instruments** | `aumu` (instrument), `aumi` (MIDI processor) | Arpeggiators and chord tools are first-class |
| **Presets** | `factoryPresets`, `userPresets` (10.15), `fullState`, `.aupreset`. User presets are "available across all host applications" | Presets follow the plugin, not the host |
| **The plugin view in hosts** | `requestViewController` → `AUViewController` | Any host can show any plugin's UI |
| **Inter-app audio** | IAA is deprecated (iOS 13) in favour of AUv3 | Apps as plugins |

### 3.2 The Linux candidates, measured against that list

| | **CLAP** | **LV2** | **VST3** | **LADSPA** |
|---|---|---|---|---|
| Version / licence | 1.2.10 (2026-07), MIT [doc] | lv2 1.18.10, lilv 0.28.0, ISC [doc][live] | SDK 3.8.0 (2025-10) **MIT** (VSTGUI and mda BSD-like), now 3.8.1 [doc] | 1.1, frozen legacy |
| Instruments / effects / MIDI fx | `instrument`, `audio-effect`, **`note-effect`**, `note-detector`, `analyzer` features [doc] | `InstrumentPlugin`, `MIDIPlugin`, ~38 classes [doc] | `Instrument`, `Fx` subcategories. No MIDI-effect class | effects only |
| Metadata without loading code | no: `clap_entry` → factory (fast by spec) [doc] | **yes**: Turtle (lilv reads it without dlopen) | **yes**: `moduleinfo.json` since 3.7.5 (200 of 213 here [live]) | no |
| Presets | `preset-discovery` factory (stable `/2`), indexable without instantiating [doc]. Only Surge XT ships one here [live] | `presets` ext, RDF on disk (5 of 214 here [live]) | `.vstpreset` files | none |
| Validator | **clap-validator 0.4.1** (out-of-process, 44 tests, JSON) [doc][live] | `lv2_validate` + sord (TTL lint only); no runtime suite | Steinberg `validator` in the SDK (now MIT) | none |
| Host-side threading | `thread-pool` ext (the closest thing to `os_workgroup`) | worker ext (non-RT jobs) | none | none |
| Out-of-process hosting | none standard; clap-validator's sandbox is the only out-of-process CLAP host found [doc] | Carla bridges | Bitwig-style per host | — |
| Wrapper to other formats | **clap-wrapper** v0.17: CLAP → VST3, AUv2, AUv3, AAX, standalone. **There is no reverse direction** (no VST3/LV2 → CLAP) [doc] | — | — | — |
| Linux hosts | Bitwig, REAPER, Qtractor (since 0.9.27), Zrythm v2 (alpha), Carla `main` only (not in 2.5.10). **Ardour: none**, and its lead calls CLAP redundant with LV2 [doc] | Ardour, Carla, Qtractor, Zrythm, Mixbus, **PipeWire filter-chain** [live] | all major hosts | Ardour, PipeWire |
| In PipeWire filter-chain | **no** (no MR or issue; #420 open) [doc] | **yes** [live] | no (#74 closed) [doc] | yes [live] |
| Frameworks | DPF, nih-plug (→ nice-plug), iPlug2, JUCE via clap-juce-extensions (JUCE 9 has no native CLAP) [doc] | DPF, JUCE (8+), nih-plug: no | all | DPF |
| Installed here | 214 plugins in 17 binaries [live] | 214 [live] | 213 [live] | 0 |

What this shows:
- **No format alone is AU.** AU is a format *plus* an OS service: the registry, validation on install, out-of-process instantiation, and system-wide presets.
- On Linux the formats exist and the OS service is missing. So the project is the service, and the format choice is about what the service *prefers*, not what it *accepts*.

### 3.3 Recommendation: "Omarchy Audio Units"

**A. CLAP is the preferred system format; LV2 and VST3 are accepted.**
- CLAP is the only open format that spans every AU capability above, including note effects and indexable presets.
- It has a real validator, and clap-wrapper lets a CLAP-first plugin also ship VST3 and AU, so vendors don't have to choose.
- LV2 remains the format PipeWire can load today and the best one for metadata, since nothing has to be loaded to read it.
- VST3 is MIT now, so nothing keeps it out of an open system.
- When the same product exists in several formats (212 of 215 products here ship CLAP + VST3 + LV2 [live]), the registry marks one *preferred* entry. That's CLAP unless it fails validation, then VST3, then LV2.

**B. A system registry: `omarchy-audio-plugins`, the AudioComponent registry.**
- **Scan.** It scans the formats' own search paths (CLAP `CLAP_PATH` or `~/.clap:/usr/lib/clap`, VST3's ordered list, LV2 `LV2_PATH`). No new paths and no env vars.
- **Isolate.** Every binary is probed **in its own short-lived process**, so a crash or hang becomes a registry entry, not a broken scan. (The prototype caught a real `SIGABRT` this way: Cardinal Synth LV2.)
- **Output.** It writes one JSON registry at `$XDG_CACHE_HOME/omarchy/audio-plugins.json` (schema below), cached by path, size and mtime.
- **Users.** The panel, the menu, agents and any host can read it. A host that trusts it can skip its own scan.
- **Vocabulary.** `kinds` maps every format onto AU's vocabulary: `instrument` (`aumu`), `effect` (`aufx`), `midi-effect` (`aumi`), `analyzer`.

**C. Validation on install, in two tiers.**
- **Runs:**
  - CLAP: clap-validator, out-of-process.
  - LV2: a runtime check (instantiate, activate, run, check the outputs are finite). This is shallower than clap-validator, and an LV2 runtime suite is a New-project opportunity.
  - VST3: Steinberg's validator, which can be built now that the SDK is MIT.
- **Grades:**
  - `fail`: the plugin crashed in any test, or it can't load, scan or process basic audio. Hide it, or flag it red.
  - `warn`: conformance findings that hosts survive (state round-trip, parameter edge cases).
  - `pass`: no findings.
- **Trigger:** run on package install (a pacman hook calling the scan for the changed paths) and on login for `~/.clap`, `~/.lv2` and `~/.vst3` changes (a path unit).

**D. Plugins as system effects on devices: Omarchy's answer to "AU on a device".**
- **Mechanism.** filter-chain hosted in its own PipeWire client, exposed as a WirePlumber **smart filter** whose `filter.smart.target` is the device.
- **What the prototype proved:**
  - streams aimed at the device go through the plugin;
  - it switches on and off live through the `filters` metadata (`filter.smart.disabled`);
  - its controls change live through `Props`;
  - removing it is one process exit.
- **Today** this works for LV2, LADSPA, builtin, sofa and ebur128 (and ffmpeg and onnx where built; Arch's 1.6.8 doesn't ship those two [live]).
- **CLAP** needs the upstream filter-graph plugin (E).

**E. Upstream: a `clap` plugin type for PipeWire's filter-graph.**
- `libspa-filter-graph-plugin-clap.so`, a sibling of `plugin_lv2.c`.
- **Mapping:**
  - `type = clap` and `plugin = <path or id>`;
  - `audio-ports` → filter-graph audio ports;
  - `params` → control ports, with values sent as `CLAP_EVENT_PARAM_VALUE` input events at the start of each block;
  - `latency` → ProcessLatency;
  - `state` → optional.
- **Threading.** Follow CLAP's thread rules: `activate` on the main thread, `start_processing` and `process` on the data thread, and `on_main_thread` requests serviced through the PipeWire main loop.
- **Effects only at first.** No note ports and no GUI, the same scope the LV2 plugin has.
- **Out-of-tree is possible but fragile.** The loader is generic, but the plugin interface (`audio-plugin.h`) is in-tree and not installed (`/usr/include/spa-0.2/spa/filter-graph/` has only the graph API [live]). A drop-in would track an unstable ABI. **Contribute it upstream**, prototyped out-of-tree first.

**F. Out-of-process hosting: a standalone project, not Omarchy.**
- **What it is.** A CLAP host daemon (`clapd` or similar) that runs each plugin instance in a sandboxed worker process.
- **How it connects.** It joins the graph as a PipeWire `pw_filter` with RT data threads, and drives the plugin through shared-memory audio buffers.
- **What it adds:**
  - AUv3-style crash isolation for system effects;
  - instruments and MIDI effects as system nodes (a synth any MIDI controller plays without a DAW);
  - GUIs, via CLAP `gui` with Wayland once CLAP/VST3 Wayland embedding settles (VST3 3.8 added Wayland preview interfaces [doc]).
- **Building blocks:** clack's `clack-host` (Rust) or clap-helpers (C++). The design decision is whether the worker *is* a PipeWire client (simplest: each plugin a node) or the daemon proxies.
- **Recommendation:** each worker is its own PipeWire client node. PipeWire already *is* the cross-process graph, so there's no proxy to write.

**G. Presets: index, don't invent.**
- The registry lists CLAP preset-discovery providers and LV2 `pset:Preset` counts.
- A shared user-preset store, the AU `userPresets` equivalent, should wait. CLAP's preset-discovery already lets a plugin publish user presets to every host. Promote that rather than an Omarchy format.

**H. Plugin views.**
- Out of scope for the shell. The shell shows the registry and toggles device effects.
- Opening a plugin's own GUI is the daemon's job (F). The Quickshell panel then sends one IPC command to it.

### 3.4 What Omarchy maintainers would plausibly accept, and what goes elsewhere

DESIGN.md §2 says maintainers merge measured defects and obvious Mac parity, one problem per PR, in bash and QML. They ignore niche config and new toggles they haven't agreed to.

| Piece | Home | Why |
|---|---|---|
| `omarchy-audio-plugins scan/list` (registry JSON) | Omarchy, **only once a consumer exists**: the panel's Effects section or Install › Audio | A plugin index has no user value alone. The prototype is Python plus a 400-line C probe. For Omarchy it would be bash, with a small probe living with the standalone project (below) and packaged |
| "Effect on this device" (LV2 via filter-chain smart filter) | Omarchy, as a panel action plus `omarchy-audio-effect add/remove/bypass` | Same pattern as `omarchy-audio-tuning`, which already merged. Visible Mac-beating feature. Small |
| Validation on install (pacman hook) | Omarchy, after the registry | Fits `install/` and the hooks |
| `plugprobe` / registry core, LV2 runtime validator | **New**: "linux-audio-registry", a reusable scanner and spec | Every distro and host could share it. Propose an XDG cache location and schema on linux-audio-dev |
| CLAP filter-graph plugin | **Upstream PipeWire** | It belongs next to `plugin_lv2.c` |
| CLAP host daemon (out-of-process, instruments, GUIs) | **New** | Too big and too opinionated for Omarchy. Omarchy can package and surface it later |
| MIDI-CI daemon | **New**, possibly upstream later | No system owner exists yet |

---

## 4. Prototype (proof, not product)

Everything lives in `research/proto/`. It runs in user space only, without touching the user's devices, defaults or config.

| File | What it is |
|---|---|
| `plugprobe.c` | Loads **one** plugin binary and prints JSON. Writes out the CLAP and VST3 ABIs from the specs, so no SDK is needed. Modes:<br>• `clap FILE`: descriptors and features via `clap_entry`;<br>• `vst3 BUNDLE`: `GetPluginFactory`, `IPluginFactory2` class infos;<br>• `lv2-list`: lilv, TTL only;<br>• `lv2-check URI`: instantiate with urid, options, bounded-block and a synchronous worker, run 4×512 frames of a −12 dBFS sine, check the outputs are finite |
| `omarchy-audio-plugins` | The registry: `scan [--validate]`, `list [--kind] [--format]`, `show`. Every probe runs as a separate, time-limited process. It uses clap-validator for CLAP, prefers VST3 `moduleinfo.json` over loading code, groups products across formats, picks the preferred format, and caches by fingerprint |
| `registry-sample.json` | The summary plus four representative entries from the live scan |
| `fx-host.conf` | filter-chain host config: an LV2 node as a smart filter on `@DEVICE@`, in its own PipeWire client |
| `fx-proof` | The measured end-to-end proof (below). Writes `out/fx/report.txt` |

Build and run:

```
cd research/proto
cc -O2 -Wall -o plugprobe plugprobe.c $(pkg-config --cflags --libs lilv-0) -ldl -lm
cargo install --locked --git https://github.com/free-audio/clap-validator --tag 0.4.1 --root .tools clap-validator
./omarchy-audio-plugins scan --validate     # -> out/plugins.json
./omarchy-audio-plugins list --kind instrument
./fx-proof                                  # -> out/fx/report.txt
```

### 4.1 Registry results (live, 2026-11-11)

| | CLAP | VST3 | LV2 |
|---|---|---|---|
| Plugins found | 214 (17 binaries, incl. DPF bundle dirs with nested `.clap` files) | 213 (200 from `moduleinfo.json`, 13 by loading the factory) | 214 |
| Validation | clap-validator: **0 pass / 177 warn / 37 fail** | not validated | lv2-check: **213 pass / 1 fail** (Cardinal Synth: probe aborted, SIGABRT) |
| Presets | 1 preset-discovery factory (Surge XT) | — | 5 plugins with presets |

- **Kinds:** 40 instruments, 580 effects, 2 MIDI effects (Ildaeil-MIDI), 27 analyzers.
- **Products:** 215, of which 212 come in all three formats. The rest: 1 CLAP + LV2, 1 CLAP + VST3, 1 LV2 only.
- **Scan time:** 1.7 s cached, about 68 s with full validation, 0 scan errors. The CLAP plugins span spec versions 1.0.0–1.2.10.
- **What the 37 CLAP fails are:**
  - plugins that crashed the validator's sandbox: 30 LSP plugins (22 on varying sample rate or block size, 8 on descriptor or parameter tests), Cardinal and Cardinal Synth, the three Ildaeil plugins on parameter conversion, and Odin2;
  - Dexed, which failed basic note processing without crashing.

  The `warn` set is dominated by `state-reproducibility-*` (208 plugins) and `param-*` edge cases. Hosts tolerate these, which is why two tiers are needed (§3.3 C).
- **Cross-format identity is not declared anywhere.** LSP names its vendor "LSP CLAP", "LSP VST3" or "LSP LV2", and prefixes LV2 plugin names with "LSP". The grouping is therefore a heuristic. A shared registry spec should add an optional `product-id`, and CLAP's plugin id is the obvious anchor.
- **Probe isolation worked as designed.** One plugin aborted its probe and the scan carried on. Ildaeil prints to stdout even under `--hide-output`, and the registry tolerates that.
- **Two side effects a real service must contain:**
  - **Plugins write into the current directory when loaded.** Cardinal dropped a `mini.json` settings file into the scan directory. Probes now run in a throwaway directory.
  - **clap-validator leaves hung sandbox children behind.** Three `clap-validator sandbox` processes (LSP Mixer x8 Stereo, `process-varying-block-sizes`) were still running after the validator returned, and had to be killed by hand. The service should run each validation in its own `systemd-run --user --scope` with a runtime limit, so the whole cgroup dies with it. This is worth reporting to clap-validator.

### 4.2 System effect on a device, measured (`out/fx/report.txt`)

The test device is a null sink created for the test, `omarchy-au-proto.device`. Every stream is pinned to it with `node.dont-fallback`. The tone (a 2 s sine at −12 dBFS peak, −15.1 dBFS RMS) is played **at the device, not at the filter**. The device's monitor is recorded through hand-made links. The plugin is **LSP Filter Stereo (LV2)**, low-pass 500 Hz, slope ×4.

| Step | Player linked to | 200 Hz (dBFS RMS) | 5 kHz (dBFS RMS) |
|---|---|---|---|
| 1. No effect | device | −15.1 | −15.1 |
| 2. Effect loaded (smart filter on the device) | **omarchy-fx-proto** (WirePlumber inserted it) | −20.2 | **−77.1** (−62 dB) |
| 2b. System bypass: `pw-metadata -n filters <id> filter.smart.disabled true` | device | — | −15.1 |
| 2b. Bypass cleared | omarchy-fx-proto | — | −77.1 |
| 3. Live control `fx:enabled = 0` (plugin's own bypass) | omarchy-fx-proto | — | −15.1 |
| 4. Live control `fx:enabled = 1`, then `fx:f = 8000` | omarchy-fx-proto | — | L −25.4 / R −48.3 (see note) |
| 5. Host process stopped | device | — | −15.1; filter nodes gone |
| 6. Device destroyed | — | — | 0 proto nodes left; default sink unchanged (`alsa_output…hdmi-stereo`) |

Notes:
- **Measurement trap, worth knowing for the real feature.** A capture stream (`stream.capture.sink`) that targets the device is *also* redirected to the smart filter by WirePlumber, so it records the filter's **input**. The first run read −15.1 everywhere, even with `g_out = 0`. Recording must link to the device's monitor ports explicitly. A real "record what the device plays" feature has the same problem.
- **Step 4 is asymmetric.** Loaded from config with `f = 8000`, both channels read −25.4. After a *live* change from 500 to 8000 Hz, only the left channel matches. The right stays at −48.3, which is reproducible and survives a 1 s settle. Live `enabled` changes affect both channels. It's unresolved whether LSP or filter-graph's control propagation is at fault. A device-effect feature should reload the graph on structural parameter changes until this is understood, and it's worth a minimal reproducer upstream.
- RT was off for the effect host (no rtkit on this box), and it still processed cleanly at the 128-frame quantum.
- If the target device is missing, the filter-chain removes itself: its playback stream has `node.dont-fallback`, WirePlumber errors it, and the module unloads. That's the right failure mode for a device effect (no accidental audio elsewhere). The real feature needs a WirePlumber-side retry, or a user unit that restarts when the device reappears.

---

## 5. Roadmap

Phase numbers are order of value. Each Omarchy PR is one problem, framed as DESIGN.md §2 asks. These continue DESIGN.md §5's list (items 1–13 there), so they start at 14.

### Phase 1: finish the system layer (DESIGN.md items 1–13)
Already planned: pro audio, the panel, aggregates, MIDI list/connect, IAC buses, network MIDI, Install › Audio. One amendment from this research: **item 9 (IAC buses) should set `ump=1`** as well as `ports=4`, so the buses are UMP-capable and MIDI 2.0 apps see a UMP client (MIDI 1.0 conversion keeps legacy apps working). Verify on hardware first.

### Phase 2: Omarchy PRs for parity

| # | PR (one problem) | Size | Root? |
|---|---|---|---|
| 14 | *Send alert and notification sounds to a chosen output* (WP rule on `media.role=Notification`, panel row) | ~60 | no |
| 15 | *Choose the clock device* (`priority.driver` rule; the interface clock control when ALSA has one) | ~80 | no |
| 16 | *Show device latency* (panel: in + out + buffer, from Latency params) | ~60 QML | no |
| 17 | *Give one app exclusive use of an interface* (`node.exclusive` rule, panel action) | ~80 | no |
| 18 | *Add an effect to an output device* (`omarchy-audio-effect add/remove/bypass <device> <lv2-uri>`: filter-chain host per effect, as a smart filter; bypass through the `filters` metadata; uses the registry for the picker) | ~250 + panel | no |
| 19 | *Index installed audio plugins* (`omarchy-audio-plugins`, bash front over a packaged probe; only together with 18 or Install › Audio) | ~150 | no |
| 20 | *Validate plugins on install* (pacman hook + user path unit; two-tier status in the registry) | ~60 | hook yes |
| 21 | *Offer virtual surround on headphones* (the sofa graph as a device effect via #18) | ~40 | no |

### Phase 3: upstream contributions

| Project | Contribution | Notes |
|---|---|---|
| PipeWire | **`clap` filter-graph plugin type** (effects; params as controls; latency) | The headline item. Prototype out-of-tree against 1.6's `audio-plugin.h`, then open an MR referencing #420 |
| PipeWire | Report the reproducer from §4.2 (a live control change reaching only one channel), if it's in filter-graph | Small; first confirm it isn't LSP |
| PipeWire | Network MIDI 2.0 (UDP) next to `module-rtp-session` | macOS 15 parity |
| PipeWire | Document and stabilise the UMP switch for the seq bridge and clients (1.6 vs 1.7 behaviour) | Docs + config |
| WirePlumber | Smart filters: a documented way for capture-sink streams to opt out of redirection, and retry when a filter's target device reappears | Both found in the prototype |
| WirePlumber | A desktop-safe "role → sink" policy for Notification, without the automotive role stack | Enables PR 14 cleanly |
| clap-validator | Kill the sandbox child when a test times out (orphans seen in §4.1) | Small issue with a reproducer |
| ALSA / kernel | None needed. `snd-seq-dummy ump=` already exists | — |

### Phase 4: standalone projects

| Project | Scope | Builds on |
|---|---|---|
| **linux-audio-registry** | The out-of-process scanner (`plugprobe` → a proper tool), the JSON schema, an XDG cache location, the LV2 runtime validator, an optional cross-format `product-id`. Proposed on linux-audio-dev as a shared convention | This prototype; carla-discovery's design |
| **CLAP host daemon** | Each plugin instance a sandboxed PipeWire client node. Instruments and MIDI effects as system nodes; GUIs via CLAP `gui`; presets via preset-discovery. The AUv3 equivalent | clack-host or clap-helpers; PipeWire `pw_filter` |
| **MIDI-CI service** | Discovery, profiles and property exchange for UMP endpoints, published as JSON and seq events | ni-midi2 / AM_MIDI2.0Lib |
| **PipeWire workgroup** (design only) | Let plugin worker threads join the driver's cycle (deadline, uclamp), the os_workgroup equivalent; pairs with CLAP `thread-pool` | module-rt, SCHED_DEADLINE |
| wiremix MIDI views | Community goodwill (DESIGN 3.5) | — |

---

## 6. Open questions

1. Should the registry and validation land in Omarchy at all, or start as the standalone project with Omarchy only reading its JSON? This research leans standalone-first; Omarchy gets PR 18 (device effects), which needs only LV2 URIs.
2. CLAP-first is a stance against Ardour's position. Does Manu want Omarchy to *say* "CLAP preferred", or only rank it in the registry?
3. PR 18's UI: device effects in the existing audio panel's device row, or in the Audio MIDI Setup panel?
4. Should the `ump=1` IAC amendment wait until it's tested with a real MIDI 2.0 device?

## 7. Sources

Apple (developer.apple.com/documentation unless noted):
- **HAL and aggregates:** `coreaudio/audioobjectaddpropertylistenerblock(_:_:_:_:)`, `coreaudio/audiohardwarecreateaggregatedevice(_:_:)`, `coreaudio/kaudiosubdevicedriftcompensationkey`, `coreaudio/kaudiodevicepropertyhogmode`, `coreaudio/audiodevicecreateioprocid(_:_:_:_:)`, `coreaudio/kaudiohardwarepropertydefaultsystemoutputdevice`.
- **Taps:** `coreaudio/audiohardwarecreateprocesstap(_:_:)`, `coreaudio/catapdescription`, `coreaudio/capturing-system-audio-with-core-audio-taps`.
- **Workgroups:** `audiotoolbox/understanding-audio-workgroups`, `audiotoolbox/workgroup-management`, `audiotoolbox/auaudiounit/osworkgroup`, WWDC20 10224.
- **Spatial audio:** `phase`, `phase/personalizing-spatial-audio-in-your-app`.
- **Engine and deprecations:** `avfaudio/avaudioengine`, iOS 13 release notes (AUGraph and Inter-App Audio deprecations).
- **CoreMIDI:** `coremidi/kmidipropertyuniqueid`, `coremidi/midinotificationmessageid`, `coremidi/midisourcecreatewithprotocol(_:_:_:_:)`, `coremidi/midinetworksession`, `coremidi/midi-bluetooth`, `coremidi/incorporating-midi-2-into-your-apps`, `coremidi/midicidiscoverymanager`, `coremidi/midiumpendpoint`, `coremidi/midiumpendpointmanager`, `coremidi/miditimestamp`.
- **Audio Units:** `audiotoolbox/audiocomponentdescription`, `audiotoolbox/migrating-your-audio-unit-host-to-the-auv3-api`, `audiotoolbox/auaudiounit/userpresets`, the archived Audio Unit Programming Guide.
- **Header comments** were read from the macOS 11.3 SDK headers (AudioHardwareBase.h, AudioHardware.h).
- **Audio MIDI Setup user guide** (support.apple.com/guide/audio-midi-setup): set-up-audio-devices, set-aggregate-device-settings, play-audio-through-multiple-devices-at-once, set-up-midi-devices, transfer-midi-information-between-apps, share-midi-information-over-a-network, set-up-bluetooth-midi-devices.

Linux:
- **Kernel MIDI 2.0:** docs.kernel.org/sound/designs/midi-2.0.html. snd-seq-dummy `ump` patch: patchwork.kernel.org/project/alsa-devel/patch/20240419101105.15571-1-tiwai@suse.de.
- **ALSA:** alsa-project.org wiki Changes v1.2.10, v1.2.12 and v1.2.13; the alsa-lib seq docs.
- **PipeWire docs** (docs.pipewire.org): page_module_filter_chain, page_midi, page_module_rtp_session, page_man_pipewire-props_7, page_man_pipewire-jack_conf_5, page_latency, page_module_combine_stream, page_module_rt, group__pw__thread, page_man_pw-cat_1. Also PipeWire NEWS, and gitlab.freedesktop.org/pipewire/pipewire issues #74 and #420.
- **WirePlumber:** the bluetooth configuration, features and settings pages. Local `/usr/share/wireplumber/scripts/lib/filter-utils.lua` and `wireplumber.conf` [live].
- **CLAP:** github.com/free-audio/clap (ChangeLog, `include/clap/entry.h`, `plugin-features.h`, `ext/`, `factory/`), free-audio/clap-wrapper, free-audio/clap-validator, free-audio/clap-juce-extensions, prokopyl/clack.
- **VST3:** steinbergmedia.github.io/vst3_dev_portal (Version 3.8.0 and 3.8.1, VST 3 Licensing, Plugin Locations, ModuleInfo-JSON), and the Steinberg press release of 2025-10-29.
- **LV2:** gitlab.com/lv2/lv2, github.com/lv2/lilv (NEWS, tools).
- **LADSPA:** ladspa.org.
- **Hosts and frameworks:** Qtractor ChangeLog, zrythm/zrythm, ardour.org/whatsnew, falkTX/Carla, bitwig.com user guide (plug-in hosting modes), DISTRHO/DPF, robbert-vdh/nih-plug, iPlug2, juce-framework/JUCE.
- **Linux registry history:** the linux-audio-dev archives (2009-06 paths RFC, 2018-10 plugin cache thread).
- **MIDI 2.0 libraries:** midi2-dev/ni-midi2, midi2-dev/AM_MIDI2.0Lib, midi2-dev/MIDI2.0Workbench.

Unverified, flagged in the text:
- whether drift handling is documented in PipeWire's primary docs;
- Arch BlueZ `--enable-midi`;
- the default MIDI format of PipeWire 1.6.x. This box shows MIDI 1.0 bytes, and the docs disagree between 1.4 and 1.7;
- the `aumi` four-character code;
- `auval` command-line syntax.
