import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../controls/Common.js" as Common
import "../strings.js" as Strings

// Overview: big connect/disconnect toggle, connection mode + TUN switch,
// live status, realtime speed, and quick actions.
Item {
  id: root

  property var app: null
  property var rpc: null
  property var status: ({})

  function refresh() {
    if (app) app.refreshStatus()
  }

  onStatusChanged: { }
  Component.onCompleted: root.refresh()

  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: root.refreshSpeed()
  }

  property real lastUp: 0
  property real lastDown: 0
  property real lastSampleMs: 0
  property string speedText: "↑ -- ↓ --"
  property var todayStats: ({})

  function refreshSpeed() {
    if (!rpc || !rpc.ready || !root.status.connected) {
      root.speedText = "↑ -- ↓ --"
      return
    }
    rpc.call("stats.current", {}, function (result) {
      if (!result || result.error) return
      var up = result.up || 0
      var down = result.down || 0
      var now = Date.now()
      if (root.lastSampleMs > 0 && now > root.lastSampleMs) {
        var seconds = (now - root.lastSampleMs) / 1000
        var upRate = Math.max(0, up - root.lastUp) / seconds
        var downRate = Math.max(0, down - root.lastDown) / seconds
        root.speedText = "↑ " + Common.formatBytes(upRate) + "/s   ↓ " + Common.formatBytes(downRate) + "/s"
      }
      root.lastUp = up
      root.lastDown = down
      root.lastSampleMs = now
    })
  }

  Flickable {
    anchors.fill: parent
    anchors.margins: Style.space(14)
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true

    ColumnLayout {
      id: column
      width: parent.width
      spacing: Style.space(12)

      // ---- big connect toggle ----
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(76)
        radius: Style.cornerRadius
        color: Util.alpha(Color.background, 0.35)
        border.color: root.status.connected ? Color.accent : Util.alpha(Color.muted, 0.35)
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.space(14)
          spacing: Style.space(12)

          Rectangle {
            Layout.preferredWidth: Style.space(52)
            Layout.preferredHeight: Style.space(52)
            radius: Style.space(26)
            color: root.status.connected
              ? Util.alpha(Color.accent, 0.25)
              : (root.status.connecting ? Util.alpha(Color.urgent, 0.25) : Util.alpha(Color.muted, 0.18))
            Text {
              anchors.centerIn: parent
              text: root.status.connected ? "⏻" : (root.status.connecting ? "⟳" : "⏻")
              color: root.status.connected ? Color.accent : (root.status.connecting ? Color.urgent : Color.foreground)
              font.pixelSize: Style.font.title * 1.4
            }
            MouseArea {
              anchors.fill: parent
              onClicked: {
                if (root.status.connected) root.app.disconnect()
                else root.app.connectDefault()
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              text: root.status.connected
                ? (root.status.profileName || Strings.tr("connectedSummary"))
                : (root.status.connecting ? Strings.tr("runningConnecting") : Strings.tr("statusNotConnected"))
              color: root.status.connected ? Color.accent : Color.foreground
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
            Text {
              text: root.infoText()
              color: Color.muted
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          Button {
            text: root.status.connected ? "Disconnect" : "Connect"
            highlighted: !root.status.connected
            enabled: !root.status.connecting
            onClicked: {
              if (root.status.connected) root.app.disconnect()
              else root.app.connectDefault()
            }
          }
        }
      }

      // ---- TUN + mode ----
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(56)
        radius: Style.cornerRadius
        color: Util.alpha(Color.background, 0.35)
        border.color: Util.alpha(Color.muted, 0.35)
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(14)
          anchors.rightMargin: Style.space(14)
          spacing: Style.space(10)

          Text {
            text: "TUN"
            color: Color.foreground
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Switch {
            checked: root.app ? root.app.connectionMode === "tun" : false
            enabled: root.app && root.app.tunAvailable
            onToggled: root.app.toggleTun()
          }
          Text {
            text: Strings.tr("statusTun")
            color: Color.muted
            font.pixelSize: Style.font.bodySmall
          }

          Item { Layout.fillWidth: true }

          Text {
            text: "[mixed:" + (root.status.localPort || 1080) + "]"
            color: Color.foreground
            font.family: "monospace"
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // ---- stats ----
      GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Style.space(10)
        rowSpacing: Style.space(10)

        StatCard {
          label: Strings.tr("colTodayUp")
          value: root.status.todayUp !== undefined ? Common.formatBytes(root.status.todayUp) : "0 B"
        }
        StatCard {
          label: Strings.tr("colTodayDown")
          value: root.status.todayDown !== undefined ? Common.formatBytes(root.status.todayDown) : "0 B"
        }
        StatCard {
          label: Strings.tr("colTotalUp")
          value: root.status.totalUp !== undefined ? Common.formatBytes(root.status.totalUp) : "0 B"
        }
        StatCard {
          label: Strings.tr("colTotalDown")
          value: root.status.totalDown !== undefined ? Common.formatBytes(root.status.totalDown) : "0 B"
        }
      }

      // ---- realtime speed ----
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(48)
        radius: Style.cornerRadius
        color: Util.alpha(Color.background, 0.35)
        border.color: Util.alpha(Color.muted, 0.35)
        border.width: 1
        Text {
          anchors.centerIn: parent
          text: root.speedText
          color: Color.foreground
          font.family: "monospace"
          font.pixelSize: Style.font.body
        }
      }

      // ---- quick actions ----
      Text {
        text: Strings.tr("menuServers")
        color: Color.muted
        font.pixelSize: Style.font.caption
      }

      GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Style.space(8)
        rowSpacing: Style.space(8)

        ActionTile { icon: "＋"; label: Strings.tr("serverEditTitle"); onClicked: root.app.openAddServer() }
        ActionTile { icon: "⧉"; label: Strings.tr("importFromClipboard"); onClicked: root.app.importClipboard() }
        ActionTile { icon: "⇄"; label: Strings.tr("subSetting"); onClicked: root.app.setPage("subs") }
        ActionTile { icon: "≣"; label: Strings.tr("tabMsg"); onClicked: root.app.setPage("logs") }
      }

      Item { height: Style.space(8) }
    }
  }

  component StatCard: Rectangle {
    id: card
    property string label: ""
    property string value: ""
    Layout.fillWidth: true
    Layout.preferredHeight: Style.space(52)
    radius: Style.cornerRadius
    color: Util.alpha(Color.background, 0.35)
    border.color: Util.alpha(Color.muted, 0.3)
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: 0
      Text {
        text: card.label
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
      Text {
        text: card.value
        color: Color.foreground
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
    }
  }

  component ActionTile: Rectangle {
    id: tile
    property string icon: ""
    property string label: ""
    signal clicked()

    Layout.fillWidth: true
    Layout.preferredHeight: Style.space(44)
    radius: Style.cornerRadius
    color: tileMouse.hovered ? Util.alpha(Color.foreground, 0.07) : Util.alpha(Color.background, 0.35)
    border.color: Util.alpha(Color.muted, 0.3)
    border.width: 1

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(8)
      Text {
        text: tile.icon
        color: Color.accent
        font.pixelSize: Style.font.body
      }
      Text {
        text: tile.label
        color: Color.foreground
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: tile.clicked()
    }
  }

  function infoText() {
    if (root.status.connecting) return Strings.tr("statusAvailable")
    if (root.status.lastHealth && root.status.lastHealth.ok) {
      var lat = root.status.lastHealth.latencyMs
      var ip = root.status.lastIp ? root.status.lastIp.proxyIp : ""
      return (lat !== undefined ? lat + " ms" : "") + (ip ? " | " + ip : "")
    }
    if (root.status.lastIp && root.status.lastIp.proxyIp) return root.status.lastIp.proxyIp
    return Strings.tr("statusNotConnected")
  }
}