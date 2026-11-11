import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "audio" as Audio

// Drives the real audio panel's pro audio section through its key catcher, the
// way the keys reach it. omarchy-audio-pro is a stub that keeps its state in a
// file and logs every call; nothing here changes the real audio graph. The
// panel is never opened, so nothing maps on the desktop running the test.
ShellRoot {
  id: test
  property bool failed: false
  property var keys: null
  property var steps: []

  function check(ok, message) {
    if (!ok) {
      failed = true
      console.log("RESULT fail " + message)
    }
  }

  Item {
    Audio.Panel {
      id: panel
      bar: QtObject {
        property color foreground: Commons.Color.foreground
        property color barForeground: Commons.Color.foreground
        property color background: Commons.Color.background
        property color urgent: Commons.Color.urgent
        property string fontFamily: Style.font.family
        property string position: "top"
        property int barSize: 24
        property bool vertical: false
        property bool foregroundAnimationEnabled: false
        property var activePopout: null
        property var shell: null
        function requestPopout(owner) { activePopout = owner }
        function releasePopout(owner) { activePopout = null }
        function registerClickTarget(target) {}
        function unregisterClickTarget(target) {}
        function hideTooltip(target) {}
        function showTooltip(target, text) {}
      }
    }
  }

  // Runs the steps in order, each once its condition holds or after 5 s.
  function run(list) {
    steps = list
    next()
  }

  function next() {
    if (failed || steps.length === 0) {
      console.log(failed ? "RESULT fail" : "RESULT pass")
      Qt.quit()
      return
    }
    var step = steps[0]
    steps = steps.slice(1)
    var started = Date.now()
    var poll = function() {
      if (step.until()) {
        step.then()
        Qt.callLater(next)
      } else if (Date.now() - started > 5000) {
        check(false, "timed out waiting: " + step.name)
        Qt.callLater(next)
      } else {
        waiter.callback = poll
        waiter.restart()
      }
    }
    poll()
  }

  Timer { id: waiter; property var callback: null; interval: 50; onTriggered: callback() }

  FileView {
    id: proLog
    path: Quickshell.env("AUDIO_TEST_PRO_LOG")
    blockLoading: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  function log() {
    return String(proLog.text() || "").trim().split("\n")
  }

  Timer {
    interval: 250
    running: true
    onTriggered: {
      test.check(panel.testEnsureContent() !== null, "panel content builds on demand")
      test.keys = panel.testKeys
      panel.readProStatus()
      test.run([
        { name: "status read", until: function() { return panel.proStatus !== null }, then: function() {
          test.check(panel.visibleSections[panel.visibleSections.length - 1] === "pro", "pro audio is the last section")
          test.check(!panel.proOn && panel.sectionCount("pro") === 0, "pro audio off shows no pills")
          panel.cursorActive = true
          panel.focusSection = "pro"
          panel.selectedIndex = -1
          test.keys.activateRequested(Qt.NoModifier)
        } },
        { name: "switched on", until: function() { return panel.proOn && !panel.testProBusy }, then: function() {
          test.check(test.log()[0] === "on", "Enter on the switch runs pro audio on")
          test.check(panel.sectionCount("pro") === 2, "pro audio on shows the buffer and rate rows")
          test.keys.moveRequested(0, 1)
          test.check(panel.selectedIndex === 0 && panel.proBufferIndex === 2, "down reaches the buffer pills, parked on the buffer in force")
          test.keys.moveRequested(-1, 0)
          test.check(panel.proBufferIndex === 1, "h walks the buffer pills")
          test.keys.activateRequested(Qt.NoModifier)
        } },
        { name: "buffer 128", until: function() { return panel.proStatus.buffer === 128 }, then: function() {
          test.check(test.log().pop() === "on --buffer 128", "Enter on a buffer pill sets that buffer: " + test.log())
          test.keys.moveRequested(0, 1)
          test.keys.moveRequested(1, 0)
          test.check(panel.selectedIndex === 1 && panel.proRateIndex === 2, "the rate row walks from the rate in force")
          test.keys.activateRequested(Qt.NoModifier)
        } },
        { name: "rate 88200", until: function() { return panel.proStatus.rate === 88200 }, then: function() {
          test.check(test.log().pop() === "on --rate 88200", "Enter on a rate pill sets that rate")
          test.keys.moveRequested(0, 1)
          test.check(panel.focusSection === "pro" && panel.selectedIndex === 1, "down stops at the last row")
          // Clicks while a change runs: the first runs, only the latest waits.
          panel.setProBuffer(64)
          panel.setProBuffer(128)
          panel.setProBuffer(1024)
        } },
        { name: "queue drained", until: function() { return panel.proStatus.buffer === 1024 && !panel.testProBusy }, then: function() {
          var calls = test.log().slice(-2)
          test.check(calls[0] === "on --buffer 64" && calls[1] === "on --buffer 1024", "a change asked for mid-run waits, and only the latest: " + calls)
          panel.setPro(false)
        } },
        { name: "switched off", until: function() { return panel.proStatus && !panel.proOn }, then: function() {
          test.check(panel.focusSection === "pro" && panel.selectedIndex === -1, "switching off moves the cursor from the vanished pills to the switch")
          test.keys.moveRequested(0, -1)
          test.check(panel.focusSection !== "pro", "up from the switch leaves for the section above")
        } }
      ])
    }
  }

  Timer { interval: 30000; running: true; onTriggered: { test.check(false, "fixture timed out"); Qt.quit() } }
}
