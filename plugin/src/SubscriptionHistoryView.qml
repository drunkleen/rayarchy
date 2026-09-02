import QtQuick
import QtQuick.Controls
import qs.Commons

Dialog {
    id: root
    property var subscriptions: []
    modal: true
    title: "Subscription refresh history"
    standardButtons: Dialog.Close
    Accessible.name: "Subscription refresh history"

    contentItem: ListView {
        width: 560
        height: Math.min(360, Math.max(80, root.subscriptions.length * 54))
        model: root.subscriptions
        delegate: Column {
            width: ListView.view.width
            spacing: 2
            Text {
                text: modelData.name
                color: Color.foreground
                font.bold: true
                Accessible.name: modelData.name
            }
            Text {
                text: modelData.lastRefreshAt ? "Last attempt: " + new Date(modelData.lastRefreshAt * 1000).toLocaleString() : "Never refreshed"
                color: Qt.darker(Color.foreground, 1.4)
            }
            Text {
                visible: !!modelData.lastError
                text: "Error: " + modelData.lastError
                color: "#ef6a6a"
            }
        }
    }
}
