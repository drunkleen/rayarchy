import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings
import "../controls"

// v2rayN DNS Setting (Phase 1: simple DNS flags; custom templates arrive in
// Phase 2). Writes through settings.update.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property var settings: ({})
  property bool saving: false

  title: Strings.tr("dnsSetting")
  width: Math.min(parent ? parent.width * 0.56 : 640, 660)
  height: Math.min(parent ? parent.height * 0.6 : 520, 560)

  Component.onCompleted: {
    if (!dialog.rpc) return
    dialog.rpc.call("settings.get", {}, function (s) { dialog.settings = s || {} })
  }

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        text: Strings.tr("dnsSimple")
        color: Color.foreground
        font.pixelSize: Style.font.title
        font.bold: true
      }

      GridLayout {
        columns: 2
        columnSpacing: Style.space(12)
        rowSpacing: Style.space(10)
        Layout.fillWidth: true

        Text { text: Strings.tr("settingDnsLeak"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        CheckBox { id: dnsField; checked: dialog.settings.dnsLeakProtection !== false }
        Text { text: Strings.tr("dnsSystemHosts"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        CheckBox { id: hostsField; checked: false }
        Text { text: Strings.tr("dnsFakeIp"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        CheckBox { id: fakeIpField; checked: false; enabled: false }
      }

      Text {
        Layout.fillWidth: true
        text: Strings.tr("tunNotAvailable")
        color: Color.muted
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Item { Layout.fillHeight: true }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Item { Layout.fillWidth: true }
        Button { text: Strings.tr("cancel"); flat: true; onClicked: dialog.closeRequested() }
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
    var s = {
      connectionMode: dialog.settings.connectionMode || "system_proxy",
      preferredCore: dialog.settings.preferredCore || "auto",
      localPort: dialog.settings.localPort || 1080,
      killSwitch: false,
      dnsLeakProtection: dnsField.checked,
      lanBypass: dialog.settings.lanBypass !== false,
      healthRetentionHours: dialog.settings.healthRetentionHours || 24
    }
    dialog.saving = true
    dialog.rpc.call("settings.update", { settings: s }, function (result) {
      dialog.saving = false
      if (result.error) { dialog.app.notify(result.error); return }
      dialog.closeRequested()
      dialog.app.notify(Strings.tr("save") + " ✓")
    })
  }
}