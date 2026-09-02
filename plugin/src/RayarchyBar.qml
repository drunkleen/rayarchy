import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "com.drunkleen.rayarchy"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    function open() {
        if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function")
            root.bar.shell.toggle(root.moduleName, "{}");
    }
    function close() {
        if (root.bar && root.bar.shell && typeof root.bar.shell.close === "function")
            root.bar.shell.close(root.moduleName);
    }
    function togglePanel() {
        root.open();
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
