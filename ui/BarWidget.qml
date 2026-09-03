import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import qs.Commons

// Topbar widget + compact popup panel. Left-click toggles the popup; the
// icon reflects connection state (accent when connected, shows the profile
// name). The popup is a KeyboardPanel anchored to the icon hosting App.qml.
Panel {
  id: root
  moduleName: "com.drunkleen.rayarchy"

  // The App tells us to swallow close requests while a form/sheet is open so
  // a stray outside click cannot wipe unsaved input.
  property bool suppressClose: false

  property bool connected: false
  property string profileName: ""
  property string appVersion: ""

  readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/rayarchy/rayarchy.sock"

  implicitWidth: button.implicitWidth + Style.space(4)
  implicitHeight: button.implicitHeight

  Rpc {
    id: rpc
  }

  Timer {
    interval: 3000
    repeat: true
    running: true
    onTriggered: {
      if (!rpc.ready) { rpc.setSocketPath(root.socketPath); return }
      rpc.call("system.status", {}, function (status) {
        root.connected = status.connected === true
        root.profileName = status.profileName || ""
        if (status.version) root.appVersion = status.version
      })
    }
  }

  Component.onCompleted: rpc.setSocketPath(root.socketPath)

  // Override Panel.close() so outside-click / Escape / shell.hide respect
  // suppressClose while a sheet is open in the panel.
  function close() {
    if (root.suppressClose) return
    root.controller.hide()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "⛨"
    foreground: root.connected ? Color.accent : Util.alpha(Color.foreground, 0.65)
    active: root.connected
    tooltipText: root.connected
      ? "Rayarchy — " + root.profileName
      : (root.profileName !== "" ? "Rayarchy — " + root.profileName : "Rayarchy — disconnected")
    onPressed: function (b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(Style.space(800))
    focusTarget: appLoader.item

    Loader {
      id: appLoader
      anchors.fill: parent
      source: "App.qml"
      onLoaded: {
        item.panelOwner = root
      }
    }
  }
}