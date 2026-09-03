import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings
import "../controls"

// v2rayN Routing Setting. Phase 1 exposes the single active rule set; named
// routing configs and remote templates arrive with Phase 2.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property var rules: []
  property var editingRule: null

  title: Strings.tr("routingSetting")
  width: Math.min(parent ? parent.width * 0.66 : 780, 820)
  height: Math.min(parent ? parent.height * 0.7 : 580, 620)

  Component.onCompleted: dialog.refresh()
  function refresh() {
    if (!dialog.rpc) return
    dialog.rpc.call("routing.list", {}, function (rows) {
      dialog.rules = rows || []
    })
  }

  function addRule() {
    dialog.editingRule = null
    editor.open()
  }
  function editRule(rule) {
    dialog.editingRule = rule
    editor.open()
  }
  function deleteRule(id) {
    dialog.app.confirm(Strings.tr("routingDeleteRule") + "?", function () {
      dialog.rpc.call("routing.delete", { ruleId: id }, function () { dialog.refresh() })
    })
  }

  function importPreset() {
    dialog.rpc.call("routing.presets", {}, function (result) {
      if (!result || !result.presets) return
      dialog.app.contextMenu(result.presets.map(function (p) {
        return { label: p.name, action: p.id, description: p.description || "" }
      }), 90, 40, function (item) {
        dialog.app.confirm("Import " + item.label + "?", function () {
          dialog.rpc.call("routing.importPreset", { presetId: item.action }, function (res) {
            if (res.error) dialog.app.notify(res.error)
            else dialog.app.notify(item.label + " ✓")
            dialog.refresh()
          })
        })
      })
    })
  }
  function saveRule(rule) {
    // Editing is delete+recreate (the backend has no routing.update yet).
    var done = function () {
      dialog.rpc.call("routing.create", { rule: rule }, function (result) {
        if (result.error) dialog.app.notify(result.error)
        dialog.refresh()
      })
    }
    if (dialog.editingRule) dialog.rpc.call("routing.delete", { ruleId: rule.id }, done)
    else done()
  }

  content: Component {
    Item {
      anchors.fill: parent

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(8)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Button { text: Strings.tr("routingAddRule"); flat: true; onClicked: dialog.addRule() }
          Button { text: Strings.tr("importFromClipboard"); flat: true; onClicked: dialog.importPreset() }
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
            id: list
            anchors.fill: parent
            anchors.margins: Style.space(4)
            clip: true
            model: dialog.rules
            delegate: Row {
              required property var modelData
              required property int index
              width: list.width
              height: Style.spacing.popupRowHeight
              spacing: Style.space(6)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: hover.hovered ? Util.alpha(Color.foreground, 0.07) : "transparent"
              }

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                width: 90
                text: modelData.matchType
                color: Color.accent
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(110)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(160)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: modelData.name + " — " + modelData.value
                color: Color.foreground
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(70)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.action
                color: modelData.action === "block" ? Color.urgent : (modelData.action === "direct" ? Color.muted : Color.accent)
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.enabled ? "" : Strings.tr("disabled")
                color: Color.muted
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function (mouse) {
                  if (mouse.button === Qt.RightButton) {
                    dialog.app.contextMenu([
                      { label: Strings.tr("editServer"), action: "edit" },
                      { label: Strings.tr("delete"), action: "delete" }
                    ], mouse.x, mouse.y, function (item) {
                      if (item.action === "edit") dialog.editRule(modelData)
                      else dialog.deleteRule(modelData.id)
                    })
                  } else {
                    dialog.editRule(modelData)
                  }
                }
              }
            }
          }
        }
      }

      RoutingRuleEditor {
        id: editor
        anchors.fill: parent
        rpc: dialog.rpc
        app: dialog.app
        rule: dialog.editingRule
        onSave: function (rule) { dialog.saveRule(rule) }
      }
    }
  }
}