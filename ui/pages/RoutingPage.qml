import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings

// Routing rules: list + add/edit inline + import presets.
Item {
  id: root

  property var app: null
  property var rpc: null
  property var status: ({})

  property var rules: []
  property var presets: []
  property var editing: null   // rule object or null for new
  property string editName: ""
  property string editMatchType: "domain"
  property string editValue: ""
  property string editAction: "proxy"
  property bool editEnabled: true

  function refresh() {
    if (!root.rpc || !root.rpc.ready) return
    root.rpc.call("routing.list", {}, function (rows) {
      root.rules = rows || []
    })
    root.rpc.call("routing.presets", {}, function (p) {
      root.presets = (p && p.presets) || []
    })
  }

  Component.onCompleted: root.refresh()

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)
      Layout.topMargin: Style.space(8)
      Layout.leftMargin: Style.space(8)
      Layout.rightMargin: Style.space(8)
      Layout.bottomMargin: Style.space(6)

      Button {
        text: "＋"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight + 2
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("routingAddRule")
        ToolTip.visible: hovered
        onClicked: root.startNew()
      }
      Item { Layout.fillWidth: true }
      ComboBox {
        id: presetCombo
        Layout.preferredWidth: 160
        Layout.preferredHeight: Style.spacing.controlHeight
        textRole: "name"
        valueRole: "id"
        model: root.presets
        displayText: {
          var idx = currentIndex
          if (idx >= 0 && idx < root.presets.length) return "Preset: " + root.presets[idx].name
          return "Import preset…"
        }
        onActivated: {
          if (currentIndex >= 0 && currentIndex < root.presets.length) {
            root.importPreset(root.presets[currentIndex].id)
            currentIndex = -1
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Util.alpha(Color.muted, 0.25)
    }

    // rule list
    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: "transparent"

      ListView {
        anchors.fill: parent
        anchors.margins: Style.space(6)
        clip: true
        model: root.rules
        spacing: 2
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: RuleRow {
          required property var modelData
          rule: modelData
          onClicked: root.startEdit(modelData)
          onDeleteRequested: root.deleteRule(modelData.id)
        }
      }

      Column {
        anchors.centerIn: parent
        visible: root.rules.length === 0
        spacing: Style.space(8)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "No routing rules — traffic uses the default route."
          color: Color.muted
          font.pixelSize: Style.font.body
        }
      }
    }

    // inline editor
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: root.editing !== null ? editColumn.implicitHeight + Style.space(20) : 0
      color: Util.alpha(Color.background, 0.5)
      border.color: Util.alpha(Color.accent, 0.4)
      border.width: 1
      radius: Style.cornerRadius
      visible: root.editing !== null

      ColumnLayout {
        id: editColumn
        anchors.fill: parent
        anchors.margins: Style.space(10)
        spacing: Style.space(8)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          TextField {
            Layout.fillWidth: true
            placeholderText: Strings.tr("name")
            text: root.editName
            onTextEdited: root.editName = text
          }
          ComboBox {
            Layout.preferredWidth: 150
            model: ["domain", "domain_suffix", "domain_keyword", "cidr", "ip"]
            currentIndex: Math.max(0, ["domain", "domain_suffix", "domain_keyword", "cidr", "ip"].indexOf(root.editMatchType))
            onActivated: root.editMatchType = currentText
          }
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          TextField {
            Layout.fillWidth: true
            placeholderText: Strings.tr("routingValue") + " (e.g. example.com / 1.2.3.0/24)"
            text: root.editValue
            onTextEdited: root.editValue = text
          }
          ComboBox {
            Layout.preferredWidth: 120
            model: ["proxy", "direct", "block"]
            currentIndex: Math.max(0, ["proxy", "direct", "block"].indexOf(root.editAction))
            onActivated: root.editAction = currentText
          }
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          CheckBox {
            text: Strings.tr("enabled")
            checked: root.editEnabled
            onCheckedChanged: root.editEnabled = checked
          }
          Item { Layout.fillWidth: true }
          Button { text: Strings.tr("cancel"); flat: true; onClicked: root.editing = null }
          Button {
            text: Strings.tr("save")
            highlighted: true
            onClicked: root.saveRule()
          }
        }
      }
    }
  }

  component RuleRow: Item {
    id: row
    property var rule: ({})
    signal clicked()
    signal deleteRequested()

    implicitHeight: Style.space(34)
    width: parent ? parent.width : 0

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: mouse.hovered ? Util.alpha(Color.foreground, 0.05) : "transparent"
    }
    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)
      Text {
        text: row.rule.name || ""
        color: Color.foreground
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
      Text {
        text: row.rule.matchType || ""
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
      Text {
        text: row.rule.value || ""
        color: Color.muted
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Text {
        text: row.rule.action || ""
        color: row.rule.action === "block" ? Color.urgent : (row.rule.action === "direct" ? Color.muted : Color.accent)
        font.pixelSize: Style.font.caption
      }
      Text {
        text: row.rule.enabled === false ? Strings.tr("disabled") : ""
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
      Button {
        text: "✕"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight
        Layout.preferredHeight: Style.spacing.controlHeight
        onClicked: row.deleteRequested()
      }
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: row.clicked()
    }
  }

  function startNew() {
    root.editing = {}
    root.editName = ""
    root.editMatchType = "domain"
    root.editValue = ""
    root.editAction = "proxy"
    root.editEnabled = true
  }

  function startEdit(rule) {
    root.editing = rule
    root.editName = rule.name || ""
    root.editMatchType = rule.matchType || "domain"
    root.editValue = rule.value || ""
    root.editAction = rule.action || "proxy"
    root.editEnabled = rule.enabled !== false
  }

  function saveRule() {
    if (!root.editValue.trim()) { root.app.notify(Strings.tr("serverEditInvalid")); return }
    var rule = {
      name: root.editName.trim() || root.editValue.trim(),
      matchType: root.editMatchType,
      value: root.editValue.trim(),
      action: root.editAction,
      enabled: root.editEnabled
    }
    if (root.editing && root.editing.id) {
      // update via delete+create (routing.update is not exposed)
      root.rpc.call("routing.delete", { ruleId: root.editing.id }, function () {
        root.rpc.call("routing.create", { rule: rule }, function () {
          root.editing = null
          root.app.notify(Strings.tr("save") + " ✓")
          root.refresh()
        })
      })
    } else {
      root.rpc.call("routing.create", { rule: rule }, function () {
        root.editing = null
        root.app.notify(Strings.tr("save") + " ✓")
        root.refresh()
      })
    }
  }

  function deleteRule(id) {
    root.app.confirm(Strings.tr("routingDeleteRule") + "?", function () {
      root.rpc.call("routing.delete", { ruleId: id }, function () { root.refresh() })
    })
  }

  function importPreset(presetId) {
    root.app.confirm("Import preset rules?", function () {
      root.rpc.call("routing.importPreset", { presetId: presetId }, function (result) {
        if (result.error) root.app.notify(result.error)
        else root.app.notify("Imported " + (result.imported || 0) + " rules ✓")
        root.refresh()
      })
    })
  }
}