import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

// A single modal sheet rendered inside the Rayarchy window. No external
// windows are ever created; dialogs are stacked sheets over the main view.
Rectangle {
  id: root

  property string title: ""
  property alias content: contentLoader.sourceComponent
  property alias contentItem: contentLoader.item
  property int sheetWidth: Math.min(parent ? parent.width * 0.72 : 760, 860)
  property int sheetHeight: Math.min(parent ? parent.height * 0.78 : 600, 700)
  property bool closable: true
  property bool maximized: false
  property var payload: ({})
  signal closeRequested()

  color: Color.background
  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 0
  border.color: Color.muted
  border.width: 1

  width: maximized ? parent.width : sheetWidth
  height: maximized ? parent.height : sheetHeight
  anchors.centerIn: parent

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Text {
        text: root.title
        color: Color.foreground
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      Item { Layout.fillWidth: true }

      Button {
        text: root.maximized ? "▣" : "▢"
        flat: true
        visible: root.closable
        onClicked: root.maximized = !root.maximized
      }
      Button {
        text: "✕"
        flat: true
        visible: root.closable
        onClicked: root.closeRequested()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Color.muted
      opacity: 0.35
    }

    Loader {
      id: contentLoader
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
    }
  }
}