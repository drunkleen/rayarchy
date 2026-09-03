import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings

// Minimal top bar: one menu button that opens the full menu through the app's
// ContextMenu overlay (the same mechanism as right-click menus), plus a reload
// and close quick action. Everything renders inside the window.
Item {
  id: root

  property var app: null
  property color textColor: Color.foreground
  signal reloadRequested()
  signal closeRequested()

  height: Style.spacing.controlHeight + Style.space(10)

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(6)

    // App title + menu button
    Button {
      id: menuButton
      flat: true
      Layout.preferredHeight: Style.spacing.controlHeight
      text: "⛨  Rayarchy"
      font.pixelSize: Style.font.body
      onClicked: root.openMenu()
      ToolTip.text: Strings.tr("menuServers")
      ToolTip.visible: hovered
    }

    Item { Layout.fillWidth: true }

    Button {
      flat: true
      Layout.preferredWidth: Style.spacing.controlHeight + 2
      Layout.preferredHeight: Style.spacing.controlHeight
      text: "⟳"
      onClicked: root.reloadRequested()
      ToolTip.text: Strings.tr("menuReload")
      ToolTip.visible: hovered
    }
    Button {
      flat: true
      Layout.preferredWidth: Style.spacing.controlHeight + 2
      Layout.preferredHeight: Style.spacing.controlHeight
      text: "✕"
      onClicked: root.closeRequested()
      ToolTip.text: Strings.tr("menuClose")
      ToolTip.visible: hovered
    }
  }

  function openMenu() {
    if (!root.app || !root.app.contextMenu || !root.app.windowContent) return
    var pos = menuButton.mapToItem(root.app.windowContent, 0, menuButton.height + 4)
    root.app.contextMenu(root.app.menuItems, pos.x, pos.y, function (item) {
      if (item && item.action) root.app.handleMenu(item)
    })
  }
}