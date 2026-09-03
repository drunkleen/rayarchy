import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

// Minimal top menu bar replicating v2rayN's main menu structure. Menus open
// as inline dropdown panels anchored to their button; submenus open to the
// side. Everything renders inside the window.
Item {
  id: root

  property var items: []      // [{label, icon, action, enabled, checked, separator, submenu}]
  property color textColor: Color.foreground
  property color surfaceColor: Color.popups.background
  property color surfaceText: Color.popups.text
  property color surfaceBorder: Color.popups.border

  signal itemActivated(var item)

  height: Style.spacing.controlHeight + Style.space(8)

  RowLayout {
    id: menuRow
    anchors.fill: parent
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(2)

    Repeater {
      model: root.items
      delegate: MenuButton {
        required property var modelData
        label: modelData.label
        enabled: modelData.enabled !== false
        textColor: root.textColor
        onActivated: function (item) { root.itemActivated(item) }
      }
    }
  }

  component MenuButton: Item {
    id: button
    property string label: ""
    property color textColor: Color.foreground
    property bool open: false
    signal activated(var item)

    width: menuLabel.implicitWidth + Style.space(18)
    height: parent.height

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: button.open || hover.hovered
        ? Util.alpha(Color.foreground, 0.08)
        : "transparent"
    }

    Text {
      id: menuLabel
      anchors.centerIn: parent
      text: button.label
      color: button.enabled ? button.textColor : Util.alpha(button.textColor, 0.4)
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      onClicked: {
        if (!button.enabled) return
        root.openMenuFor(button)
      }
    }
  }

  // ---- dropdown panel state -------------------------------------------------
  property Item openButton: null
  property Item openSubmenu: null
  property var openItems: []
  property var openCallback: null
  property int openDepth: 0

  function itemFor(button) {
    // Find the manifest entry for the button that opened the menu.
    for (var i = 0; i < root.items.length; i++) {
      if (root.items[i].label === button.label) return root.items[i]
    }
    return root.items[0] || {}
  }

  function openMenuFor(button) {
    var entry = root.itemFor(button)
    var submenu = entry.submenu || []
    if (submenu.length === 0) {
      root.itemActivated({ label: button.label, item: entry })
      return
    }
    root.openButton = button
    root.openItems = submenu
    root.openCallback = function (item) { root.itemActivated(item) }
    root.openDepth = 0
    root.openSubmenu = null
    menuPanel.updatePosition()
    menuPanel.visible = true
    for (var i = 0; i < menuRow.children.length; i++) {
      var b = menuRow.children[i]
      if (b.open !== undefined) b.open = (b === button)
    }
  }

  function closeMenu() {
    menuPanel.visible = false
    root.openButton = null
    root.openSubmenu = null
    root.openItems = []
    for (var i = 0; i < menuRow.children.length; i++) {
      var b = menuRow.children[i]
      if (b.open !== undefined) b.open = false
    }
  }

  // ---- popup panel ----------------------------------------------------------
  Item {
    id: popupOverlay
    anchors.fill: root
    z: 200
    visible: menuPanel.visible

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeMenu()
    }

    MenuPanel {
      id: menuPanel
      anchors.fill: parent
      visible: false
    }
  }

  component MenuPanel: Item {
    id: panelRoot
    property bool visible: false

    Rectangle {
      id: panel
      visible: panelRoot.visible
      width: Math.min(Style.space(280), panelRoot.width - 8)
      implicitHeight: list.count * Style.spacing.popupRowHeight + Style.space(8)
      color: root.surfaceColor
      border.color: root.surfaceBorder
      border.width: 1
      radius: Style.cornerRadius
      z: 300

      x: {
        var bx = 0
        var by = 0
        if (root.openButton) {
          var pos = root.openButton.mapToItem(panelRoot, 0, root.openButton.height)
          bx = pos.x
          by = pos.y
        }
        return bx
      }
      y: {
        var bx = 0
        var by = 0
        if (root.openButton) {
          var pos = root.openButton.mapToItem(panelRoot, 0, root.openButton.height)
          bx = pos.x
          by = pos.y
        }
        return by
      }

      // Submenu opens to the right of the hovered/clicked row.
      Item {
        id: submenuPlaceholder
        x: 0
        y: 0
        width: 1
        height: 1
      }

      ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Style.space(4)
        clip: true
        model: root.openItems
        delegate: Row {
          id: rowDelegate
          required property var modelData
          property bool hovered: false
          width: list.width
          height: Style.spacing.popupRowHeight

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: rowDelegate.hovered
              ? Util.alpha(root.surfaceText, 0.08)
              : "transparent"
          }

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            text: modelData.separator ? "" : (modelData.label || "")
            color: rowDelegate.hovered
              ? root.surfaceText
              : (modelData.enabled === false ? Util.alpha(root.surfaceText, 0.4) : root.surfaceText)
            font.pixelSize: Style.font.body
            visible: !modelData.separator
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Style.space(8)
            text: modelData.submenu && modelData.submenu.length ? "›" : (modelData.checked ? "✓" : "")
            color: root.surfaceText
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
              rowDelegate.hovered = true
              if (modelData.submenu && modelData.submenu.length) root.openSubmenuAt(modelData.submenu)
            }
            onExited: rowDelegate.hovered = false
            onClicked: {
              if (modelData.separator) return
              if (modelData.submenu && modelData.submenu.length) {
                root.openSubmenuAt(modelData.submenu)
                return
              }
              if (modelData.enabled === false) return
              var item = modelData
              root.closeMenu()
              if (root.openCallback) root.openCallback(item)
            }
          }
        }
      }

      // Nested submenu panel (one level).
      Rectangle {
        id: submenu
        visible: root.openSubmenu !== null
        width: Style.space(260)
        implicitHeight: submenuList.count * Style.spacing.popupRowHeight + Style.space(8)
        color: root.surfaceColor
        border.color: root.surfaceBorder
        border.width: 1
        radius: Style.cornerRadius
        z: 400

        x: panel.width - Style.space(4)
        y: submenuY

        property int submenuY: 0

        ListView {
          id: submenuList
          anchors.fill: parent
          anchors.margins: Style.space(4)
          clip: true
          model: root.openSubmenu
          delegate: Row {
            required property var modelData
            property bool hovered: false
            width: submenuList.width
            height: Style.spacing.popupRowHeight

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: hovered ? Util.alpha(root.surfaceText, 0.08) : "transparent"
            }
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              text: modelData.label || ""
              color: modelData.enabled === false ? Util.alpha(root.surfaceText, 0.4) : root.surfaceText
              font.pixelSize: Style.font.body
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.rightMargin: Style.space(8)
              text: modelData.checked ? "✓" : ""
              color: root.surfaceText
              font.pixelSize: Style.font.body
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: hovered = true
              onExited: hovered = false
              onClicked: {
                if (modelData.enabled === false) return
                var item = modelData
                root.closeMenu()
                if (root.openCallback) root.openCallback(item)
              }
            }
          }
        }
      }

      function openSubmenuAt(items) {
        root.openSubmenu = items
      }

      function updatePosition() {
        // no-op; position is computed from root.openButton each frame
      }
    }

    function updatePosition() { panel.updatePosition() }
  }
}