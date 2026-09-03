import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings

// v2rayN Clash Connections panel (sing-box clash_api).
Item {
  id: root

  property var app: null
  property var rpc: null
  property var connections: []
  property string filterText: ""

  function refresh() {
    if (!root.rpc || !root.rpc.ready) return
    root.rpc.call("clash.connections", {}, function (result) {
      if (!result || result.error || !result.connections) return
      var list = result.connections
      if (root.filterText !== "") {
        var needle = root.filterText.toLowerCase()
        list = list.filter(function (c) {
          return String(c.host || "").toLowerCase().indexOf(needle) !== -1
            || String(c.chain || "").toLowerCase().indexOf(needle) !== -1
        })
      }
      root.connections = list
    })
  }

  function closeAll() {
    root.rpc.call("clash.closeAll", {}, function () { root.refresh() })
  }

  function closeOne(id) {
    root.rpc.call("clash.closeConnection", { id: id }, function () { root.refresh() })
  }

  Timer {
    id: pollTimer
    interval: 4000
    repeat: true
    running: root.app && root.app.showClashUI
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
        Layout.preferredWidth: 200
        placeholderText: Strings.tr("msgFilter")
        onTextEdited: root.filterText = text
      }
      Item { Layout.fillWidth: true }
      Button { text: Strings.tr("reload"); flat: true; onClicked: root.refresh() }
      Button { text: Strings.tr("closeAll"); flat: true; onClicked: root.closeAll() }
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
        id: list
        anchors.fill: parent
        anchors.margins: Style.space(4)
        clip: true
        model: root.connections
        delegate: Row {
          required property var modelData
          width: list.width
          height: Style.spacing.popupRowHeight

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: hover.hovered ? Util.alpha(Color.foreground, 0.07) : "transparent"
          }

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            width: 180
            elide: Text.ElideRight
            text: modelData.host || ""
            color: Color.foreground
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(196)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(160)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: (modelData.chain || []).join(" > ")
            color: Color.muted
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.elapsed ? Math.round(modelData.elapsed) + " s" : ""
            color: Color.muted
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.RightButton
            onClicked: function (mouse) {
              root.app.contextMenu([
                { label: Strings.tr("close"), action: "close" }
              ], mouse.x, mouse.y, function (item) {
                if (item.action === "close") root.closeOne(modelData.id)
              })
            }
          }
        }
      }
    }
  }
}