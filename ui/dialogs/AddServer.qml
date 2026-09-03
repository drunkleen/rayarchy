import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../controls/Common.js" as Common
import "../strings.js" as Strings
import "../controls"

// "Add server" — every protocol is a visible button in a grid (no dropdown).
// Clicking one opens the server editor for that protocol as an inline sheet.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null

  title: Strings.tr("serverEditTitle")
  width: Math.min(parent ? parent.width * 0.56 : 620, 640)
  height: Math.min(parent ? parent.height * 0.56 : 480, 500)

  readonly property var protocols: [
    { id: "vless", label: "VLESS", color: "#8be9fd" },
    { id: "vmess", label: "VMess", color: "#bd93f9" },
    { id: "trojan", label: "Trojan", color: "#ff79c6" },
    { id: "shadowsocks", label: "Shadowsocks", color: "#f1fa8c" },
    { id: "socks", label: "SOCKS", color: "#50fa7b" },
    { id: "http", label: "HTTP", color: "#6272a4" },
    { id: "hysteria2", label: "Hysteria2", color: "#ffb86c" },
    { id: "tuic", label: "TUIC", color: "#ff5555" },
    { id: "wireguard", label: "WireGuard", color: "#f8f8f2" },
    { id: "anytls", label: "Anytls", color: "#ff79c6" },
    { id: "naive", label: "Naive", color: "#66d9ef" },
    { id: "custom", label: "Custom", color: "#a6e22e" },
    { id: "policy-group", label: "Policy Group", color: "#e6db74" },
    { id: "proxy-chain", label: "Proxy Chain", color: "#f92672" }
  ]

  function pick(protocol) {
    dialog.app.openServerEditor(protocol, null)
    dialog.closeRequested()
  }

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Button {
          text: Strings.tr("importFromClipboard")
          flat: true
          Layout.preferredHeight: Style.spacing.controlHeight
          onClicked: { dialog.app.importClipboard(); dialog.closeRequested() }
        }
        Button {
          text: Strings.tr("importFromImage")
          flat: true
          Layout.preferredHeight: Style.spacing.controlHeight
          onClicked: { dialog.app.importImage(); dialog.closeRequested() }
        }
        Item { Layout.fillWidth: true }
        Button {
          text: Strings.tr("close")
          flat: true
          Layout.preferredHeight: Style.spacing.controlHeight
          onClicked: dialog.closeRequested()
        }
      }

      GridLayout {
        columns: 2
        columnSpacing: Style.space(8)
        rowSpacing: Style.space(8)
        Layout.fillWidth: true
        Layout.fillHeight: true

        Repeater {
          model: dialog.protocols
          delegate: Rectangle {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: Style.spacing.controlHeight + Style.space(6)
            radius: Style.cornerRadius
            color: mouse.hovered
              ? Util.alpha(Color.foreground, 0.08)
              : Util.alpha(Color.background, 0.35)
            border.color: Util.alpha(Color.muted, 0.3)
            border.width: 1

            Rectangle {
              width: 8
              height: 8
              radius: 4
              color: modelData.color
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(28)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: Color.foreground
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: mouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: dialog.pick(modelData.id)
            }
          }
        }
      }
    }
  }
}