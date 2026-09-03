import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings

// Settings: connection mode (system proxy/local/TUN/transparent), kill switch,
// preferred core, local port, DNS protection, LAN bypass, health retention,
// and maintenance actions (updates, backup/restore).
Item {
  id: root

  property var app: null
  property var rpc: null
  property var status: ({})

  property var settings: ({})
  property string localPort: "1080"
  property string retention: "24"
  property string subConvert: ""
  property bool saving: false

  function refresh() {
    if (!root.rpc || !root.rpc.ready) return
    root.rpc.call("settings.get", {}, function (s) {
      root.settings = s || {}
      root.localPort = String(s && s.localPort ? s.localPort : 1080)
      root.retention = String(s && s.healthRetentionHours ? s.healthRetentionHours : 24)
      root.subConvert = (s && s.subConvertUrl) || ""
    })
  }

  Component.onCompleted: root.refresh()

  Flickable {
    anchors.fill: parent
    anchors.margins: Style.space(14)
    contentWidth: width
    contentHeight: col.implicitHeight
    clip: true

    ColumnLayout {
      id: col
      width: parent.width
      spacing: Style.space(12)

      Group {
        title: Strings.tr("settingGeneral")
        FieldRow {
          label: Strings.tr("settingLocalPort")
          value: root.localPort
          numeric: true
          onChanged: function (v) { root.localPort = v }
        }
        FieldRow {
          label: Strings.tr("settingConnectionMode")
          combo: true
          comboModel: [Strings.tr("settingModeSystemProxy"), Strings.tr("settingModeLocal"), Strings.tr("settingModeTun"), Strings.tr("settingModeTransparent")]
          comboIndex: root.modeIndex()
          onComboChanged: function (i) { root.modeChanged(i) }
        }
        ToggleRow {
          label: Strings.tr("settingKillSwitch")
          checked: root.settings.killSwitch === true
          enabled: root.app ? root.app.tunAvailable : false
          onToggled: function (v) { root.settings.killSwitch = v }
        }
        ToggleRow {
          label: Strings.tr("settingDnsLeak")
          checked: root.settings.dnsLeakProtection !== false
          onToggled: function (v) { root.settings.dnsLeakProtection = v }
        }
        ToggleRow {
          label: Strings.tr("settingLanBypass")
          checked: root.settings.lanBypass !== false
          onToggled: function (v) { root.settings.lanBypass = v }
        }
      }

      Group {
        title: Strings.tr("settingCore")
        FieldRow {
          label: Strings.tr("settingPreferredCore")
          combo: true
          comboModel: ["auto", "xray", "sing-box"]
          comboIndex: Math.max(0, ["auto", "xray", "sing-box"].indexOf(root.settings.preferredCore || "auto"))
          onComboChanged: function (i) { root.settings.preferredCore = ["auto", "xray", "sing-box"][i] }
        }
      }

      Group {
        title: Strings.tr("settingSpeed")
        FieldRow {
          label: Strings.tr("settingRetention")
          value: root.retention
          numeric: true
          onChanged: function (v) { root.retention = v }
        }
      }

      Group {
        title: Strings.tr("subSetting")
        FieldRow {
          label: Strings.tr("subConvert")
          value: root.subConvert
          onChanged: function (v) { root.subConvert = v }
        }
      }

      Text {
        text: root.app && root.app.tunAvailable
          ? "TUN routes all traffic through sing-box using the privileged helper (pkexec). Kill switch needs the helper too."
          : Strings.tr("tunNotAvailable")
        color: Color.muted
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
        Layout.fillWidth: true
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Item { Layout.fillWidth: true }
        Button {
          text: Strings.tr("save")
          highlighted: true
          enabled: !root.saving
          onClicked: root.save()
        }
      }

      Text {
        text: Strings.tr("backupRestore")
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
      GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Style.space(8)
        rowSpacing: Style.space(8)
        ActionTile { icon: "♻"; label: Strings.tr("checkUpdateTitle"); onClicked: root.app.openCheckUpdate() }
        ActionTile { icon: "⛃"; label: Strings.tr("backupRestore"); onClicked: root.app.openBackupRestore() }
        ActionTile { icon: "↻"; label: Strings.tr("reload"); onClicked: root.app.reload() }
        ActionTile { icon: "🗑"; label: Strings.tr("clearServerStats"); onClicked: root.app.clearStatistics() }
      }

      Item { height: Style.space(8) }
    }
  }

  component FieldRow: RowLayout {
    id: fr
    property string label: ""
    property string value: ""
    property bool numeric: false
    property bool combo: false
    property var comboModel: []
    property int comboIndex: 0
    signal changed(string value)
    signal comboChanged(int index)
    Layout.fillWidth: true
    spacing: Style.space(10)

    Text {
      text: fr.label
      color: Color.muted
      font.pixelSize: Style.font.bodySmall
      Layout.preferredWidth: 130
    }
    TextField {
      visible: !fr.combo
      Layout.fillWidth: true
      text: fr.value
      validator: fr.numeric ? IntValidator { bottom: 1; top: 65535 } : null
      onTextEdited: fr.changed(text)
    }
    ComboBox {
      visible: fr.combo
      Layout.fillWidth: true
      model: fr.comboModel
      currentIndex: fr.comboIndex
      onActivated: fr.comboChanged(currentIndex)
    }
  }

  component ToggleRow: RowLayout {
    id: tr
    property string label: ""
    property bool checked: false
    signal toggled(bool value)
    Layout.fillWidth: true
    spacing: Style.space(10)

    Text {
      text: tr.label
      color: Color.foreground
      font.pixelSize: Style.font.bodySmall
      Layout.fillWidth: true
    }
    Switch {
      checked: tr.checked
      onToggled: tr.toggled(checked)
    }
  }

  component Group: Item {
    id: grp
    property string title: ""
    default property alias content: inner.children
    Layout.fillWidth: true
    Layout.preferredHeight: inner.implicitHeight + Style.space(24)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Util.alpha(Color.background, 0.35)
      border.color: Util.alpha(Color.muted, 0.3)
      border.width: 1

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(10)
        Text {
          text: grp.title
          color: Color.foreground
          font.pixelSize: Style.font.body
          font.bold: true
        }
        ColumnLayout {
          id: inner
          Layout.fillWidth: true
          spacing: Style.space(10)
        }
      }
    }
  }

  component ActionTile: Rectangle {
    id: tile
    property string icon: ""
    property string label: ""
    signal clicked()

    Layout.fillWidth: true
    Layout.preferredHeight: Style.space(44)
    radius: Style.cornerRadius
    color: tileMouse.hovered ? Util.alpha(Color.foreground, 0.07) : Util.alpha(Color.background, 0.35)
    border.color: Util.alpha(Color.muted, 0.3)
    border.width: 1

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(8)
      Text {
        text: tile.icon
        color: Color.accent
        font.pixelSize: Style.font.body
      }
      Text {
        text: tile.label
        color: Color.foreground
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: tile.clicked()
    }
  }

  function modeIndex() {
    var map = { system_proxy: 0, local: 1, tun: 2, transparent: 3 }
    var idx = map[root.settings.connectionMode]
    return idx !== undefined ? idx : 0
  }

  function modeChanged(i) {
    var modes = ["system_proxy", "local", "tun", "transparent"]
    if (i >= 2 && !root.app.tunAvailable) {
      root.app.notify(Strings.tr("tunNotAvailable"))
      return
    }
    root.settings.connectionMode = modes[i]
  }

  function save() {
    var port = parseInt(root.localPort, 10)
    if (isNaN(port) || port < 1 || port > 65535) {
      root.app.notify(Strings.tr("serverEditInvalid"))
      return
    }
    var retention = parseInt(root.retention, 10)
    var s = {
      connectionMode: root.settings.connectionMode || "system_proxy",
      preferredCore: root.settings.preferredCore || "auto",
      localPort: port,
      killSwitch: root.settings.killSwitch === true,
      dnsLeakProtection: root.settings.dnsLeakProtection !== false,
      lanBypass: root.settings.lanBypass !== false,
      healthRetentionHours: isNaN(retention) ? 24 : retention,
      subConvertUrl: root.subConvert.trim() || null
    }
    var connectedId = root.app.status.profileId || null
    if (connectedId) {
      root.app.confirm("Settings apply only while disconnected. Disconnect, save and reconnect?", function () {
        root.rpc.call("profile.disconnect", {}, function () {
          root.commit(s, connectedId)
        })
      })
      return
    }
    root.commit(s, null)
  }

  function commit(s, reconnectId) {
    root.saving = true
    root.rpc.call("settings.update", { settings: s }, function (result) {
      root.saving = false
      if (result.error) { root.app.notify(result.error); return }
      root.app.notify(Strings.tr("save") + " ✓")
      root.app.refreshAll()
      if (reconnectId) {
        root.rpc.call("profile.connect", { profileId: reconnectId }, function (res) {
          if (res.error) root.app.notify(Strings.tr("connectFailed") + ": " + res.error)
        })
      }
    })
  }
}