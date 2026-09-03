import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings

// Inline editor for a single routing rule (add/edit), hosted inside the
// RoutingSetting sheet.
Item {
  id: root

  property var rpc: null
  property var app: null
  property var rule: null
  signal save(var rule)

  property bool open: false
  property string name: ""
  property string matchType: "domain"
  property string value: ""
  property string action: "proxy"
  property bool enabled: true

  Rectangle {
    anchors.fill: parent
    visible: root.open
    z: 50
    color: Util.alpha(Color.background, 0.94)
    radius: Style.cornerRadius
    border.color: Color.muted
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.space(14)
      spacing: Style.space(10)

      Text {
        text: Strings.tr("routingRule")
        color: Color.foreground
        font.pixelSize: Style.font.title
        font.bold: true
      }

      GridLayout {
        columns: 2
        columnSpacing: Style.space(10)
        rowSpacing: Style.space(8)
        Layout.fillWidth: true

        Text { text: Strings.tr("name"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          Layout.fillWidth: true
          text: root.name
          onTextEdited: root.name = text
        }
        Text { text: Strings.tr("routingMatchType"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        ComboBox {
          Layout.fillWidth: true
          model: ["domain", "domain_suffix", "domain_keyword", "cidr", "ip"]
          currentIndex: Math.max(0, ["domain", "domain_suffix", "domain_keyword", "cidr", "ip"].indexOf(root.matchType))
          onActivated: root.matchType = currentText
        }
        Text { text: Strings.tr("routingValue"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          Layout.fillWidth: true
          text: root.value
          placeholderText: "example.com or 192.168.0.0/16"
          onTextEdited: root.value = text
        }
        Text { text: Strings.tr("routingAction"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        ComboBox {
          Layout.fillWidth: true
          model: ["proxy", "direct", "block"]
          currentIndex: Math.max(0, ["proxy", "direct", "block"].indexOf(root.action))
          onActivated: root.action = currentText
        }
        Text { text: Strings.tr("enabled"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        CheckBox {
          checked: root.enabled
          onCheckedChanged: root.enabled = checked
        }
      }

      Item { Layout.fillHeight: true }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Item { Layout.fillWidth: true }
        Button { text: Strings.tr("cancel"); flat: true; onClicked: root.open = false }
        Button {
          text: Strings.tr("save")
          highlighted: true
          onClicked: {
            if (!root.value.trim()) { root.app.notify(Strings.tr("serverEditInvalid")); return }
            root.save({
              id: root.rule ? root.rule.id : undefined,
              name: root.name.trim() || root.matchType + " rule",
              matchType: root.matchType,
              value: root.value.trim(),
              action: root.action,
              enabled: root.enabled
            })
            root.open = false
          }
        }
      }
    }
  }

  function open() {
    root.name = root.rule ? (root.rule.name || "") : ""
    root.matchType = root.rule ? root.rule.matchType : "domain"
    root.value = root.rule ? (root.rule.value || "") : ""
    root.action = root.rule ? (root.rule.action || "proxy") : "proxy"
    root.enabled = root.rule ? root.rule.enabled !== false : true
    root.open = true
  }
}