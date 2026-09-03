import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../controls/Common.js" as Common
import "../strings.js" as Strings
import "../controls"

// Profile picker used by policy-group/proxy-chain member selection and other
// flows. Multi-select by default; OK hands the chosen ids to `thenSelect`.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property bool multiSelect: true
  property var selectedIds: []
  property var profiles: []
  property string filterText: ""
  property string groupFilter: ""
  property var thenSelect: null

  title: Strings.tr("profilesSelectTitle")

  width: Math.min(parent ? parent.width * 0.6 : 700, 740)
  height: Math.min(parent ? parent.height * 0.7 : 560, 620)

  Component.onCompleted: dialog.refresh()

  function refresh() {
    if (!dialog.rpc) return
    dialog.rpc.call("profile.list", {}, function (rows) {
      dialog.profiles = rows || []
    })
  }

  function filtered() {
    var needle = dialog.filterText.toLowerCase()
    var out = []
    for (var i = 0; i < dialog.profiles.length; i++) {
      var p = dialog.profiles[i]
      if (dialog.groupFilter && p.group !== dialog.groupFilter) continue
      if (needle && p.name.toLowerCase().indexOf(needle) === -1
          && Common.str(p.server).toLowerCase().indexOf(needle) === -1) continue
      if (!multiSelect) continue
      out.push(p)
    }
    return out
  }

  function isSelected(id) {
    return dialog.selectedIds.indexOf(id) !== -1
  }

  function toggle(id) {
    var ids = dialog.selectedIds.slice()
    var at = ids.indexOf(id)
    if (at !== -1) ids.splice(at, 1)
    else if (dialog.multiSelect) ids.push(id)
    else ids = [id]
    dialog.selectedIds = ids
  }

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      TextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: Strings.tr("searchPlaceholder")
        onTextEdited: dialog.filterText = text
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
          model: dialog.filtered()
          delegate: Row {
            required property var modelData
            required property int index
            width: list.width
            height: Style.spacing.popupRowHeight
            spacing: Style.space(8)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: hover.hovered || dialog.isSelected(modelData.id)
                ? Util.alpha(Color.foreground, dialog.isSelected(modelData.id) ? 0.16 : 0.07)
                : "transparent"
            }
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              text: Common.protocolLabel(modelData.protocol)
              color: Common.protocolColor(modelData.protocol)
              font.pixelSize: Style.font.caption
            }
            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10) + 92
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              color: Color.foreground
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: list.width - 110
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.rightMargin: Style.space(10)
              text: dialog.isSelected(modelData.id) ? "✓" : ""
              color: Color.accent
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              onClicked: dialog.toggle(modelData.id)
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Item { Layout.fillWidth: true }
        Button {
          text: Strings.tr("cancel")
          flat: true
          onClicked: dialog.closeRequested()
        }
        Button {
          text: Strings.tr("ok")
          highlighted: true
          onClicked: {
            if (dialog.thenSelect) dialog.thenSelect(dialog.selectedIds)
            dialog.closeRequested()
          }
        }
      }
    }
  }
}