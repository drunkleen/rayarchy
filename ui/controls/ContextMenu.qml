import QtQuick
import QtQuick.Controls
import qs.Commons

// Inline right-click context menu. Shown at an absolute position inside the
// window; supports separators, checked items, and one submenu level.
Item {
  id: root

  property var items: []
  property var callback: null
  property color surfaceColor: Color.popups.background
  property color surfaceText: Color.popups.text
  property color surfaceBorder: Color.popups.border

  visible: false
  z: 500

  function showAt(x, y, items, callback) {
    root.x = x
    root.y = y
    root.items = items
    root.callback = callback
    root.visible = true
    root.clampToWindow()
  }

  function hide() {
    root.visible = false
    root.submenuVisible = false
  }

  function clampToWindow() {
    var w = root.parent ? root.parent.width : 1280
    var h = root.parent ? root.parent.height : 820
    if (root.x + panel.width > w) root.x = Math.max(0, w - panel.width)
    if (root.y + panel.height > h) root.y = Math.max(0, h - panel.height)
  }

  property bool submenuVisible: false
  property var submenuItems: []
  property int submenuRowY: 0

  MouseArea {
    anchors.fill: parent
    anchors.margins: -4
    onClicked: { }
  }

  Rectangle {
    id: panel
    width: Math.max(contents.implicitWidth, Style.space(230))
    implicitHeight: contents.count * Style.spacing.popupRowHeight + Style.space(8)
    color: root.surfaceColor
    border.color: root.surfaceBorder
    border.width: 1
    radius: Style.cornerRadius

    Column {
      id: contents
      anchors.fill: parent
      anchors.margins: Style.space(4)
      spacing: 0
      Repeater {
        model: root.items
        delegate: ContextRow {
          required property var modelData
          item: modelData
          onTriggered: function (item) {
            root.hide()
            if (root.callback) root.callback(item)
          }
          onSubmenuRequested: function (item, rowY) {
            root.submenuItems = item.submenu
            root.submenuRowY = rowY
            root.submenuVisible = true
          }
        }
      }
    }
  }

  Rectangle {
    id: submenuPanel
    visible: root.submenuVisible
    width: Style.space(250)
    implicitHeight: submenuContents.count * Style.spacing.popupRowHeight + Style.space(8)
    x: panel.width - Style.space(4)
    y: root.submenuRowY
    color: root.surfaceColor
    border.color: root.surfaceBorder
    border.width: 1
    radius: Style.cornerRadius

    Column {
      id: submenuContents
      anchors.fill: parent
      anchors.margins: Style.space(4)
      Repeater {
        model: root.submenuItems
        delegate: ContextRow {
          required property var modelData
          item: modelData
          onTriggered: function (item) {
            root.hide()
            if (root.callback) root.callback(item)
          }
        }
      }
    }
  }

  component ContextRow: Item {
    id: row
    property var item: ({})
    property bool hovered: false
    signal triggered(var item)
    signal submenuRequested(var item, int rowY)

    width: parent.width
    height: item.separator ? Style.space(9) : Style.spacing.popupRowHeight

    Rectangle {
      anchors.fill: parent
      visible: !item.separator
      radius: Style.cornerRadius
      color: row.hovered ? Util.alpha(root.surfaceText, 0.08) : "transparent"
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: 1
      color: root.surfaceBorder
      visible: !!item.separator
      opacity: 0.5
    }

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      text: item.label || ""
      color: item.enabled === false ? Util.alpha(root.surfaceText, 0.4) : root.surfaceText
      font.pixelSize: Style.font.body
      visible: !item.separator
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: Style.space(8)
      text: item.submenu && item.submenu.length ? "›" : (item.checked ? "✓" : "")
      color: root.surfaceText
      font.pixelSize: Style.font.body
      visible: !item.separator
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: {
        row.hovered = true
        if (item.submenu && item.submenu.length) row.submenuRequested(item, row.mapToItem(root, 0, 0).y)
      }
      onExited: {
        row.hovered = false
        if (item.submenu && item.submenu.length) root.submenuVisible = false
      }
      onClicked: {
        if (item.separator) return
        if (item.enabled === false) return
        if (item.submenu && item.submenu.length) return
        row.triggered(item)
      }
    }
  }
}