import QtQuick
import QtQuick.Controls
import qs.Commons
Item {
 id: root; property var rpc: null; property var profiles: []; property string query: ""; property bool connected: false
 Rectangle { anchors.fill: parent; color: Color.background }
 Column { anchors.fill: parent; anchors.margins: 18; spacing: 12
  Row { spacing: 12; Text { text: "Rayarchy"; color: Color.foreground; font.bold: true; font.pixelSize: 22 } Button { text: root.connected ? "Disconnect" : "Connect"; onClicked: root.connected=!root.connected } }
  TextField { width: parent.width; placeholderText: "Search profiles…"; onTextChanged: root.query=text }
  Text { visible: root.profiles.length===0; text: "No profiles yet. Add a profile or subscription to begin."; color: Color.foreground }
  Button { text: "Add profile"; onClicked: addDialog.open() }
 }
 Dialog { id: addDialog; modal: true; title: "Add profile"; standardButtons: Dialog.Ok | Dialog.Cancel; contentItem: TextArea { id: input; placeholderText: "Paste a vless://, vmess://, trojan://, ss://, JSON, or YAML configuration" } onAccepted: if (root.rpc) root.rpc.call("import.commit", {"input": input.text}, function(result, error) { if (!error) input.text = "" }) }
}
