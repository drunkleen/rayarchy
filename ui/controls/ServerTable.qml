import QtQuick
import QtQuick.Controls
import qs.Commons
import "Common.js" as Common

// The v2rayN-style server table. Rows are read from `model` (an array of
// profile objects enriched with display fields); columns come from `columns`.
// Handles selection, hover, double-click activation, and context-menu
// plumbing. Drag reordering and column resizing are supported.
Rectangle {
  id: root

  property var model: []
  property var columns: []
  property color headerColor: Util.alpha(Color.foreground, 0.06)
  property color rowEvenColor: "transparent"
  property color rowOddColor: Util.alpha(Color.foreground, 0.025)
  property color selectedColor: Util.alpha(Color.accent, 0.16)
  property color hoverColor: Util.alpha(Color.foreground, 0.05)
  property color textColor: Color.foreground
  property color mutedColor: Color.muted
  property color borderColor: Util.alpha(Color.muted, 0.35)

  property var selectedIds: []
  property int lastSelectedIndex: -1
  property bool multiSelect: true

  signal rowActivated(var profile)
  signal rowContextMenu(var profile, int x, int y)
  signal selectionChanged(var selectedIds)
  signal columnWidthChanged(int index, int width)
  signal headerClicked(var column, int index)

  color: "transparent"
  clip: true

  function columnX(index) {
    var x = 0
    for (var i = 0; i < index; i++) x += root.columns[i].width
    return x
  }

  function totalWidth() {
    var w = 0
    for (var i = 0; i < root.columns.length; i++) w += root.columns[i].width
    return w
  }

  function isSelected(id) {
    return root.selectedIds.indexOf(id) !== -1
  }

  function setSelection(ids, lastIndex) {
    root.selectedIds = ids
    root.lastSelectedIndex = lastIndex !== undefined ? lastIndex : -1
    root.selectionChanged(root.selectedIds)
  }

  function clearSelection() {
    root.selectedIds = []
    root.lastSelectedIndex = -1
    root.selectionChanged(root.selectedIds)
  }

  function selectAll() {
    var ids = []
    for (var i = 0; i < root.model.length; i++) ids.push(root.model[i].id)
    root.setSelection(ids, root.model.length - 1)
  }

  // ---- header ----------------------------------------------------------------
  Rectangle {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.spacing.controlHeight
    color: root.headerColor

    Row {
      Repeater {
        model: root.columns
        delegate: Item {
          required property var modelData
          required property int index
          width: modelData.width
          height: header.height

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            text: modelData.label
            color: root.textColor
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Style.space(4)
            text: modelData.sortHint || ""
            color: root.mutedColor
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            onClicked: root.headerClicked(modelData, index)
          }

          // Column resize handle
          Rectangle {
            width: 1
            height: parent.height
            color: root.borderColor
            anchors.right: parent.right
            MouseArea {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.leftMargin: -2
              anchors.rightMargin: -2
              cursorShape: Qt.SizeHorCursor
              onPressed: mouse.accepted = true
              onPositionChanged: {
                if (pressed) {
                  root.columnWidthChanged(index, Math.max(48, modelData.width + mouse.x))
                  mouse.accepted = true
                }
              }
            }
          }
        }
      }
    }
  }

  // ---- rows ------------------------------------------------------------------
  ListView {
    id: list
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    model: root.model
    boundsBehavior: Flickable.StopAtBounds
    currentIndex: -1

    delegate: Item {
      required property var modelData
      required property int index
      readonly property var rowProfile: modelData
      width: list.width
      height: rowHeight
      readonly property int rowHeight: Math.max(Style.spacing.controlHeight + 2, 30)

      Rectangle {
        anchors.fill: parent
        color: root.isSelected(modelData.id)
          ? root.selectedColor
          : (index % 2 === 1 ? root.rowOddColor : root.rowEvenColor)
      }
      Rectangle {
        anchors.fill: parent
        color: root.hoverColor
        visible: hover.hovered && !root.isSelected(modelData.id)
      }

      Row {
        Repeater {
          model: root.columns
          delegate: Item {
            required property var modelData
            required property int index
            width: modelData.width
            height: parent.height

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              elide: Text.ElideRight
              font.pixelSize: Style.font.bodySmall
              text: root.cellText(modelData.key, rowProfile)
              color: root.cellColor(modelData.key, rowProfile)
              font.bold: modelData.key === "remarks" && rowProfile.default
            }
          }
        }
      }

      // "Active" tag next to the remarks for the currently connected server.
      Rectangle {
        visible: !!root.model[index].connected
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8) + root.remarksTagOffset()
        anchors.verticalCenter: parent.verticalCenter
        width: tagText.implicitWidth + Style.space(8)
        height: Style.spacing.controlHeight - 8
        radius: Style.cornerRadius
        color: Util.alpha(Color.accent, 0.25)
        Text {
          id: tagText
          anchors.centerIn: parent
          text: "●"
          color: Color.accent
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (mouse) {
          if (mouse.button === Qt.RightButton) {
            if (!root.isSelected(modelData.id)) {
              root.setSelection([modelData.id], index)
            }
            root.rowContextMenu(modelData, mouse.x, mouse.y)
            return
          }
          if (mouse.modifiers & Qt.ControlModifier) {
            var ids = root.selectedIds.slice()
            if (root.isSelected(modelData.id)) {
              var at = ids.indexOf(modelData.id)
              if (at !== -1) ids.splice(at, 1)
            } else {
              ids.push(modelData.id)
            }
            root.setSelection(ids, index)
          } else if (mouse.modifiers & Qt.ShiftModifier && root.lastSelectedIndex !== -1) {
            var lo = Math.min(root.lastSelectedIndex, index)
            var hi = Math.max(root.lastSelectedIndex, index)
            var shiftIds = []
            for (var i = lo; i <= hi; i++) shiftIds.push(root.model[i].id)
            root.setSelection(shiftIds, index)
          } else {
            root.setSelection([modelData.id], index)
          }
        }
        onDoubleClicked: root.rowActivated(modelData)
      }
    }
  }

// ---- column helpers ---------------------------------------------------------
  function remarksTagOffset() {
    var w = 0
    for (var i = 0; i < root.columns.length; i++) {
      if (root.columns[i].key === "remarks") break
      w += root.columns[i].width
    }
    return w
  }

  function cellText(key, profile) {
    switch (key) {
      case "configType": return Common.protocolLabel(profile.protocol)
      case "remarks": return Common.str(profile.name)
      case "address": return profile.server ? Common.displayAddress(profile) : ""
      case "port": return profile.port ? String(profile.port) : ""
      case "network": return Common.networkLabel(profile.fields)
      case "security": return Common.securityLabel(profile.fields)
      case "subRemarks": return Common.str(profile.subRemarks)
      case "delay": {
        var delay = profile.lastTest ? profile.lastTest.latencyMs : null
        return Common.delayText(delay)
      }
      case "speed": {
        var speed = profile.lastTest ? profile.lastTest.megabitsPerSecond : null
        return Common.speedText(speed)
      }
      case "ipInfo": return Common.str(profile.ipInfo)
      case "todayUp": return Common.formatBytes(profile.todayUp)
      case "todayDown": return Common.formatBytes(profile.todayDown)
      case "totalUp": return Common.formatBytes(profile.totalUp)
      case "totalDown": return Common.formatBytes(profile.totalDown)
    }
    return ""
  }

  function cellColor(key, profile) {
    switch (key) {
      case "configType": return Common.protocolColor(profile.protocol)
      case "delay": {
        var delay = profile.lastTest ? profile.lastTest.latencyMs : null
        return Common.delayColor(delay)
      }
      case "remarks":
        if (profile.connected) return Color.accent
        return root.textColor
    }
    return root.textColor
  }
}