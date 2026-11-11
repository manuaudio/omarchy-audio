#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_home=$(mktemp -d)
test_bin=$(mktemp -d)
trap 'rm -rf "$test_home" "$test_bin"' EXIT

# PipeWire's settings metadata is a key=value file the pw-metadata stub reads
# and writes; ps reports the data loop's scheduling class from another.
cat >"$test_bin/pw-metadata" <<'STUB'
#!/bin/bash
[[ -f $TEST_DATA/settings ]] || exit 1
if (( $# == 5 )); then
  sed -i "/^$4=/d" "$TEST_DATA/settings"
  echo "$4=$5" >>"$TEST_DATA/settings"
else
  while IFS='=' read -r key value; do
    echo "update: id:0 key:'$key' value:'$value' type:''"
  done <"$TEST_DATA/settings"
fi
STUB
cat >"$test_bin/systemctl" <<'STUB'
#!/bin/bash
echo "$*" >>"$TEST_DATA/systemctl"
case "$*" in
  *"show -p MainPID"*) echo 4242 ;;
  *is-enabled*) grep -q '^--user enable' "$TEST_DATA/systemctl" && ! grep -q '^--user disable' "$TEST_DATA/systemctl" ;;
esac
exit 0
STUB
cat >"$test_bin/ps" <<'STUB'
#!/bin/bash
cat "$TEST_DATA/cls"
STUB
printf '#!/bin/bash\necho "$*" >>"$TEST_DATA/notifications"\n' >"$test_bin/omarchy-notification-send"
printf '#!/bin/bash\necho "$*" >>"$TEST_DATA/shell"\n' >"$test_bin/omarchy-shell"
chmod +x "$test_bin"/*

pro() {
  HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" XDG_RUNTIME_DIR="$test_home/run" \
    TEST_DATA="$test_home/data" OMARCHY_PATH="$ROOT" PATH="$test_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-audio-pro" "$@"
}

setting() {
  sed -n "s/^$1=//p" "$test_home/data/settings"
}

# A freshly started PipeWire: nothing forced, its audio thread at normal priority.
fresh_pipewire() {
  rm -rf "$test_home/data" "$test_home/run"
  mkdir -p "$test_home/data" "$test_home/run"
  printf '%s\n' clock.rate=48000 clock.quantum=1024 clock.min-quantum=32 clock.max-quantum=2048 \
    clock.force-quantum=0 clock.force-rate=0 >"$test_home/data/settings"
  printf '%s\n' TS TS >"$test_home/data/cls"
}

fresh_pipewire
pro on >/dev/null 2>&1 || fail "pro audio turns on"
[[ $(setting clock.force-quantum) == 256 && $(setting clock.force-rate) == 48000 ]] ||
  fail "pro audio defaults to 256 frames without realtime and locks the current rate" "$(cat "$test_home/data/settings")"
grep -q '^--user enable omarchy-audio-pro.service' "$test_home/data/systemctl" ||
  fail "pro audio enables the unit that sets it again when PipeWire restarts"
[[ -f $test_home/.local/state/omarchy/toggles/audio-pro && -f $test_home/.config/systemd/user/omarchy-audio-pro.service ]] ||
  fail "pro audio saves its toggle and installs its unit"
pass "pro audio defaults to 256 frames without realtime, locks the rate and persists"

fresh_pipewire
rm -f "$test_home/.local/state/omarchy/toggles/audio-pro"
printf '%s\n' RR TS >"$test_home/data/cls"
pro on >/dev/null 2>&1
[[ $(setting clock.force-quantum) == 128 ]] || fail "pro audio defaults to 128 frames once PipeWire runs realtime"
pass "pro audio defaults to 128 frames once PipeWire runs realtime"

# Each choice changes only itself, and is what a restarted PipeWire gets back.
pro on --buffer 64 >/dev/null 2>&1
pro on --rate 96000 >/dev/null 2>&1
[[ $(setting clock.force-quantum) == 64 && $(setting clock.force-rate) == 96000 ]] ||
  fail "a rate change keeps the chosen buffer" "$(cat "$test_home/data/settings")"
fresh_pipewire
pro on >/dev/null 2>&1
[[ $(setting clock.force-quantum) == 64 && $(setting clock.force-rate) == 96000 ]] ||
  fail "a restarted PipeWire gets the saved buffer and rate back" "$(cat "$test_home/data/settings")"
pass "buffer and rate choices are kept apart and restored after a PipeWire restart"

# Turning off clears only what pro audio forced, never a buffer forced since.
sed -i 's/^clock.force-quantum=.*/clock.force-quantum=512/' "$test_home/data/settings"
pro off >/dev/null 2>&1 || fail "pro audio turns off"
[[ $(setting clock.force-quantum) == 512 && $(setting clock.force-rate) == 0 ]] ||
  fail "off leaves a buffer another program forced" "$(cat "$test_home/data/settings")"
[[ ! -e $test_home/.local/state/omarchy/toggles/audio-pro && ! -e $test_home/.config/systemd/user/omarchy-audio-pro.service ]] ||
  fail "off forgets the choice and removes the unit"
pass "pro audio off clears only what it forced and forgets the choice"

fresh_pipewire
if pro on --buffer 100 >/dev/null 2>&1; then
  fail "a buffer that is not a power of two is refused"
fi
[[ $(setting clock.force-quantum) == 0 && ! -e $test_home/.local/state/omarchy/toggles/audio-pro ]] ||
  fail "a refused buffer changes nothing"
pass "pro audio refuses a buffer that is not a power of two"

pro on --buffer 64 >/dev/null 2>&1
[[ $(pro status --json) == '{"enabled":true,"buffer":64,"rate":48000,"realtime":false}' ]] ||
  fail "status --json reports the live buffer and rate" "$(pro status --json)"
pass "pro audio status --json reports the live buffer and rate"

# With PipeWire down there is nothing to clear, but off still forgets the choice.
rm -f "$test_home/data/settings"
pro off >/dev/null 2>&1 || fail "pro audio turns off while PipeWire is down"
[[ ! -e $test_home/.local/state/omarchy/toggles/audio-pro && ! -e $test_home/.config/systemd/user/omarchy-audio-pro.service ]] ||
  fail "off with PipeWire down forgets the choice and removes the unit"
pass "pro audio turns off while PipeWire is down"
