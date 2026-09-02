import QtQuick
import qs.Ui
import qs.Commons

Panel {
    id: root
    moduleName: "com.drunkleen.rayarchy"
    ipcTarget: "com.drunkleen.rayarchy"
    manageIpc: false
    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root
    function openFromHotkey() {
        root.controller.show();
    }
    function toggle() {
        root.opened ? root.close() : root.openFromHotkey();
    }
    RayarchyRpc {
        id: rpc
    }
    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        centerOnBar: true
        contentWidth: panel.fittedContentWidth(Style.space(600))
        contentHeight: panel.fittedContentHeight(Style.space(760))
        RayarchyPanelContent {
            anchors.fill: parent
            rpc: rpc
        }
    }
}
