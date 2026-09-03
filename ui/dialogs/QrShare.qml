import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qs.Commons
import "../strings.js" as Strings
import "../controls"

// v2rayN Share Server dialog: QR image (when available) plus the payload
// text with a copy button.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property string payload: ""
  property string imagePath: ""
  property string error: ""

  title: Strings.tr("qrShareTitle")
  width: Math.min(parent ? parent.width * 0.46 : 480, 520)
  height: Math.min(parent ? parent.height * 0.62 : 540, 580)

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 240
        Layout.preferredHeight: 240
        color: "white"
        radius: Style.cornerRadius
        visible: dialog.imagePath !== ""
        Image {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          source: dialog.imagePath !== "" ? "file://" + dialog.imagePath : ""
          fillMode: Image.PreserveAspectFit
          smooth: true
        }
      }

      Text {
        Layout.alignment: Qt.AlignHCenter
        text: dialog.imagePath === "" && dialog.error ? dialog.error : ""
        color: Color.urgent
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(120, dialog.height * 0.3)
        color: Util.alpha(Color.background, 0.35)
        radius: Style.cornerRadius
        border.color: Util.alpha(Color.muted, 0.3)
        border.width: 1
        clip: true

        TextArea {
          anchors.fill: parent
          anchors.margins: Style.space(6)
          readOnly: true
          text: dialog.payload
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Item { Layout.fillWidth: true }
        Button {
          text: Strings.tr("qrCopyPayload")
          flat: true
          onClicked: dialog.app.copyText(dialog.payload)
        }
        Button { text: Strings.tr("close"); flat: true; onClicked: dialog.closeRequested() }
      }
    }
  }
}