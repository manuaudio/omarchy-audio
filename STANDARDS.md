# Omarchy's standards, as this work follows them

Read from `omacom/omarchy` `quattro` at `e485c6224` (2026-11-11), its `AGENTS.md`, `agents/skills/*.md`, `docs/*.md`, the PR template, the CI workflows, and recent merged PRs. Each line names where the rule comes from. Where this repo makes a choice the sources do not settle, it says so.

## Contribution shape

| Convention | Source |
|---|---|
| One problem per PR; lead with what changes and why, in plain terms | `.github/pull_request_template.md` |
| PR body sections: **What changes**, **Verification** (tests run and manual checks with what was seen, plus what could not be checked; "tests pass" alone is not enough), **Screenshots** (before/after, or one line `No visible change: <why>`) | `.github/pull_request_template.md`, `visual-evidence.yml` |
| Captures are uploaded to the PR, never committed | `agents/skills/visual-verification.md` |
| Short, measured descriptions: the defect or gap first, numbers where there are any, a table only when it carries measurements | merged #18292, #17226, #15033, #12958, #11318, #16824 |
| AI-assisted PRs end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; there is no CONTRIBUTING file and no AI ban | merged #18292, #17226, #15033, #11318 |
| Commits are atomic and their messages succinct, describing the change ("Show …", "Keep …", "Resolve …") | `AGENTS.md` › Git; `git log` on `quattro` |
| Changes that need a maintainer's yes (new toggles, niche config) are framed as a measured defect or obvious parity, or wait for the yes | `DESIGN.md` §2, from maintainer behaviour on #13838, #13832 |
| Visible changes are verified in the running UI, not only by tests | `AGENTS.md` › Tests; `agents/skills/visual-verification.md` |

## `bin/` commands

| Convention | Source |
|---|---|
| `#!/bin/bash`, never `/usr/bin/env bash` | `AGENTS.md` › Style |
| Two-space indent, no tabs, final newline | `AGENTS.md` › Style; `.editorconfig` |
| `[[ ]]` for strings and files, unquoted variables, quoted literals (`[[ $x == "on" ]]`); `(( ))` for numbers | `AGENTS.md` › Style |
| A full `if`/`else` for two-path flow rather than `exit` in one branch | `AGENTS.md` › Style |
| Name `omarchy-<group>-<name>`; the group must be in `GROUP_DESCRIPTIONS` (`audio` is) | `AGENTS.md` › Command Naming; `bin/omarchy` |
| `# omarchy:summary=` always; `# omarchy:args=` for usage; `# omarchy:examples=` only where args need explaining; `hidden`, `requires-sudo` where true; metadata in the first 80 lines | `agents/skills/command-metadata.md`; enforced by `test/cli` |
| A comment block after the metadata says why the command exists and what it deliberately does not do | `bin/omarchy-audio-tuning`, `bin/omarchy-realtime-repair` |
| `set -uo pipefail` or `set -euo pipefail`; `pipefail` must not turn a `grep -q` SIGPIPE into a false negative | `bin/omarchy-audio-tuning`; #6614 |
| Use `$OMARCHY_PATH`; never derive it from `HOME` or re-export a default | `AGENTS.md` › Runtime Environment |
| Use the helpers: `omarchy-notification-send` (never `notify-send`), `omarchy-cmd-present/missing` only for optional tools, `omarchy-pkg-add`; default-package commands (`pw-dump`, `jq`, `aconnect`) are called directly | `AGENTS.md` › Helper Commands |
| User-facing strings in notifications and prompts come from `default/i18n/en/cli.json` through `omarchy-i18n key args…`; terminal output, usage and diagnostics stay English | `docs/i18n.md`; `scripts/i18n-sync.py` (`BIN_NOTIFY`, `BIN_PROMPT`) |
| Desktop prompts go through `omarchy-menu-select` (single or `--multiple`) and `omarchy-menu-input`, with an i18n prompt; `gum` is for flows that run in a terminal | `bin/omarchy-webapp-remove`, `bin/omarchy-capture-screenrecording-with-webcam`, `bin/omarchy-menu-select` |
| Toggle feedback is a notification (`omarchy-notification-send -g <glyph> "$(omarchy-i18n …)"`) | `bin/omarchy-toggle-screensaver`, `bin/omarchy-toggle-crash-capture` |
| A command that changes state the shell shows pushes `omarchy-shell -q <target> refresh` afterwards | `agents/skills/shell-dev.md` › Keeping state current |
| Persistent on/off state is a flag under `~/.local/state/omarchy/toggles/`, read with `omarchy-toggle-enabled` | `bin/omarchy-toggle`, `bin/omarchy-toggle-enabled`, `manual/13-toggles-idle-screensaver.md` |
| Audio prior art: never restart PipeWire or pipewire-pulse to apply something; host extra graph pieces as their own PipeWire client in a user unit copied to `~/.config/systemd/user`, `PartOf=pipewire.service`; verify the result and roll back on failure | `docs/audio-tuning.md`; `bin/omarchy-audio-tuning`; `default/systemd/user/omarchy-speaker-tuning.service` |
| Realtime is detected the way the repair does it: `pipewire.service`'s `MainPID`, `ps -L -o cls=` matching `RR` or `FF` | `bin/omarchy-realtime-repair` |
| No `sudo` in user-space features; privileged steps follow the omarchy skill's escalation rules | `AGENTS.md` › Privileged Commands |

## The menu

| Convention | Source |
|---|---|
| Rows are data in `default/omarchy/omarchy-menu.jsonc`; every label mirrored in `default/i18n/en/menu.json` in the same order | `docs/menu.md`; `docs/i18n.md`; `i18n-test.sh` |
| Toggles are an on/off pair of rows with `when` guards (`trigger.toggle.<x>-on` / `-off`), guarded by cheap checks such as `omarchy-toggle-enabled` | `default/omarchy/omarchy-menu.jsonc`; `menu-guard-budget-test.sh` |
| Add/remove pairs under Setup, the remove row guarded on there being something to remove | `setup.plugin.*` rows |
| No `aliases` on new rows | `AGENTS.md` › Menu |

## Shell panels (QML)

| Convention | Source |
|---|---|
| First-party plugins live in `shell/plugins/<category>/<name>/` with `manifest.json`, an entry QML `Item` and a pure `Model.js` with a guarded `module.exports` | `agents/skills/shell-dev.md`; `docs/testing.md` |
| Bar popups extend `Ui/Panel.qml`, build their card as `KeyboardPanel { content: PanelKeyCatcher { … } }` so it is built on first open; ids inside are exposed with `property alias` and read through `panel.loadedContent` | `agents/skills/shell-dev.md` › Plugin contract |
| One cursor model per panel: `focusSection` + index, shared by keyboard and mouse (hover moves the cursor; visuals come from `hasCursor`/`current` through `CursorSurface`, never `containsMouse`) | `shell/plugins/panels/audio/Panel.qml`, `network/Panel.qml`, `Ui/CursorSurface.qml` |
| Keys come from `PanelKeyCatcher`: j/k and arrows move, h/l adjust or move along a row, Enter/Space activate, x/Delete remove, Esc closes, Tab switches panels; Left/Right go through the mirrored reading order | `Ui/PanelKeyCatcher.qml`; `docs/i18n.md` › direction |
| A switch on a section's header line with pills under it, collapsing when off, is the network panel's band pattern (`ToggleSwitch` sized off the header label, `Button` pills with `selected`/`active`/`hasCursor`) | `shell/plugins/panels/network/Panel.qml` (band section) |
| Shared components only: `PanelSectionHeader`, `PanelSeparator`, `ToggleSwitch`, `Button`, `PanelActionButton`, `PanelToolTip`, `CursorSurface` | `shell/Ui/` |
| Palette via `import qs.Commons as Commons` and `Commons.Color.*`; colours derived from `bar.foreground` and `Style.*Fill*` tokens, sizes from `Style.space()`/`Style.font.*`/`Style.spacing.*` | `agents/skills/shell-dev.md` › Palette; `Ui/*.qml` |
| Every duration through `Style.duration(ms)`; ease-out, under 300 ms, nothing bounces | `agents/skills/motion.md`; `motion-test.sh` |
| Never poll for state that has a change signal; read on open, take pushes from the commands that change it; a closed panel runs nothing | `agents/skills/shell-dev.md`; `AGENTS.md` › Background Work; `shell-idle-spawn-test.sh` |
| Repeater rows are primitive snapshots, never `PwNode`s (a dangling node segfaults the shell) | `shell/plugins/panels/audio/Model.js` (`rowSnapshot`); #c9faea7c5 |
| A panel adding IPC methods answers its own `ShellIpc` target with `manageIpc: false`; targets are named for the plugin | `Ui/Panel.qml`; `agents/skills/shell-dev.md` › IPC |

## i18n

| Convention | Source |
|---|---|
| Shell strings in `default/i18n/en/shell.json`, read with literal keys `Commons.I18n.t("…")` inside bindings; `%1` placeholders; plurals via `I18n.tn` | `docs/i18n.md` |
| Plain-JS models take an optional `tr(key, english)` and Node tests assert the English | `docs/i18n.md`; `audio/Model.js` |
| Numbers through `I18n.formatNumber`, never `toFixed` | `docs/i18n.md` › Plurals, numbers |
| Every `Text` declares `textFormat` | `qml-text-format-test.sh` |
| Section headers are upper-case in the catalog ("OUTPUT") | `default/i18n/en/shell.json` |
| PRs add English only; the sync workflow translates | `docs/i18n.md` › Keeping translations in sync |
| Every catalog key is referenced and every referenced key exists | `i18n-test.sh` |

## Tests

| Convention | Source |
|---|---|
| Area tests in `test/shell.d/<area>-test.sh`, sourcing `base-test.sh`; extend the area's file rather than adding one | `AGENTS.md` › Tests; `docs/testing.md` |
| `pass`/`fail`/`skip`, first failure ends the file; `run_node_test` for `Model.js` | `docs/testing.md` |
| Stub the world, run the real code: scratch `bin/` stubs that log, fake `HOME`, `OMARCHY_PATH="$ROOT"` | `docs/testing.md` › Conventions |
| Only real logic gets a test, and it must fail without the change; no tests for menu rows, strings, config values or migrations; no change-detectors | `AGENTS.md` › When to add a test |
| Panel runtime tests stage the real `Panel.qml` with mocks and drive its key catcher, gated by `require_compositor` | `test/shell.d/network-panel-runtime-test.sh` |
| Run the files for the area, write output to a log and read it from there; run a failing untouched file on the base branch before blaming the change | `AGENTS.md` › Tests |
| Upstream checks this work must keep green: `test/cli` (metadata lint), `i18n-test.sh` (structural, as CI runs it), `scripts/i18n-sync.py extract-scan --check`, `qml-text-format-test.sh`, `plugin-manifest-scan-test.sh`, `plugin-registry-contract-test.sh`, `motion-test.sh`, `keyboard-panel-lazy-test.sh`, `menu-test.sh`, `audio-test.sh` | `.github/workflows/test.yml`, `i18n-check.yml` |

## Docs and manual

| Convention | Source |
|---|---|
| `manual/` is for users, `docs/` for how the code is shaped, `agents/skills/` for procedure | `AGENTS.md` › Documentation Layout |
| Full lines in markdown, no hard wrapping | `AGENTS.md` › Style |
| The manual's toggles chapter lists every toggle with its hotkey and command; the top-bar chapter says what each panel does | `manual/13-toggles-idle-screensaver.md`, `manual/05-the-top-bar.md` |

## Migrations and defaults

| Convention | Source |
|---|---|
| Migrations only for one-time repairs of existing installs; `0644`, no shebang, an `echo` first, idempotent, never restart the shell; no tests | `agents/skills/migrations.md` |
| None of this work needs one: every file it writes is created on first use by the command (as `omarchy-audio-tuning` does), so existing installs need no repair | this repo's choice |
| Shipped user units live in `default/systemd/user/`; units a command enables on demand are copied to `~/.config/systemd/user/` by it | `default/systemd/user/`; `bin/omarchy-audio-tuning` |
