import QtQuick
import QtQuick.Controls
import qs.Commons

// Host for the inline modal-sheet stack. Dialogs are pushed as sheets and the
// top one is rendered with a scrim; Esc closes the top sheet. Everything stays
// inside the Rayarchy window. Sheets are created as children of this host, so
// later sheets naturally stack above earlier ones and above the scrim.
Item {
  id: root

  property var stack: []

  Rectangle {
    id: scrim
    anchors.fill: parent
    z: 0
    color: Qt.rgba(0, 0, 0, 0.45)
    visible: root.stack.length > 0
  }

  function open(component, props) {
    var sheet = component.createObject(root, props || {})
    if (!sheet) return null
    sheet.visible = true
    sheet.z = root.stack.length + 1
    root.stack.push(sheet)
    if (sheet.closeRequested !== undefined) {
      sheet.closeRequested.connect(function () { root.close(sheet) })
    }
    return sheet
  }

  function close(sheet) {
    var index = root.stack.indexOf(sheet)
    if (index === -1) return
    root.stack.splice(index, 1)
    sheet.destroy()
  }

  function closeTop() {
    if (root.stack.length === 0) return false
    root.close(root.stack[root.stack.length - 1])
    return true
  }

  function closeAll() {
    while (root.stack.length > 0) root.close(root.stack[root.stack.length - 1])
  }
}