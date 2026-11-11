#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_compositor "audio panel runtime test"
require_command quickshell
require_command node

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
stage="$scratch/stage"

# A disposable shell that loads the real audio Panel.qml and Model.js. The
# panel reads the real PipeWire graph but changes nothing in it: the fixture
# only drives the pro audio section, and every command the panel can run is a
# stub here.
mkdir -p "$stage/audio" "$stage/bin" "$stage/home"
ln -s "$ROOT/shell/Ui" "$stage/Ui"
ln -s "$ROOT/shell/Commons" "$stage/Commons"
cp "$SHELL_TEST_DIR/fixtures/audio-panel/pro-audio.qml" "$stage/shell.qml"
cp "$ROOT/shell/plugins/panels/audio/Model.js" "$stage/audio/Model.js"
node - "$ROOT" "$stage" <<'JS'
const fs = require('fs')
const [root, stage] = process.argv.slice(2)
let source = fs.readFileSync(`${root}/shell/plugins/panels/audio/Panel.qml`, 'utf8')
// Expose the lazily built content and a private id in the disposable copy only.
source = source.replace('  id: root\n', `  id: root
  function testEnsureContent() { return panel.ensureContent() }
  readonly property Item testKeys: panel.loadedContent
  readonly property bool testProBusy: proActionProc.running
`)
fs.writeFileSync(`${stage}/audio/Panel.qml`, source)
JS

# omarchy-audio-pro as a file of key=value state, slow enough that a second
# click lands while the first change still runs.
cat >"$stage/bin/omarchy-audio-pro" <<'SH'
#!/bin/bash
state="$AUDIO_TEST_PRO_STATE"
[[ -f $state ]] || printf 'enabled=false\nbuffer=1024\nrate=48000\n' >"$state"
get() { sed -n "s/^$1=//p" "$state"; }
put() { sed -i "s/^$1=.*/$1=$2/" "$state"; }
if [[ $1 == "status" ]]; then
  printf '{"enabled":%s,"buffer":%s,"rate":%s,"realtime":false}\n' "$(get enabled)" "$(get buffer)" "$(get rate)"
  exit 0
fi
echo "$*" >>"$AUDIO_TEST_PRO_LOG"
sleep 0.3
case "$1" in
  on)
    [[ $(get enabled) == "true" ]] || put buffer 256
    put enabled true
    [[ ${2:-} == "--buffer" ]] && put buffer "$3"
    [[ ${2:-} == "--rate" ]] && put rate "$3"
    ;;
  off) printf 'enabled=false\nbuffer=1024\nrate=48000\n' >"$state" ;;
esac
SH
printf '#!/bin/bash\nexit 0\n' >"$stage/bin/noop"
chmod +x "$stage/bin/omarchy-audio-pro" "$stage/bin/noop"
for command in omarchy-audio-output-sink omarchy-audio-sink-availability omarchy-audio-output-set-default omarchy-audio-input-set-default; do
  ln -s noop "$stage/bin/$command"
done

: >"$scratch/pro.log"
output=$(HOME="$stage/home" OMARCHY_PATH="$ROOT" PATH="$stage/bin:$PATH" \
  AUDIO_TEST_PRO_STATE="$scratch/pro-state" AUDIO_TEST_PRO_LOG="$scratch/pro.log" \
  timeout 40 quickshell -p "$stage" --no-color 2>&1) || fail "audio pro fixture exits cleanly" "$output"
[[ $output == *"RESULT pass"* ]] || fail "audio pro runtime assertions pass" "$output"
if rg -q 'RESULT fail|ReferenceError|TypeError|Error:|Unable to assign|Binding loop' <<<"$output"; then
  fail "audio pro fixture has no QML errors" "$output"
fi
pass "audio pro audio switch, buffer and rate pills, keyboard navigation and change queue work in QML"
