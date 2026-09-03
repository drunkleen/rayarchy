import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings
import "../controls"

// Add / edit a subscription. Fields mirror v2rayN's SubEditWindow (core set;
// MoreUrl / Convert / Prev-Next arrive with Phase 2).
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property var subscription: null
  property string remarks: ""
  property string url: ""
  property bool enabledFlag: true
  property string autoUpdate: "daily"
  property string userAgent: ""
  property bool saving: false

  title: dialog.subscription ? Strings.tr("subEdit") : Strings.tr("subAdd")
  width: Math.min(parent ? parent.width * 0.5 : 560, 580)
  height: Math.min(parent ? parent.height * 0.55 : 440, 480)

  Component.onCompleted: {
    if (dialog.subscription) {
      dialog.remarks = dialog.subscription.name || ""
      dialog.url = dialog.subscription.url || ""
      dialog.enabledFlag = dialog.subscription.enabled !== false
      dialog.autoUpdate = dialog.subscription.autoUpdate || "daily"
      dialog.userAgent = dialog.subscription.userAgent || ""
    }
  }

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      GridLayout {
        columns: 2
        columnSpacing: Style.space(10)
        rowSpacing: Style.space(8)
        Layout.fillWidth: true

        Text { text: Strings.tr("name"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          Layout.fillWidth: true
          text: dialog.remarks
          onTextEdited: dialog.remarks = text
        }
        Text { text: Strings.tr("subUrl"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          Layout.fillWidth: true
          text: dialog.url
          placeholderText: "https://…"
          onTextEdited: dialog.url = text
        }
        Text { text: Strings.tr("enabled"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        CheckBox {
          checked: dialog.enabledFlag
          onCheckedChanged: dialog.enabledFlag = checked
        }
        Text { text: Strings.tr("subAutoUpdate"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        ComboBox {
          Layout.fillWidth: true
          model: ["off", "startup", "daily", "every_6_hours"]
          currentIndex: Math.max(0, ["off", "startup", "daily", "every_6_hours"].indexOf(dialog.autoUpdate))
          onActivated: dialog.autoUpdate = currentText
        }
        Text { text: Strings.tr("subUserAgent"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          Layout.fillWidth: true
          text: dialog.userAgent
          onTextEdited: dialog.userAgent = text
        }
      }

      Item { Layout.fillHeight: true }

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
          text: Strings.tr("save")
          highlighted: true
          enabled: !dialog.saving
          onClicked: dialog.save()
        }
      }
    }
  }

  function save() {
    var url = dialog.url.trim()
    if (!/^https?:\/\//.test(url)) {
      dialog.app.notify(Strings.tr("subUrl") + " invalid")
      return
    }
    var sub = {
      name: dialog.remarks.trim() || "Subscription",
      url: url,
      enabled: dialog.enabledFlag,
      autoUpdate: dialog.autoUpdate,
      userAgent: dialog.userAgent
    }
    if (dialog.subscription) sub.id = dialog.subscription.id
    dialog.saving = true
    var method = dialog.subscription ? "subscription.update" : "subscription.create"
    dialog.rpc.call(method, { subscription: sub }, function (result) {
      dialog.saving = false
      if (result.error) {
        dialog.app.notify(result.error)
        return
      }
      dialog.closeRequested()
      dialog.app.notify(Strings.tr("save") + " ✓")
      dialog.app.refreshAll()
    })
  }
}