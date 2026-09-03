import QtQuick
import qs.Commons
import "../views"

// Logs: daemon log ring with filter, copy and client-side clear.
Item {
  id: root

  property var app: null
  property var rpc: null
  property var status: ({})

  function refresh() {
    if (msgView) msgView.refresh()
  }

  function clearLogs() {
    if (msgView) msgView.logs = []
  }

  MsgView {
    id: msgView
    anchors.fill: parent
    app: root.app
    rpc: root.rpc
    autoRefresh: true
  }
}