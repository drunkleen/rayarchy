import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings
import "../controls"

// v2rayN DNS Setting: simple DNS servers plus protection toggles. Written
// through settings.update (the daemon preserves unrelated settings).
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property var settings: ({})
  property bool saving: false

  title: Strings.tr("dnsSetting")
  width: Math.min(parent ? parent.width * 0.56 : 640, 660)
  height: Math.min(parent ? parent.height * 0.66 : 560, 600)

  Component.onCompleted: {
    if (!dialog.rpc) return
    dialog.rpc.call("settings.get", {}, function (s) {
      dialog.settings = s || {}
      dialog.directDns = (s && s.dns && s.dns.direct) || "223.5.5.5"
      dialog.remoteDns = (s && s.dns && s.dns.remote) || "https://1.1.1.1/dns-query"
      dialog.bootstrapDns = (s && s.dns && s.dns.bootstrap) || "8.8.8.8"
    })
  }

  property string directDns: "223.5.5.5"
  property string remoteDns: "https://1.1.1.1/dns-query"
  property string bootstrapDns: "8.8.8.8"

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

        Text { text: Strings.tr("dnsDirect"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          Layout.fillWidth: true
          text: dialog.directDns
          onTextEdited: dialog.directDns = text
        }
        Text { text: Strings.tr("dnsRemote"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          Layout.fillWidth: true
          text: dialog.remoteDns
          onTextEdited: dialog.remoteDns = text
        }
        Text { text: Strings.tr("dnsBootstrap"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          Layout.fillWidth: true
          text: dialog.bootstrapDns
          onTextEdited: dialog.bootstrapDns = text
        }
        Text { text: Strings.tr("dnsFakeIp"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        CheckBox { id: fakeIpField; checked: false; enabled: false }
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
      healthRetentionHours: dialog.settings.healthRetentionHours || 24,
      dns: {
        direct: dialog.directDns.trim() || "223.5.5.5",
        remote: dialog.remoteDns.trim() || "https://1.1.1.1/dns-query",
        bootstrap: dialog.bootstrapDns.trim() || "8.8.8.8",
        systemHosts: true
      }
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