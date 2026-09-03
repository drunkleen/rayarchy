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
        root.tooltip = (status.localPort ? "[mixed:" + status.localPort + "] " : "") + (root.profileName || "")
      })
    }
  }

  WidgetButton {
    anchors.fill: parent
    bar: root.bar
    text: "⛨" + (root.profileName !== "" ? " " + root.profileName : "")
    foreground: root.connected ? Color.accent : (root.connecting ? Color.urgent : Util.alpha(Color.foreground, 0.55))
    activeColor: Color.accent
    active: root.connected
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    fontSize: Style.font.body
    tooltipText: root.connected
      ? root.tooltip + " — click to open"
      : "Rayarchy — click to open"
    onPressed: function () {
      if (root.bar) root.bar.run("omarchy-shell shell toggle com.drunkleen.rayarchy '{}'")
      else Quickshell.execDetached("omarchy-shell shell toggle com.drunkleen.rayarchy '{}'")
    }
  }
}