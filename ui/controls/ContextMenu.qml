import QtQuick
import QtQuick.Controls
import qs.Commons

// Inline context menu / dropdown. Shown at a position inside the window;
// supports separators, checked items, and one submenu level. The root fills
// the window so an outside click closes it; the panel is positioned with its
// own x/y (the root cannot be moved, it is anchored).
Item {
  id: root

  property var items: []
  property var callback: null
  property color surfaceColor: Color.popups.background
  property color surfaceText: Color.popups.text
  property color surfaceBorder: Color.popups.border

  visible: false
  z: 500

  property int panelX: 0
  property int panelY: 0

  function showAt(x, y, items, callback) {
    root.items = items
    root.callback = callback
    root.panelX = x
    root.panelY = y
    root.submenuVisible = false
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
    if (root.panelX + panel.width > w) root.panelX = Math.max(0, w - panel.width)
    if (root.panelY + panel.height > h) root.panelY = Math.max(0, h - panel.height)
  }

  property bool submenuVisible: false
  property var submenuItems: []
  property int submenuRowY: 0

  // Backdrop: below the panel (declared first), closes on outside click.
  MouseArea {
    anchors.fill: parent
    anchors.margins: -4
    onClicked: root.hide()
  }

  Rectangle {
    id: panel
    x: root.panelX
    y: root.panelY
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
          onSubmenuCleared: root.submenuVisible = false
        }
      }
    }
  }

  Rectangle {
    id: submenuPanel
    visible: root.submenuVisible
    width: Style.space(250)
    implicitHeight: submenuContents.count * Style.spacing.popupRowHeight + Style.space(8)
    x: {
      var right = root.panelX + panel.width - Style.space(4) + width
      var limit = root.parent ? root.parent.width : 1280
      if (right > limit) return Math.max(0, root.panelX - width + Style.space(4))
      return root.panelX + panel.width - Style.space(4)
    }
    y: {
      var bottom = root.panelY + root.submenuRowY + implicitHeight
      var limit = root.parent ? root.parent.height : 820
      if (bottom > limit) return Math.max(0, limit - implicitHeight)
      return root.panelY + root.submenuRowY
    }
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
    signal submenuCleared()

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
        if (item.submenu && item.submenu.length) {
          row.submenuRequested(item, row.mapToItem(panel, 0, 0).y)
        } else {
          row.submenuCleared()
        }
      }
      onExited: row.hovered = false
      onClicked: {
        if (item.separator) return
        if (item.enabled === false) return
        if (item.submenu && item.submenu.length) return
        row.triggered(item)
      }
    }
  }
}