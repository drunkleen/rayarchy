import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import "../strings.js" as Strings
import "../controls"

// v2rayN Backup & Restore. Phase 1 does local export of the daemon state to a
// JSON file; import via the FileBrowser sheet. Remote (WebDAV) arrives later.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property bool working: false
  property string statusText: ""

  title: Strings.tr("backupTitle")
  width: Math.min(parent ? parent.width * 0.5 : 560, 580)
  height: Math.min(parent ? parent.height * 0.5 : 400, 440)

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(14)

      Text {
        text: Strings.tr("backupTitle")
        color: Color.foreground
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Button {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.spacing.controlHeight + 8
        text: Strings.tr("backupExport")
        enabled: !dialog.working
        onClicked: dialog.exportBackup()
      }
      Button {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.spacing.controlHeight + 8
        text: Strings.tr("backupImport")
        enabled: !dialog.working
        onClicked: dialog.importBackup()
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Button {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.spacing.controlHeight + 4
          text: Strings.tr("clearServerStats")
          onClicked: { dialog.app.clearStatistics(); dialog.closeRequested() }
        }
        Button {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.spacing.controlHeight + 4
          text: Strings.tr("openFileLocation")
          onClicked: { dialog.app.openFileLocation(); dialog.closeRequested() }
        }
      }

      Text {
        Layout.fillWidth: true
        text: dialog.statusText
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      Item { Layout.fillHeight: true }

      RowLayout {
        Layout.fillWidth: true
        Button { text: Strings.tr("close"); flat: true; onClicked: dialog.closeRequested() }
      }
    }
  }

  function exportBackup() {
    if (!dialog.rpc) return
    dialog.working = true
    dialog.statusText = Strings.tr("loading") + "…"
    dialog.rpc.call("backup.export", {}, function (result) {
      dialog.working = false
      var json = JSON.stringify(result.state || {}, null, 2)
      var path = Quickshell.env("HOME") + "/rayarchy-backup-" + Date.now() + ".json"
      dialog.writeFile(path, json, function (ok) {
        dialog.statusText = ok ? path : "Failed to write backup"
      })
    })
  }

  function importBackup() {
    dialog.app.sheetHost.open(Qt.createComponent("../dialogs/FileBrowser.qml"), {
      rpc: dialog.rpc, app: dialog.app, mode: "json",
      onPicked: function (path) { dialog.importFromFile(path) },
      title: Strings.tr("backupImport")
    })
  }

  function importFromFile(path) {
    dialog.working = true
    var f = Qt.createQmlObject("import Quickshell.Io; File { }", dialog, "backupImportFile")
    f.path = path
    var text = f.text || ""
    var state = null
    try { state = JSON.parse(text) } catch (e) { state = null }
    f.destroy()
    dialog.working = false
    if (!state) {
      dialog.statusText = "Invalid backup file"
      return
    }
    dialog.app.confirm(Strings.tr("confirm") + "?", function () {
      dialog.rpc.call("backup.import", { state: state }, function (result) {
        if (result.error) dialog.statusText = result.error
        else {
          dialog.statusText = Strings.tr("backupRestored") + " ✓"
          dialog.app.refreshAll()
        }
      })
    })
  }

  function writeFile(path, contents, cb) {
    var f = Qt.createQmlObject("import Quickshell.Io; File { }", dialog, "backupExportFile")
    f.path = path
    f.setText(contents)
    f.save()
    var ok = !f.saveFailed
    f.destroy()
    cb(ok)
  }
}