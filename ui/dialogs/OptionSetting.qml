import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings
import "../controls"

// v2rayN Option Setting (core set): General, Core, Speed test, TUN, UI tabs.
// TUN options are read-only until the privileged helper lands in Phase 3.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property var settings: ({})
  property bool saving: false

  title: Strings.tr("optSetting")
  width: Math.min(parent ? parent.width * 0.62 : 720, 760)
  height: Math.min(parent ? parent.height * 0.72 : 600, 640)

  Component.onCompleted: dialog.load()
  function load() {
    if (!dialog.rpc) return
    dialog.rpc.call("settings.get", {}, function (s) {
      dialog.settings = s || {}
    })
  }

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      TabBar {
        id: tabBar
        Layout.fillWidth: true
        TabButton { text: Strings.tr("settingGeneral") }
        TabButton { text: Strings.tr("settingCore") }
        TabButton { text: Strings.tr("settingSpeed") }
        TabButton { text: Strings.tr("settingTun") }
        TabButton { text: Strings.tr("settingUi") }
      }

      StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: tabBar.currentIndex

        // General
        GridLayout {
          columns: 2
          columnSpacing: Style.space(12)
          rowSpacing: Style.space(10)
          anchors.fill: parent
          anchors.margins: Style.space(8)

          Text { text: Strings.tr("settingLocalPort"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
          TextField {
            id: portField
            Layout.preferredWidth: 120
            text: dialog.settings.localPort || "1080"
            validator: IntValidator { bottom: 1; top: 65535 }
          }
          Text { text: Strings.tr("settingConnectionMode"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
          ComboBox {
            id: modeField
            Layout.fillWidth: true
            model: [Strings.tr("settingModeSystemProxy"), Strings.tr("settingModeLocal"), Strings.tr("settingModeTun"), Strings.tr("settingModeTransparent")]
            currentIndex: {
              var map = { system_proxy: 0, local: 1, tun: 2, transparent: 3 }
              var idx = map[dialog.settings.connectionMode]
              return idx !== undefined ? idx : 0
            }
            onActivated: {
              if (currentIndex >= 2) {
                dialog.app.notify(Strings.tr("tunNotAvailable"))
                currentIndex = dialog.settings.connectionMode === "local" ? 1 : 0
              }
            }
          }
          Text { text: Strings.tr("settingKillSwitch"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
          CheckBox {
            id: killSwitchField
            checked: !!dialog.settings.killSwitch
            enabled: false
          }
          Text { text: Strings.tr("settingDnsLeak"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
          CheckBox { id: dnsField; checked: dialog.settings.dnsLeakProtection !== false }
          Text { text: Strings.tr("settingLanBypass"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
          CheckBox { id: lanField; checked: dialog.settings.lanBypass !== false }
        }

        // Core
        GridLayout {
          columns: 2
          columnSpacing: Style.space(12)
          rowSpacing: Style.space(10)
          anchors.fill: parent
          anchors.margins: Style.space(8)

          Text { text: Strings.tr("settingPreferredCore"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
          ComboBox {
            id: coreField
            Layout.fillWidth: true
            model: ["auto", "xray", "sing-box"]
            currentIndex: Math.max(0, ["auto", "xray", "sing-box"].indexOf(dialog.settings.preferredCore || "auto"))
          }
          Text { text: Strings.tr("coreInstalled"); color: Color.muted; font.pixelSize: Style.font.bodySmall }
          Text {
            text: {
              var caps = rootStatus ? "" : ""
              return Strings.tr("coreInstalled")
            }
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
        }

        // Speed test
        GridLayout {
          columns: 2
          columnSpacing: Style.space(12)
          rowSpacing: Style.space(10)
          anchors.fill: parent
          anchors.margins: Style.space(8)

          Text { text: Strings.tr("settingRetention"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
          TextField {
            id: retentionField
            Layout.preferredWidth: 120
            text: dialog.settings.healthRetentionHours || "24"
            validator: IntValidator { bottom: 1; top: 720 }
          }
        }

        // TUN
        Column {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(8)
          Text {
            text: Strings.tr("tunNotAvailable")
            color: Color.muted
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            width: parent.width
          }
        }

        // UI
        Column {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(8)
          Text {
            text: Strings.tr("settingUi")
            color: Color.muted
            font.pixelSize: Style.font.bodySmall
            width: parent.width
          }
        }
      }

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

  property var rootStatus: null

  function save() {
    var port = parseInt(portField.text, 10)
    if (isNaN(port) || port < 1 || port > 65535) {
      dialog.app.notify(Strings.tr("serverEditInvalid"))
      return
    }
    var retention = parseInt(retentionField.text, 10)
    var s = {
      connectionMode: dialog.settings.connectionMode || "system_proxy",
      preferredCore: coreField.currentText,
      localPort: port,
      killSwitch: false,
      dnsLeakProtection: dnsField.checked,
      lanBypass: lanField.checked,
      healthRetentionHours: isNaN(retention) ? 24 : retention
    }
    dialog.saving = true
    dialog.rpc.call("settings.update", { settings: s }, function (result) {
      dialog.saving = false
      if (result.error) {
        dialog.app.notify(result.error)
        return
      }
      dialog.closeRequested()
      dialog.app.notify(Strings.tr("save") + " ✓")
      if (dialog.app.status.connected) {
        dialog.app.confirm(Strings.tr("reload") + "?", function () { dialog.app.reload() })
      }
    })
  }
}