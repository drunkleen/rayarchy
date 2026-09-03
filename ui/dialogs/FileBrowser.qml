import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import "../strings.js" as Strings
import "../controls"

// Minimal inline file browser used wherever v2rayN would open a native file
// dialog. Directory listings come from `ls`, so no extra QML modules are
// needed; the picked path is handed to `onPicked`.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property string mode: "file"     // "image" | "json" | "file"
  property var onPicked: null
  property string dir: Quickshell.env("HOME")
  property var entries: []
  property bool listing: false

  title: Strings.tr("more") + " — " + dialog.mode
  width: Math.min(parent ? parent.width * 0.55 : 620, 660)
  height: Math.min(parent ? parent.height * 0.6 : 500, 540)

  Component.onCompleted: dialog.reload()

  function extensions() {
    if (dialog.mode === "image") return [".png", ".jpg", ".jpeg", ".gif", ".webp"]
    if (dialog.mode === "json") return [".json"]
    return []
  }

  function reload() {
    if (dialog.listing) return
    dialog.listing = true
    lsProc.command = "ls -a -p " + Util.shellQuote(dialog.dir)
    lsProc.running = true
  }

  Process {
    id: lsProc
    onExited: function (exitCode, exitStatus) {
      dialog.listing = false
      var out = []
      var stdout = lsProc.stdout
      if (exitCode === 0 && stdout) {
        var lines = stdout.split("\n")
        var exts = dialog.extensions()
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim()
          if (!name || name === "." || name === "..") continue
          var isDir = name.charAt(name.length - 1) === "/"
          var clean = isDir ? name.slice(0, -1) : name
          if (!isDir) {
            var lower = clean.toLowerCase()
            var match = exts.length === 0
            for (var j = 0; j < exts.length; j++) {
              if (lower.indexOf(exts[j]) === lower.length - exts[j].length) { match = true; break }
            }
            if (!match) continue
          }
          out.push({ name: clean, isDir: isDir })
        }
        out.sort(function (a, b) {
          if (a.isDir && !b.isDir) return -1
          if (!a.isDir && b.isDir) return 1
          return a.name.localeCompare(b.name)
        })
      }
      dialog.entries = out
    }
  }

  function pick(name) {
    var path = dialog.dir === "/" ? "/" + name : dialog.dir + "/" + name
    if (name.indexOf("/") === 0) path = name
    if (dialog.onPicked) dialog.onPicked(path)
    dialog.closeRequested()
  }

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Button { text: "‹"; flat: true; onClicked: dialog.up() }
        Button { text: "↻"; flat: true; onClicked: dialog.reload() }
        TextField {
          Layout.fillWidth: true
          text: dialog.dir
          onEditingFinished: {
            var t = text
            if (t && t.length > 0) { dialog.dir = t; dialog.reload() }
          }
        }
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
          model: dialog.entries
          delegate: Row {
            required property var modelData
            required property int index
            width: list.width
            height: Style.spacing.popupRowHeight

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: hover.hovered ? Util.alpha(Color.foreground, 0.07) : "transparent"
            }
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              text: (modelData.isDir ? "▸ " : "· ") + modelData.name
              color: modelData.isDir ? Color.accent : Color.foreground
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: list.width - 20
            }
            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              onDoubleClicked: {
                if (modelData.isDir) {
                  dialog.dir = dialog.dir === "/" ? "/" + modelData.name : dialog.dir + "/" + modelData.name
                  dialog.reload()
                } else {
                  dialog.pick(modelData.name)
                }
              }
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Item { Layout.fillWidth: true }
        Button { text: Strings.tr("cancel"); flat: true; onClicked: dialog.closeRequested() }
      }
    }
  }

  function up() {
    var parts = dialog.dir.replace(/\/+$/, "").split("/")
    parts.pop()
    dialog.dir = parts.join("/") || "/"
    dialog.reload()
  }
}