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
    RayarchyRpc {
        id: rpc
    }
    RayarchyPanelContent {
        anchors.fill: parent
        rpc: rpc
    }
}
