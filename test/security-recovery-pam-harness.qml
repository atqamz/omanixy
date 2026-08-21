import QtQuick
import Quickshell
import Quickshell.Services.Pam

ShellRoot {
  id: root

  property string mode: Quickshell.env("HARNESS_MODE") || "single"
  property string pamConfig: Quickshell.env("HARNESS_PAM_CONFIG") || "omarchy-lock-password"
  property string pamUser: Quickshell.env("HARNESS_PAM_USER") || ""
  property string password: Quickshell.env("HARNESS_PASSWORD") || ""
  property string wrongPassword: Quickshell.env("HARNESS_WRONG_PASSWORD") || ""
  property int repeatCount: parseInt(Quickshell.env("HARNESS_REPEAT_COUNT") || "20", 10)
  property int wrongAttemptsDone: 0
  property bool done: false

  function finish(tag) {
    if (root.done) return
    root.done = true
    console.log("HARNESS_DONE " + tag)
    Qt.quit()
  }

  function driveRepeat() {
    console.log("HARNESS_EVENT attempt " + (root.wrongAttemptsDone + 1) + "/" + (root.repeatCount + 1))
    if (!pam.start()) {
      console.log("HARNESS_EVENT start-failed")
      root.finish("start-failed")
    }
  }

  PamContext {
    id: pam
    config: root.pamConfig
    user: root.pamUser

    onPamMessage: {
      console.log("HARNESS_EVENT message " + JSON.stringify(pam.message) +
        " responseRequired=" + pam.responseRequired + " isError=" + pam.messageIsError)
      if (!pam.responseRequired) return
      if (root.mode === "cancel") {
        console.log("HARNESS_EVENT abort")
        pam.abort()
        return
      }
      var reply = (root.mode === "repeat" && root.wrongAttemptsDone < root.repeatCount)
        ? root.wrongPassword
        : root.password
      pam.respond(reply)
    }

    onCompleted: function(result) {
      var resultName = PamResult.toString(result)
      console.log("HARNESS_EVENT completed " + resultName)

      if (root.mode === "repeat") {
        if (root.wrongAttemptsDone < root.repeatCount) {
          root.wrongAttemptsDone += 1
          if (result === PamResult.Success) {
            root.finish("repeat-unexpected-success-at-" + root.wrongAttemptsDone)
            return
          }
          Qt.callLater(root.driveRepeat)
          return
        }
        root.finish("repeat-final:" + resultName)
        return
      }

      root.finish("completed:" + resultName)
    }

    onError: function(error) {
      var errorName = PamError.toString(error)
      console.log("HARNESS_EVENT error " + errorName)
      root.finish("error:" + errorName)
    }

    onActiveChanged: {
      console.log("HARNESS_EVENT active=" + pam.active)
      if (root.mode === "cancel" && !pam.active) {
        root.finish("aborted-active-false")
      }
    }
  }

  property int watchdogMs: parseInt(Quickshell.env("HARNESS_WATCHDOG_MS") || "25000", 10)

  Timer {
    id: watchdog
    interval: root.watchdogMs
    running: true
    repeat: false
    onTriggered: root.finish("timeout")
  }

  Component.onCompleted: {
    console.log("HARNESS_EVENT begin mode=" + root.mode + " config=" + root.pamConfig + " user=" + root.pamUser)
    if (!pam.start()) {
      console.log("HARNESS_EVENT start-failed")
      // Qt.quit() called synchronously here, before the event loop has
      // actually started spinning, is dropped ("no receivers connected to
      // handle it") and the process then hangs until an external timeout
      // kills it. Defer to the next turn of the event loop, by which time
      // it is guaranteed to be running.
      Qt.callLater(function() { root.finish("start-failed") })
    }
  }
}
