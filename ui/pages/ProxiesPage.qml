import QtQuick
import qs.Commons
import "../views"

// Clash Proxies (sing-box clash_api), shown while connected via sing-box.
Item {
  id: root

  property var app: null
  property var rpc: null
  property var status: ({})

  function refresh() {
    if (clash) clash.refresh()
  }

  ClashProxies {
    id: clash
    anchors.fill: parent
    app: root.app
    rpc: root.rpc
  }
}