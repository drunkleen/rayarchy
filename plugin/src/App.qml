import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui

Item {
    id: root
    property var shell: null
    property var manifest: null
    property var service: null
    property bool opened: false
    property bool closingFromHost: false

    RayarchyRpc {
        id: rpc
    }

    function open(payload) {
        root.opened = true;
    }

    function close() {
        root.opened = false;
    }

    function requestClose() {
        if (root.shell && typeof root.shell.close === "function")
            root.shell.close(root.pluginId);
        else
            root.opened = false;
    }

    readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "com.drunkleen.rayarchy"
    readonly property color background: Color.background

    FloatingWindow {
        id: window
        visible: root.opened
        title: "Rayarchy"
        color: root.background
        width: Style.space(980)
        height: Style.space(720)
        implicitWidth: Style.space(980)
        implicitHeight: Style.space(720)
        minimumSize: Qt.size(Style.space(760), Style.space(520))

        onVisibleChanged: {
            if (!visible && root.opened && !root.closingFromHost)
                root.requestClose();
        }

        RayarchyPanelContent {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            rpc: rpc
        }
    }
}
