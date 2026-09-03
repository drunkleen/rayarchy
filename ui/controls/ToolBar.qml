import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

// Compact, verbose top toolbar: every primary action is a visible labeled
// button (no dropdowns). Dialogs open as inline sheets in the same window.
Item {
  id: root

  property var app: null
  signal addRequested()
  signal pasteRequested()
  signal subsRequested()
  signal routingRequested()
  signal dnsRequested()
  signal optionsRequested()
  signal updateRequested()
  signal backupRequested()
  signal reloadRequested()
  signal closeRequested()

  height: Style.spacing.controlHeight + Style.space(8)

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(2)

    Text {
      text: "⛨"
      color: Color.accent
      font.pixelSize: Style.font.body
      Layout.alignment: Qt.AlignVCenter
      Layout.rightMargin: Style.space(4)
    }

    ToolBtn { label: "＋ Add"; onTriggered: root.addRequested() }
    ToolBtn { label: "⎘ Paste"; onTriggered: root.pasteRequested() }
    ToolBtn { label: "⌁ Subs"; onTriggered: root.subsRequested() }
    ToolBtn { label: "⇄ Routing"; onTriggered: root.routingRequested() }
    ToolBtn { label: "◎ DNS"; onTriggered: root.dnsRequested() }
    ToolBtn { label: "⚙ Options"; onTriggered: root.optionsRequested() }
    ToolBtn { label: "⇅ Update"; onTriggered: root.updateRequested() }
    ToolBtn { label: "⌫ Backup"; onTriggered: root.backupRequested() }

    Item { Layout.fillWidth: true }

    ToolBtn { label: "⟳"; onTriggered: root.reloadRequested() }
    ToolBtn { label: "✕"; onTriggered: root.closeRequested() }
  }

  component ToolBtn: Item {
    id: btn
    property string label: ""
    signal triggered()

    Layout.preferredHeight: Style.spacing.controlHeight
    implicitWidth: btnLabel.implicitWidth + Style.space(14)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: mouse.hovered || mouse.pressed
        ? Util.alpha(Color.foreground, mouse.pressed ? 0.14 : 0.08)
        : "transparent"
    }
    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: Color.foreground
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: btn.triggered()
    }
  }
}