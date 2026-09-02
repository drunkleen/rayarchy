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
    RayarchyPanelContent {
        anchors.fill: parent
        rpc: rpc
    }
}
