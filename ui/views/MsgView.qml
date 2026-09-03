import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings

// v2rayN Msg console: filtered log lines with copy/clear and auto-refresh.
Rectangle {
  id: root

  property var app: null
  property var rpc: null
  property var logs: []
  property string filterText: ""
  property bool autoRefresh: true

  color: "transparent"

  function refresh() {
    if (!root.rpc || !root.rpc.ready) return
    root.rpc.call("system.logs", { limit: 400 }, function (result) {
      root.logs = result.lines || []
    })
  }

  function filtered() {
    if (root.filterText === "") return root.logs
    var needle = root.filterText.toLowerCase()
    var out = []
    for (var i = 0; i < root.logs.length; i++) {
      if (root.logs[i].toLowerCase().indexOf(needle) !== -1) out.push(root.logs[i])
    }
    return out
  }

  Timer {
    id: pollTimer
    interval: 1500
    repeat: true
    running: root.autoRefresh
    onTriggered: root.refresh()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(8)
    spacing: Style.space(8)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      TextField {
        id: filterField
        Layout.preferredWidth: 220
        placeholderText: Strings.tr("msgFilter")
        onTextEdited: root.filterText = text
      }

      Item { Layout.fillWidth: true }

      Button {
        text: Strings.tr("msgCopy")
        flat: true
        onClicked: {
          var joined = root.filtered().join("\n")
          root.app.copyText(joined)
        }
      }
      Button {
        text: Strings.tr("msgClear")
        flat: true
        onClicked: root.app.clearLogs()
      }
      CheckBox {
        text: Strings.tr("msgAutoRefresh")
        checked: root.autoRefresh
        onCheckedChanged: root.autoRefresh = checked
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: Util.alpha(Color.background, 0.35)
      radius: Style.cornerRadius
      border.color: Util.alpha(Color.muted, 0.3)
      border.width: 1
      clip: true

      Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Style.space(6)
        contentWidth: logText.width
        contentHeight: logText.height
        clip: true

        Text {
          id: logText
          width: Math.max(flick.width - Style.space(8), 0)
          text: root.filtered().join("\n")
          color: Color.foreground
          font.family: "monospace"
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WrapAnywhere
        }
      }

      Text {
        anchors.centerIn: parent
        text: Strings.tr("msgEmpty")
        color: Color.muted
        font.pixelSize: Style.font.body
        visible: root.filtered().length === 0
      }
    }
  }
}