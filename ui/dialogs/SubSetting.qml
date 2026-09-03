import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../controls/Common.js" as Common
import "../strings.js" as Strings
import "../controls"

// v2rayN Subscription Setting window: table of subscriptions with add/edit/
// delete/update actions.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property var subs: []
  property var selectedId: null

  title: Strings.tr("subSetting")
  width: Math.min(parent ? parent.width * 0.66 : 760, 800)
  height: Math.min(parent ? parent.height * 0.66 : 560, 600)

  Component.onCompleted: dialog.refresh()
  function refresh() {
    if (!dialog.rpc) return
    dialog.rpc.call("subscription.list", {}, function (rows) {
      dialog.subs = rows || []
    })
  }

  function selected() {
    for (var i = 0; i < dialog.subs.length; i++) {
      if (String(dialog.subs[i].id) === String(dialog.selectedId)) return dialog.subs[i]
    }
    return null
  }

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Button { text: Strings.tr("add"); flat: true; onClicked: dialog.app.addSubscription() }
        Button { text: Strings.tr("edit"); flat: true; enabled: dialog.selectedId !== null; onClicked: dialog.app.editSubscription(dialog.selectedId) }
        Button { text: Strings.tr("delete"); flat: true; enabled: dialog.selectedId !== null; onClicked: dialog.app.deleteSubscription(dialog.selectedId) }
        Button { text: Strings.tr("subRefresh"); flat: true; enabled: dialog.selectedId !== null; onClicked: dialog.app.refreshSubscription(dialog.selectedId) }
        Item { Layout.fillWidth: true }
        Button { text: Strings.tr("close"); flat: true; onClicked: dialog.closeRequested() }
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
          model: dialog.subs
          delegate: Row {
            required property var modelData
            required property int index
            width: parent ? parent.width : 0
            height: Style.spacing.popupRowHeight
            spacing: Style.space(6)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: hover.hovered || String(dialog.selectedId) === String(modelData.id)
                ? Util.alpha(Color.foreground, String(dialog.selectedId) === String(modelData.id) ? 0.16 : 0.07)
                : "transparent"
            }

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              width: 200
              elide: Text.ElideRight
              text: modelData.name
              color: Color.foreground
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(220)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.rightMargin: Style.space(110)
              elide: Text.ElideMiddle
              text: modelData.url
              color: Color.muted
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.rightMargin: Style.space(10)
              text: modelData.enabled ? Strings.tr("enabled") : Strings.tr("disabled")
              color: modelData.enabled ? Color.accent : Color.muted
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              onClicked: dialog.selectedId = modelData.id
              onDoubleClicked: dialog.app.editSubscription(modelData.id)
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: {
          var sub = dialog.selected()
          if (!sub) return ""
          var last = sub.lastRefreshAt ? Common.timeAgo(sub.lastRefreshAt) : Strings.tr("subNever")
          return Strings.tr("subLastRefresh") + ": " + last + (sub.lastError ? " — " + sub.lastError : "")
        }
        color: Color.muted
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
        visible: dialog.selected() !== null
      }
    }
  }
}