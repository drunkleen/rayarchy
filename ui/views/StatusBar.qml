import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../controls/Common.js" as Common
import "../strings.js" as Strings

// Bottom status bar mirroring v2rayN: inbound display, TUN toggle, system
// proxy combo, routing combo, running-server readout, and realtime speed.
Rectangle {
  id: root

  property var app: null
  property var rpc: null
  property var status: ({})
  property var routing: []
  property bool available: false

  height: Style.spacing.controlHeight + Style.space(8)
  color: Util.alpha(Color.foreground, 0.05)

  function refreshRouting() {
    if (!root.rpc || !root.rpc.ready) return
    root.rpc.call("routing.list", {}, function (rows) {
      root.routing = rows || []
    })
  }

  onStatusChanged: {
    root.available = root.status.connected === true
  }

  property real lastUp: 0
  property real lastDown: 0
  property real lastSampleMs: 0
  property string speedText: ""

  function refreshSpeed() {
    if (!root.rpc || !root.rpc.ready || !root.status.connected) {
      root.speedText = "↑ -- ↓ --"
      return
    }
    root.rpc.call("stats.current", {}, function (result) {
      if (!result || result.error) return
      var up = result.up || 0
      var down = result.down || 0
      var now = Date.now()
      if (root.lastSampleMs > 0 && now > root.lastSampleMs) {
        var seconds = (now - root.lastSampleMs) / 1000
        var upRate = Math.max(0, up - root.lastUp) / seconds
        var downRate = Math.max(0, down - root.lastDown) / seconds
        root.speedText = "↑ " + Common.formatBytes(upRate) + "/s ↓ " + Common.formatBytes(downRate) + "/s"
      }
      root.lastUp = up
      root.lastDown = down
      root.lastSampleMs = now
    })
  }

  Timer {
    id: speedTimer
    interval: 2000
    repeat: true
    running: true
    onTriggered: root.refreshSpeed()
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(12)

    // Inbound display
    Text {
      text: {
        var port = root.status.localPort || 1080
        return "[mixed:" + port + "]"
      }
      color: Color.foreground
      font.family: "monospace"
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      text: Strings.tr("statusInbound")
      color: Color.muted
      font.pixelSize: Style.font.bodySmall
      visible: false
    }

    // TUN toggle
    RowLayout {
      spacing: Style.space(6)
      visible: true
      Text {
        text: "TUN"
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }
      ToggleSwitch {
        id: tunSwitch
        checked: root.app ? root.app.connectionMode === "tun" : false
        enabled: root.app && root.app.tunAvailable
        onToggled: root.app.toggleTun()
      }
    }

    Item { Layout.fillWidth: true }

    // System proxy combo
    Text {
      text: Strings.tr("statusSystemProxy")
      color: Color.muted
      font.pixelSize: Style.font.bodySmall
      Layout.alignment: Qt.AlignVCenter
    }
    ComboBox {
      id: sysProxyCombo
      model: [Strings.tr("statusNoChange"), Strings.tr("statusClear"), Strings.tr("statusSet")]
      Layout.preferredWidth: 130
      onActivated: root.changeSystemProxy(currentIndex)
    }

    // Routing combo
    Text {
      text: Strings.tr("statusRouting")
      color: Color.muted
      font.pixelSize: Style.font.bodySmall
      Layout.alignment: Qt.AlignVCenter
    }
    ComboBox {
      id: routingCombo
      Layout.preferredWidth: 150
      textRole: "name"
      valueRole: "id"
      model: {
        var out = []
        for (var i = 0; i < root.routing.length; i++) out.push(root.routing[i])
        return out
      }
      displayText: {
        var idx = currentIndex
        if (idx >= 0 && idx < root.routing.length) return root.routing[idx].name
        return Strings.tr("statusRouting")
      }
      onActivated: {
        if (currentIndex >= 0 && currentIndex < root.routing.length) {
          root.app.setActiveRouting(root.routing[currentIndex])
        }
      }
    }

    // Running server + availability readout
    Item {
      Layout.preferredWidth: 240
      Text {
        id: runningText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        elide: Text.ElideRight
        text: root.statusText()
        color: root.status.connected ? Color.accent : Color.foreground
        font.pixelSize: Style.font.bodySmall
        font.bold: root.status.connected === true
      }
      Text {
        id: infoText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: runningText.bottom
        elide: Text.ElideRight
        text: root.infoText()
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
      MouseArea {
        anchors.fill: parent
        onClicked: root.app.checkAvailability()
      }
    }

    // Realtime speed (proxy/direct deltas from stats.current)
    Text {
      text: root.speedText
      color: Color.muted
      font.family: "monospace"
      font.pixelSize: Style.font.caption
    }
  }

  function statusText() {
    if (root.status.connecting) return Strings.tr("runningConnecting")
    if (root.status.connected) return root.status.profileName || Strings.tr("connectedSummary")
    return Strings.tr("statusNotConnected")
  }

  function infoText() {
    if (root.status.connecting) return Strings.tr("statusAvailable")
    if (root.status.lastHealth && root.status.lastHealth.ok) {
      var lat = root.status.lastHealth.latencyMs
      var ip = root.status.lastIp ? root.status.lastIp.proxyIp : ""
      return (lat !== undefined ? lat + " ms" : "") + (ip ? " | " + ip : "")
    }
    if (root.status.lastIp && root.status.lastIp.proxyIp) {
      return root.status.lastIp.proxyIp
    }
    return ""
  }

  function changeSystemProxy(index) {
    // index 0 = No Change, 1 = Clear, 2 = Set
    if (index === 1) {
      if (root.app && root.app.disconnect()) return
      root.app.notify(Strings.tr("statusClear"))
    } else if (index === 2) {
      if (root.status.connected) root.app.notify(Strings.tr("statusSet"))
      else root.app.notify(Strings.tr("statusNotConnected"))
    }
    sysProxyCombo.currentIndex = 0
  }
}