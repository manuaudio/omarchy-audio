#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_home=$(mktemp -d)
test_bin=$(mktemp -d)
trap 'rm -rf "$test_home" "$test_bin"' EXIT

# A sequencer with a MIDI 2.0 keyboard sending to one synth app and to
# PipeWire's bridge, a second synth, the kernel's Midi Through bus, and the
# plumbing the list leaves out.
cat >"$test_home/clients" <<'SEQ'
Client info
  cur  clients : 6
Client   0 : "System" [Kernel Legacy]
  Port   0 : "Timer" (Rwe-) [In/Out]
    Connecting To: 142:0
Client  14 : "Midi Through" [Kernel Legacy]
  Port   0 : "Midi Through Port-0" (RWe-) [In/Out]
Client  24 : "Keystation" [Kernel UMP MIDI2]
  Port   0 : "Keystation MIDI 1" (RWeX) [In/Out]
    Connecting To: 128:0[real:0], 142:0
Client 128 : "Surge XT" [User Legacy]
  Port   0 : "input" (-We-) [Out]
    Connected From: 24:0[real:0]
Client 129 : "Vital" [User Legacy]
  Port   0 : "input" (-We-) [Out]
Client 142 : "PipeWire-System" [User Legacy]
  Port   0 : "input" (rwe-) [In/Out]
SEQ

cat >"$test_bin/aconnect" <<'STUB'
#!/bin/bash
echo "$*" >>"$TEST_DATA/aconnect"
STUB
cat >"$test_bin/omarchy-menu-select" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_DATA/menu"
printf '["Vital\\tinput · 129:0"]\n'
STUB
printf '#!/bin/bash\nexit 0\n' >"$test_bin/omarchy-shell"
chmod +x "$test_bin"/*

midi() {
  HOME="$test_home" TEST_DATA="$test_home" OMARCHY_SEQ_CLIENTS_PATH="$test_home/clients" \
    OMARCHY_PATH="$ROOT" PATH="$test_bin:$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-audio-midi" "$@"
}

json=$(midi list --json)
[[ $(jq -c '.[] | select(.address == "24:0")' <<<"$json") == '{"address":"24:0","client":"Keystation","port":"Keystation MIDI 1","kind":"hardware","protocol":"MIDI 2.0","direction":"both","sendsTo":["128:0"]}' ]] ||
  fail "a MIDI 2.0 keyboard lists as hardware with its connection, not the bridge's" "$json"
[[ $(jq -r '.[] | select(.address == "128:0") | .direction' <<<"$json") == "destination" ]] ||
  fail "a port others can only write to is a destination" "$json"
[[ $(jq -r 'map(.client) | join(",")' <<<"$json") == "Midi Through,Keystation,Surge XT,Vital" ]] ||
  fail "the sequencer's own client and PipeWire's bridge are left out" "$json"
pass "midi lists each port's kind, protocol, direction and connections"

# Picking from the menu makes the picks the source's connections, no more.
: >"$test_home/aconnect"
midi connect 24:0 || fail "the menu's flow connects a source"
grep -qx -- '--selected' "$test_home/menu" && grep -qx $'Surge XT\tinput · 128:0' "$test_home/menu" ||
  fail "the menu opens with the source's connections ticked" "$(cat "$test_home/menu")"
! grep -q 'Keystation MIDI 1 · 24:0' "$test_home/menu" || fail "a source is not offered as its own destination"
[[ $(cat "$test_home/aconnect") == $'-d 24:0 128:0\n24:0 129:0' ]] ||
  fail "unticked destinations are disconnected and ticked ones connected, and the bridge is left alone" "$(cat "$test_home/aconnect")"
pass "midi connect makes the destinations picked in the menu the source's connections"
