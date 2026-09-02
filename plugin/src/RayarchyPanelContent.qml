import QtQuick
import QtQuick.Controls
import qs.Commons

Item {
  id: root
  property var rpc: null
  property var profiles: []
  property string query: ""
  property bool connected: false
  function refresh() { if (!root.rpc) return; root.rpc.call("profile.list", {}, function(result, error) { if (!error) root.profiles = result || [] }) }
  Component.onCompleted: root.refresh()
  Connections { target: root.rpc; function onConnectedChanged() { if (root.rpc.connected) root.refresh() } }
  Rectangle { anchors.fill: parent; color: Color.background }
  Column {
    anchors.fill: parent; anchors.margins: 18; spacing: 12
    Row { spacing: 12; Text { text: "Rayarchy"; color: Color.foreground; font.bold: true; font.pixelSize: 22 } Button { text: root.connected ? "Disconnect" : "Connect"; onClicked: root.connected = !root.connected } }
    TextField { width: parent.width; placeholderText: "Search profiles…"; onTextChanged: root.query = text }
    Text { visible: root.profiles.length === 0; text: "No profiles yet. Add a profile or subscription to begin."; color: Color.foreground }
    ListView {
      width: parent.width; height: Math.max(80, parent.height - y - 54)
      model: root.profiles.filter(function(p) { return !root.query || String(p.name).toLowerCase().indexOf(root.query.toLowerCase()) >= 0 })
      delegate: Rectangle {
        width: ListView.view.width; height: 58; color: "transparent"; border.color: Color.foreground; border.width: 1
        Row {
          anchors.fill: parent; anchors.margins: 8; spacing: 10
          Column { width: parent.width - 130; Text { text: modelData.name; color: Color.foreground; elide: Text.ElideRight } Text { text: (modelData.server || "") + (modelData.port ? ":" + modelData.port : ""); color: Qt.darker(Color.foreground, 1.5) } }
          Button { text: "★"; onClicked: root.rpc.call("profile.favorite", { profileId: modelData.id, favorite: !modelData.favorite }, function() { root.refresh() }) }
          Button { text: "•••"; onClicked: details.open() }
        }
        Dialog { id: details; title: modelData.name; modal: true; standardButtons: Dialog.Close; contentItem: Column { spacing: 8; Text { text: modelData.protocol + "  " + (modelData.server || "") + ":" + (modelData.port || ""); color: Color.foreground } Button { text: "Delete"; onClicked: { details.close(); root.rpc.call("profile.delete", { profileId: modelData.id }, function() { root.refresh() }) } } } }
      }
    }
    Button { text: "Add profile"; onClicked: addDialog.open() }
  }
  Dialog { id: addDialog; modal: true; title: "Add profile"; standardButtons: Dialog.Ok | Dialog.Cancel; contentItem: TextArea { id: input; placeholderText: "Paste a vless://, vmess://, trojan://, ss://, JSON, or YAML configuration" } onAccepted: if (root.rpc) root.rpc.call("import.commit", { input: input.text }, function(result, error) { if (!error) { input.text = ""; root.refresh() } }) }
}
