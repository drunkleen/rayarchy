import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings

// v2rayN Clash Proxies panel (sing-box clash_api). Only visible while a
// sing-box connection is active.
Item {
  id: root

  property var app: null
  property var rpc: null
  property var groups: []
  property var proxies: []
  property string selectedGroup: ""
  property string mode: "rule"
  property string sortMode: "default"
  property bool testing: false

  function refresh() {
    if (!root.rpc || !root.rpc.ready) return
    root.rpc.call("clash.proxies", {}, function (result) {
      if (!result || result.error || !result.proxies) return
      root.groups = result.proxies || []
      if (result.mode) root.mode = result.mode
      root.applySort()
    })
  }

  function groupList() {
    var out = []
    for (var key in root.groups) {
      out.push({ name: key, type: root.groups[key].type, now: root.groups[key].now })
    }
    return out
  }

  function proxiesFor(groupName) {
    if (!root.groups[groupName]) return []
    var items = root.groups[groupName].all || []
    var out = []
    for (var i = 0; i < items.length; i++) {
      out.push({
        name: items[i],
        delay: root.groups[groupName].history ? root.groups[groupName].history[items[i]] : undefined,
        active: root.groups[groupName].now === items[i]
      })
    }
    return out
  }

  function applySort() {
    var list = root.proxiesFor(root.selectedGroup)
    if (root.sortMode === "name") list.sort(function (a, b) { return a.name.localeCompare(b.name) })
    else if (root.sortMode === "delay") list.sort(function (a, b) {
      var ad = a.delay !== undefined ? a.delay : 99999
      var bd = b.delay !== undefined ? b.delay : 99999
      return ad - bd
    })
    root.proxies = list
  }

  onSelectedGroupChanged: root.applySort()

  Timer {
    id: pollTimer
    interval: 4000
    repeat: true
    running: root.app && root.app.showClashUI
    onTriggered: root.refresh()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(8)
    spacing: Style.space(8)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Text { text: "Rule mode"; color: Color.muted; font.pixelSize: Style.font.bodySmall }
      ComboBox {
        id: modeCombo
        Layout.preferredWidth: 120
        model: ["rule", "global", "direct"]
        currentIndex: Math.max(0, ["rule", "global", "direct"].indexOf(root.mode))
        onActivated: {
          root.rpc.call("clash.setMode", { mode: currentText }, function () { root.refresh() })
        }
      }
      Text { text: "Sort"; color: Color.muted; font.pixelSize: Style.font.bodySmall }
      ComboBox {
        Layout.preferredWidth: 120
        model: ["default", "name", "delay"]
        currentIndex: Math.max(0, ["default", "name", "delay"].indexOf(root.sortMode))
        onActivated: { root.sortMode = currentText; root.applySort() }
      }
      Item { Layout.fillWidth: true }
      Button {
        text: Strings.tr("reload")
        flat: true
        onClicked: root.refresh()
      }
      Button {
        text: Strings.tr("realPing")
        flat: true
        enabled: !root.testing
        onClicked: root.delayTest()
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.space(8)

      // Groups
      Rectangle {
        Layout.preferredWidth: 190
        Layout.fillHeight: true
        color: Util.alpha(Color.background, 0.35)
        radius: Style.cornerRadius
        border.color: Util.alpha(Color.muted, 0.3)
        border.width: 1
        clip: true

        ListView {
          id: groupList
          anchors.fill: parent
          anchors.margins: Style.space(4)
          clip: true
          model: root.groupList()
          delegate: Row {
            required property var modelData
            width: groupList.width
            height: Style.spacing.popupRowHeight
            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: root.selectedGroup === modelData.name || hover.hovered
                ? Util.alpha(Color.foreground, 0.1) : "transparent"
            }
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              text: modelData.name
              color: Color.foreground
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: groupList.width - 70
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.rightMargin: Style.space(8)
              text: modelData.now || ""
              color: modelData.now ? Color.accent : Color.muted
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.selectedGroup = modelData.name
            }
          }
        }
      }

      // Proxies
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Util.alpha(Color.background, 0.35)
        radius: Style.cornerRadius
        border.color: Util.alpha(Color.muted, 0.3)
        border.width: 1
        clip: true

        ListView {
          id: proxyList
          anchors.fill: parent
          anchors.margins: Style.space(4)
          clip: true
          model: root.proxies
          delegate: Row {
            required property var modelData
            width: proxyList.width
            height: Style.spacing.popupRowHeight
            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: modelData.active || hover.hovered
                ? Util.alpha(modelData.active ? Color.accent : Color.foreground, modelData.active ? 0.2 : 0.08)
                : "transparent"
            }
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              text: (modelData.active ? "● " : "") + modelData.name
              color: modelData.active ? Color.accent : Color.foreground
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: proxyList.width - 110
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.rightMargin: Style.space(8)
              text: modelData.delay !== undefined ? modelData.delay + " ms" : ""
              color: modelData.delay !== undefined && modelData.delay <= 500 ? "#50fa7b" : Color.muted
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function (mouse) {
                if (mouse.button === Qt.RightButton) {
                  root.app.contextMenu([
                    { label: Strings.tr("realPing"), action: "delay" },
                    { label: Strings.tr("setDefaultServer"), action: "select" }
                  ], mouse.x, mouse.y, function (item) {
                    if (item.action === "select") root.selectProxy(modelData.name)
                    else root.delayTestOne(modelData.name)
                  })
                } else {
                  root.selectProxy(modelData.name)
                }
              }
            }
          }
        }
      }
    }
  }

  function selectProxy(name) {
    if (!root.selectedGroup) return
    root.rpc.call("clash.select", { group: root.selectedGroup, proxy: name }, function () { root.refresh() })
  }

  function delayTest() {
    root.testing = true
    root.rpc.call("clash.proxies", {}, function () { root.testing = false })
  }

  function delayTestOne(name) {
    root.rpc.call("clash.proxies", {}, function () {})
  }
}