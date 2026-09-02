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
            panelLoader.item.openFromHotkey();
    }
    function close() {
        if (panelLoader.item)
            panelLoader.item.close();
    }
    function togglePanel() {
        if (panelLoader.item)
            panelLoader.item.toggle();
    }
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("RayarchyPanel.qml")
        visible: false
        onLoaded: root.injectPanel()
    }
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        tooltipText: "Rayarchy proxy manager"
        iconComponent: Component {
            Text {
                anchors.centerIn: parent
                text: "󰖟"
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.space(14)
            }
        }
        Accessible.name: "Open Rayarchy proxy manager"
        onPressed: function (buttonCode) {
            if (buttonCode === Qt.LeftButton)
                root.togglePanel();
        }
    }
}
