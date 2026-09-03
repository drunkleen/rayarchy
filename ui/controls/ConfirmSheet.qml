import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings

// Inline yes/no message box used by every destructive or guarded action.
Rectangle {
  id: root

  property string message: ""
  property string okText: Strings.tr("yes")
  property string cancelText: Strings.tr("no")
  property bool okDanger: true
  signal ok()
  signal cancelled()

  width: Math.min(parent ? parent.width * 0.4 : 420, 460)
  height: contentColumn.height + Style.space(32)
  anchors.centerIn: parent
  z: 100

  color: Color.background
  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 0
  border.color: Color.muted
  border.width: 1

  ColumnLayout {
    id: contentColumn
    anchors.fill: parent
    anchors.margins: Style.space(18)
    spacing: Style.space(16)

    Text {
      text: root.message
      color: Color.foreground
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Item { Layout.fillWidth: true }
      Button {
        text: root.cancelText
        flat: true
        onClicked: root.cancelled()
      }
      Button {
        text: root.okText
        highlighted: root.okDanger
        onClicked: root.ok()
      }
    }
  }

  function close() { root.destroy() }
}