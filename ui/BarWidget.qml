import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Topbar widget: proxy status indicator. Clicking it summons the Rayarchy
// panel window through the shell's toggle IPC (same path as a keybind or
// launcher entry). The widget polls the daemon status over the same socket
// the panel uses.
BarWidget {
  id: root
  moduleName: "com.drunkleen.rayarchy"

  property bool connected: false
  property bool connecting: false
  property string profileName: ""
  property string tooltip: ""

  readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/rayarchy/rayarchy.sock"

  // Bar widgets are sized by their content: the root must advertise an
  // implicit size or the slot collapses to 0x0 and nothing renders.
  implicitWidth: Math.max(shieldButton.implicitWidth + Style.space(4), Style.space(30))
  implicitHeight: shieldButton.implicitHeight

  Component.onCompleted: {
    rpc.setSocketPath(root.socketPath)
    pollTimer.start()
  }

  Rpc {
    id: rpc
  }

  Timer {
    id: pollTimer
    interval: 3000
    repeat: true
    onTriggered: {
      if (!rpc.ready) { rpc.setSocketPath(root.socketPath); return }
      rpc.call("system.status", {}, function (status) {
        root.connected = status.connected === true
        root.connecting = status.connecting === true
        root.profileName = status.profileName || ""
        root.tooltip = "Rayarchy v" + (status.version || "?")
          + (status.localPort ? " · [mixed:" + status.localPort + "]" : "")
          + (root.profileName ? " · " + root.profileName : "")
      })
    }
  }

  WidgetButton {
    id: shieldButton
    bar: root.bar
    text: "⛨" + (root.profileName !== "" ? " " + root.profileName : "")
    foreground: root.connected ? Color.accent : (root.connecting ? Color.urgent : Util.alpha(Color.foreground, 0.65))
    activeColor: Color.accent
    active: root.connected
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    fontSize: Style.font.body
    keepSpace: true
    tooltipText: root.tooltip + " — click to open"
    onPressed: function () {
      if (root.bar) root.bar.run("omarchy-shell shell toggle com.drunkleen.rayarchy '{}'")
      else Quickshell.execDetached("omarchy-shell shell toggle com.drunkleen.rayarchy '{}'")
    }
  }
}