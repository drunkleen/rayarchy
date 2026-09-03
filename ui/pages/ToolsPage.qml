import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../controls/Common.js" as Common
import "../strings.js" as Strings

// Tools: network tests on the live connection, test history, and maintenance
// actions (dedupe, statistics, diagnostics, backup/restore, updates).
Item {
  id: root

  property var app: null
  property var rpc: null
  property var status: ({})

  property var history: []
  property bool running: false

  function refresh() {
    if (!root.rpc || !root.rpc.ready) return
    root.rpc.call("test.history", {}, function (rows) {
      root.history = rows || []
    })
  }

  Component.onCompleted: root.refresh()

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(10)

    Text {
      text: "Network tests"
      color: Color.muted
      font.pixelSize: Style.font.caption
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.space(8)
      rowSpacing: Style.space(8)

      TestTile { icon: "✓"; label: "Proxy check"; onClicked: root.run("test.proxy", {}, "proxy check") }
      TestTile { icon: "✉"; label: "IP check"; onClicked: root.run("test.ip", {}, "IP check") }
      TestTile { icon: "⚡"; label: "Speed test"; enabled: root.status.connected; onClicked: root.run("test.speed", {}, "speed test") }
      TestTile { icon: "⇄"; label: "TCP test"; onClicked: root.run("test.tcp", {}, "TCP test") }
      TestTile { icon: "⟳"; label: "Check availability"; onClicked: root.app.checkAvailability() }
      TestTile { icon: "✎"; label: "Clear statistics"; onClicked: root.app.clearStatistics() }
      TestTile { icon: "♻"; label: "Remove duplicates"; onClicked: root.app.removeDuplicates() }
      TestTile { icon: "⛃"; label: "Backup / Restore"; onClicked: root.app.openBackupRestore() }
      TestTile { icon: "♻"; label: "Check updates"; onClicked: root.app.openCheckUpdate() }
      TestTile { icon: "↻"; label: "Reload core"; onClicked: root.app.reload() }
      TestTile { icon: "🗑"; label: "Clear history"; onClicked: root.clearHistory() }
      TestTile { icon: "ⓘ"; label: "Diagnostics"; onClicked: root.diagnostics() }
    }

    Text {
      text: "Test history"
      color: Color.muted
      font.pixelSize: Style.font.caption
      Layout.topMargin: Style.space(4)
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: Util.alpha(Color.background, 0.35)
      radius: Style.cornerRadius
      border.color: Util.alpha(Color.muted, 0.3)
      border.width: 1
      clip: true

      ListView {
        anchors.fill: parent
        anchors.margins: Style.space(4)
        clip: true
        model: root.history
        spacing: 0
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
          required property var modelData
          implicitHeight: Style.space(22)
          width: parent ? parent.width : 0
          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)
            Text {
              text: modelData.kind || ""
              color: Color.muted
              font.pixelSize: Style.font.caption
              Layout.preferredWidth: 90
            }
            Text {
              text: modelData.name || modelData.host || ""
              color: Color.foreground
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
            Text {
              text: modelData.ok === true
                ? ((modelData.latencyMs !== undefined ? modelData.latencyMs + " ms" : "ok")
                    + (modelData.megabitsPerSecond ? " · " + modelData.megabitsPerSecond + " Mb/s" : ""))
                : (modelData.error || "failed")
              color: modelData.ok === true ? Color.accent : Color.urgent
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.history.length === 0
        text: "No tests yet"
        color: Color.muted
        font.pixelSize: Style.font.body
      }
    }
  }

  component TestTile: Rectangle {
    id: tile
    property string icon: ""
    property string label: ""
    signal clicked()
    Layout.fillWidth: true
    Layout.preferredHeight: Style.space(40)
    radius: Style.cornerRadius
    color: tileMouse.hovered ? Util.alpha(Color.foreground, 0.07) : Util.alpha(Color.background, 0.35)
    border.color: Util.alpha(Color.muted, 0.3)
    border.width: 1

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)
      Text {
        text: tile.icon
        color: Color.accent
        font.pixelSize: Style.font.bodySmall
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

  function run(method, params, label) {
    if (root.running) return
    root.running = true
    root.app.notify(label + "…")
    root.rpc.call(method, params, function (result) {
      root.running = false
      if (result && result.error) root.app.notify(label + ": " + result.error)
      else if (result && result.ok === true) root.app.notify(label + " ✓ " + (result.latencyMs !== undefined ? result.latencyMs + " ms" : ""))
      else if (result && result.megabitsPerSecond) root.app.notify(label + " ✓ " + result.megabitsPerSecond + " Mb/s")
      else if (result && result.proxyIp) root.app.notify("IP: " + result.proxyIp + (result.protected ? " (protected)" : ""))
      else root.app.notify(label + " ✓")
      root.refresh()
    }, function (error) {
      root.running = false
      root.app.notify(label + ": " + error)
    })
  }

  function clearHistory() {
    root.app.confirm("Clear test history?", function () {
      root.rpc.call("test.history.clear", {}, function () { root.refresh() })
    })
  }

  function diagnostics() {
    root.rpc.call("system.diagnostics", {}, function (result) {
      if (!result) { root.app.notify("No diagnostics"); return }
      var lines = []
      lines.push("version: " + (result.version || "?"))
      if (result.status) {
        lines.push("connected: " + result.status.connected)
        lines.push("corePid: " + (result.status.corePid || "—"))
        lines.push("uptime: " + (result.status.coreUptimeSeconds || 0) + "s")
      }
      if (result.cores) {
        lines.push("xray: " + (result.cores.xray || "missing"))
        lines.push("sing-box: " + (result.cores.singBox || "missing"))
      }
      if (result.hints && result.hints.length) lines = lines.concat(result.hints)
      root.app.copyText(lines.join("\n"))
      root.app.notify("Diagnostics copied ✓")
    })
  }
}