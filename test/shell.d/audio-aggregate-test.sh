#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_home=$(mktemp -d)
test_bin=$(mktemp -d)
trap 'rm -rf "$test_home" "$test_bin"' EXIT

# The graph: two USB inputs (one without channel positions), a speaker and
# headphones. A combined device shows up once its unit is enabled, unless the
# scenario says it never does.
cat >"$test_bin/pw-dump" <<'STUB'
#!/bin/bash
node() { printf '{"type":"PipeWire:Interface:Node","info":{"props":%s}},' "$1"; }
printf '['
node '{"node.name":"alsa_input.usb-a","media.class":"Audio/Source","node.description":"Interface A","audio.channels":2,"audio.position":"[ FL, FR ]"}'
node '{"node.name":"alsa_input.usb-b","media.class":"Audio/Source","node.description":"Interface B","audio.channels":4}'
node '{"node.name":"alsa_output.speakers","media.class":"Audio/Sink","node.description":"Speakers","audio.channels":2,"audio.position":"[ FL, FR ]"}'
node '{"node.name":"bluez_output.headphones","media.class":"Audio/Sink","node.description":"Headphones","audio.channels":2,"audio.position":"[ FL, FR ]"}'
if [[ ! -f $TEST_DATA/never-appears ]]; then
  for unit in $(sed -n 's/^--user enable --now omarchy-audio-aggregate@\(.*\)\.service$/\1/p' "$TEST_DATA/systemctl" 2>/dev/null); do
    grep -q "disable --now omarchy-audio-aggregate@$unit.service" "$TEST_DATA/systemctl" && continue
    node "{\"node.name\":\"omarchy_aggregate_${unit//-/_}\",\"media.class\":\"Audio/Source\",\"audio.channels\":6}"
  done
fi
printf '{}]\n'
STUB
cat >"$test_bin/systemctl" <<'STUB'
#!/bin/bash
echo "$*" >>"$TEST_DATA/systemctl"
STUB
printf '#!/bin/bash\necho "$*" >>"$TEST_DATA/notifications"\n' >"$test_bin/omarchy-notification-send"
printf '#!/bin/bash\ncat "$TEST_DATA/picks"\n' >"$test_bin/omarchy-menu-select"
printf '#!/bin/bash\necho "Field Rig"\n' >"$test_bin/omarchy-menu-input"
chmod +x "$test_bin"/*

aggregate() {
  HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" TEST_DATA="$test_home/data" \
    OMARCHY_PATH="$ROOT" PATH="$test_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-audio-aggregate" "$@"
}

fresh() {
  rm -rf "$test_home/data" "$test_home/.config"
  mkdir -p "$test_home/data"
}

fragment() {
  cat "$test_home/.config/pipewire/omarchy-audio-aggregate-$1.conf.d/50-combine.conf"
}

# Channels stack in member order, and a member without positions gets AUX ones.
fresh
aggregate create "Studio Rig" alsa_input.usb-a alsa_input.usb-b >/dev/null || fail "an aggregate of two inputs is made"
conf=$(fragment studio-rig)
[[ $conf == *"combine.mode = source"* && $conf == *"audio.position = [ AUX0 AUX1 AUX2 AUX3 AUX4 AUX5 ]"* ]] ||
  fail "an aggregate input has every member's channels" "$conf"
[[ $conf == *'node.name = "alsa_input.usb-a"'*"combine.audio.position = [ AUX0 AUX1 ]"*"audio.position = [ FL FR ]"* ]] ||
  fail "the first member takes channels 1 and 2" "$conf"
[[ $conf == *'node.name = "alsa_input.usb-b"'*"combine.audio.position = [ AUX2 AUX3 AUX4 AUX5 ]"*"audio.position = [ AUX0 AUX1 AUX2 AUX3 ]"* ]] ||
  fail "the second member follows on channels 3 to 6" "$conf"
grep -qx -- '--user enable --now omarchy-audio-aggregate@studio-rig.service' "$test_home/data/systemctl" ||
  fail "the device runs in its own unit"
pass "an aggregate stacks its members' channels in order, each in its own PipeWire client"

fresh
aggregate create --mirror Everywhere alsa_output.speakers bluez_output.headphones >/dev/null || fail "a multi-output device is made"
conf=$(fragment everywhere)
[[ $conf == *"combine.mode = sink"* && $conf == *"stream.dont-remix = false"* && $(grep -c 'combine.audio.position = \[ FL FR \]' <<<"$conf") == 2 ]] ||
  fail "a multi-output device sends the same stereo pair to every output" "$conf"
pass "a multi-output device mirrors stereo onto every output"

fresh
if aggregate create Mixed alsa_input.usb-a alsa_output.speakers >/dev/null 2>&1; then
  fail "inputs and outputs are not combined"
fi
if aggregate create --mirror Mics alsa_input.usb-a alsa_input.usb-b >/dev/null 2>&1; then
  fail "inputs are not mirrored"
fi
if aggregate create 'Rig" }' alsa_input.usb-a alsa_input.usb-b >/dev/null 2>&1; then
  fail "a name that would break PipeWire's config is refused"
fi
[[ ! -e $test_home/.config/pipewire ]] || fail "a refused device writes nothing"
pass "inputs and outputs are not mixed, only outputs mirror, and names stay plain"

# A device PipeWire never lists is undone rather than left half made.
fresh
touch "$test_home/data/never-appears"
if aggregate create Ghost alsa_input.usb-a alsa_input.usb-b >/dev/null 2>&1; then
  fail "a device that never appears is reported as failed"
fi
[[ ! -e $test_home/.config/pipewire/omarchy-audio-aggregate-ghost.conf && ! -e $test_home/.config/systemd/user/omarchy-audio-aggregate@.service ]] ||
  fail "a device that never appears is removed again"
pass "a device that never appears in PipeWire is removed again"

# The menu's flow: members picked by their node names, then a name.
fresh
printf '["Interface A\\t2 ch · alsa_input.usb-a","Interface B\\t4 ch · alsa_input.usb-b"]\n' >"$test_home/data/picks"
aggregate create >/dev/null || fail "the menu's flow makes a device"
[[ $(fragment field-rig) == *'node.name = "alsa_input.usb-a"'*'node.name = "alsa_input.usb-b"'* ]] ||
  fail "the menu's picks become the members, in order"
pass "the menu's flow makes the device from the picked members"

aggregate remove "Field Rig" >/dev/null || fail "a combined device is removed by name"
[[ ! -e $test_home/.config/pipewire/omarchy-audio-aggregate-field-rig.conf && ! -e $test_home/.config/systemd/user/omarchy-audio-aggregate@.service ]] ||
  fail "removing the last device removes its files and the unit"
pass "removing the last combined device removes its files and the unit"
