import QtQuick
import qs.Commons

Item {
    id: root
    implicitWidth: 92
    implicitHeight: 28
    Text {
        anchors.centerIn: parent
        text: "Rayarchy"
        color: Color.foreground
        font.family: "monospace"
    }
    MouseArea {
        anchors.fill: parent
        onClicked: if (rootPanel && rootPanel.open)
            rootPanel.open("{}")
    }
    property var rootPanel: null
}
