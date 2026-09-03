import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings
import "../controls"

// v2rayN Check Update: lists installed vs latest for cores and geo files,
// with per-row install buttons. Downloads are SHA-256 verified server-side.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property var info: ({})
  property bool checking: false
  property string working: ""
  property var rows: []

  title: Strings.tr("checkUpdateTitle")
  width: Math.min(parent ? parent.width * 0.58 : 640, 680)
  height: Math.min(parent ? parent.height * 0.62 : 520, 560)

  Component.onCompleted: dialog.check()

  function check() {
    dialog.checking = true
    dialog.rpc.call("update.check", {}, function (result) {
      dialog.checking = false
      dialog.info = result || {}
      var out = []
      var installed = result.installed || {}
      var latest = result.latest || {}
      out.push({ id: "xray", label: "Xray", installed: installed.xray || "", latest: latest.xray || "" })
      out.push({ id: "sing-box", label: "sing-box", installed: installed["sing-box"] || "", latest: latest["sing-box"] || "" })
      out.push({ id: "geoip.dat", label: "GeoIP", installed: installed["geoip.dat"] ? Strings.tr("coreInstalled") : Strings.tr("coreMissing"), latest: latest.geo || "" })
      out.push({ id: "geosite.dat", label: "GeoSite", installed: installed["geosite.dat"] ? Strings.tr("coreInstalled") : Strings.tr("coreMissing"), latest: latest.geo || "" })
      dialog.rows = out
    })
  }

  function install(row) {
    if (!row.latest || row.latest === "") { dialog.app.notify("No release found"); return }
    dialog.working = row.id
    var version = (row.id === "geoip.dat" || row.id === "geosite.dat") ? "" : row.latest
    dialog.rpc.call("update.install", { target: row.id, version: version }, function (result) {
      dialog.working = ""
      if (result.error) dialog.app.notify("Update: " + result.error)
      else dialog.app.notify(row.id + " updated ✓")
      dialog.check()
    })
  }

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        text: dialog.checking ? Strings.tr("loading") + "…" : Strings.tr("checkUpdateTitle")
        color: Color.foreground
        font.pixelSize: Style.font.title
        font.bold: true
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
          model: dialog.rows
          delegate: Row {
            required property var modelData
            width: parent ? parent.width : 0
            height: Style.spacing.popupRowHeight + 4
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: 110
              leftPadding: Style.space(8)
              text: modelData.label
              color: Color.foreground
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: 150
              text: modelData.installed
              color: modelData.installed && modelData.installed !== Strings.tr("coreMissing")
                ? Color.accent : Color.urgent
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: 150
              text: modelData.latest
              color: Color.muted
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Item { Layout.fillWidth: true }
            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: dialog.working === modelData.id ? Strings.tr("loading") + "…" : Strings.tr("checkUpdateNow")
              flat: true
              enabled: dialog.working === "" && modelData.latest !== ""
              onClicked: dialog.install(modelData)
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Item { Layout.fillWidth: true }
        Button { text: Strings.tr("close"); flat: true; onClicked: dialog.closeRequested() }
      }
    }
  }
}