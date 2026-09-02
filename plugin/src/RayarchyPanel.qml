import QtQuick
import qs.Commons
Item { id: root; property var panel: null; function open(payloadJson) { visible=true } function close() { visible=false } visible: false; anchors.fill: parent; RayarchyRpc { id: rpc } RayarchyPanelContent { anchors.fill: parent; rpc: rpc } }
