import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "com.drunkleen.rayarchy"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    function injectPanel() {
        if (!panelLoader.item)
            return;
        panelLoader.item.anchorItem = button;
        panelLoader.item.hostWidget = root;
        panelLoader.item.bar = root.bar;
    }
    function open() {
        if (panelLoader.item)
            panelLoader.item.open();
    }
    function close() {
        if (panelLoader.item)
            panelLoader.item.close();
    }
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("RayarchyPanel.qml")
        visible: false
        onLoaded: root.injectPanel()
    }
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰖟"
        labelVisible: true
        hasVisualContent: true
        Accessible.name: "Open Rayarchy proxy manager"
        onPressed: function (mouseButton) {
            if (mouseButton === Qt.LeftButton)
                root.open();
        }
    }
}
