import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings

// DNS settings: protection toggle + direct/remote/bootstrap resolvers.
Item {
  id: root

  property var app: null
  property var rpc: null
  property var status: ({})

  property var settings: ({})
  property string directDns: "223.5.5.5"
  property string remoteDns: "https://1.1.1.1/dns-query"
  property string bootstrapDns: "8.8.8.8"
  property bool dnsProtect: true
  property bool saving: false

  function refresh() {
    if (!root.rpc || !root.rpc.ready) return
    root.rpc.call("settings.get", {}, function (s) {
      root.settings = s || {}
      root.directDns = (s && s.dns && s.dns.direct) || "223.5.5.5"
      root.remoteDns = (s && s.dns && s.dns.remote) || "https://1.1.1.1/dns-query"
      root.bootstrapDns = (s && s.dns && s.dns.bootstrap) || "8.8.8.8"
      root.dnsProtect = s ? s.dnsLeakProtection !== false : true
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
        title: Strings.tr("dnsSimple")
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)
          Text {
            text: Strings.tr("settingDnsLeak")
            color: Color.foreground
            font.pixelSize: Style.font.bodySmall
            Layout.fillWidth: true
          }
          Switch {
            checked: root.dnsProtect
            onToggled: root.dnsProtect = checked
          }
        }
        FieldRow { label: Strings.tr("dnsDirect"); value: root.directDns; onChanged: function (v) { root.directDns = v } }
        FieldRow { label: Strings.tr("dnsRemote"); value: root.remoteDns; onChanged: function (v) { root.remoteDns = v } }
        FieldRow { label: Strings.tr("dnsBootstrap"); value: root.bootstrapDns; onChanged: function (v) { root.bootstrapDns = v } }
      }

      Text {
        text: Strings.tr("dnsSystemHosts") + " / FakeIP are applied automatically from core defaults."
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

      Item { height: Style.space(8) }
    }
  }

  component FieldRow: RowLayout {
    id: fr
    property string label: ""
    property string value: ""
    signal changed(string value)
    Layout.fillWidth: true
    spacing: Style.space(10)

    Text {
      text: fr.label
      color: Color.muted
      font.pixelSize: Style.font.bodySmall
      Layout.preferredWidth: 120
    }
    TextField {
      Layout.fillWidth: true
      text: fr.value
      onTextEdited: fr.changed(text)
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

  function save() {
    var s = {
      dnsLeakProtection: root.dnsProtect,
      dns: {
        direct: root.directDns.trim() || "223.5.5.5",
        remote: root.remoteDns.trim() || "https://1.1.1.1/dns-query",
        bootstrap: root.bootstrapDns.trim() || "8.8.8.8",
        systemHosts: true
      }
    }
    root.saving = true
    root.rpc.call("settings.update", { settings: s }, function (result) {
      root.saving = false
      if (result.error) { root.app.notify(result.error); return }
      root.app.notify(Strings.tr("save") + " ✓")
    })
  }
}