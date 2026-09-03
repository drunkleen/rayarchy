import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "controls/Common.js" as Common
import "strings.js" as Strings
import "controls"
import "views"
import "dialogs"

// Rayarchy panel window: a v2rayN-style main window rendered entirely inside
// the Omarchy shell. No external windows are created — every dialog is an
// inline sheet over this surface.
Item {
  id: root

  // ---- plugin lifecycle ------------------------------------------------------
  property bool closingFromHost: false

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    Qt.callLater(function () {
      root.activate()
    })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("com.drunkleen.rayarchy")
    else window.visible = false
  }

  function ping() { return "ok" }

  function activate() {
    rpc.setSocketPath(runtimeSocket)
    Qt.callLater(function () {
      if (profilesView) profilesView.forceActiveFocus()
    })
  }

  // ---- host injections --------------------------------------------------------
  property var shell: null
  property var manifest: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeSocket: Quickshell.env("XDG_RUNTIME_DIR") + "/rayarchy/rayarchy.sock"

  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted

  // ---- RPC + state -------------------------------------------------------------
  Rpc {
    id: rpcInstance
  }
  property alias rpc: rpcInstance
  property var status: ({})
  property var selection: []
  property bool daemonReady: rpcInstance.ready

  Connections {
    target: rpcInstance
    function onStatusChanged() {
      if (rpcInstance.ready) {
        if (!root.daemonReady) {
          root.daemonReady = true
          root.loadUiState()
        }
        root.refreshAll()
      } else {
        root.daemonReady = false
      }
    }
  }

  function refreshStatus() {
    if (!rpc.ready) return
    rpc.call("system.status", {}, function (result) {
      root.status = result || {}
      if (result && result.version) root.appVersion = result.version
    })
  }

  property string appVersion: ""

  function refreshAll() {
    root.refreshStatus()
    if (profilesView) profilesView.refresh()
    if (statusBar) statusBar.refreshRouting()
    if (rpc.ready) {
      rpc.call("system.capabilities", {}, function (caps) {
        if (caps) root.tunAvailable = caps.tun === true
      })
      rpc.call("settings.get", {}, function (s) {
        if (s && s.connectionMode) root.connectionMode = s.connectionMode
        if (s) root.killSwitch = s.killSwitch === true
      })
    }
  }

  property string connectionMode: "system_proxy"
  property bool killSwitch: false
  property bool tunAvailable: false

  function toggleTun() {
    if (!rpc.ready) { root.notify(Strings.tr("backendNotInstalled")); return }
    var enable = root.connectionMode !== "tun"
    if (enable && root.status.profileId) {
      root.confirm(Strings.tr("runningConnecting") + " — TUN?", function () {
        root.applyConnectionMode("tun")
      })
      return
    }
    root.applyConnectionMode(enable ? "tun" : "system_proxy")
  }

  function applyConnectionMode(mode) {
    var active = root.status.profileId
    if (active) {
      rpc.call("profile.disconnect", {}, function () { root.commitConnectionMode(mode, active) })
    } else {
      root.commitConnectionMode(mode, null)
    }
  }

  function commitConnectionMode(mode, activeId) {
    rpc.call("settings.get", {}, function (s) {
      var settings = s || {}
      var connectedId = activeId
      settings.connectionMode = mode
      rpc.call("settings.update", { settings: settings }, function (result) {
        if (result.error) { root.notify(result.error); return }
        root.connectionMode = mode
        if (connectedId) {
          rpc.call("profile.connect", { profileId: connectedId }, function (res) {
            if (res.error) root.notify(Strings.tr("connectFailed") + ": " + res.error)
            root.refreshAll()
          })
        } else {
          root.refreshAll()
        }
      })
    })
  }

  // ---- UI state persistence -----------------------------------------------------
  property var uiState: ({ columns: [], windowWidth: 1280, windowHeight: 820 })
  property bool showStatsColumns: false

  function defaultColumns() {
    var cols = [
      { key: "configType", label: Strings.tr("colConfigType"), width: 90 },
      { key: "remarks", label: Strings.tr("colRemarks"), width: 220 },
      { key: "address", label: Strings.tr("colAddress"), width: 150 },
      { key: "port", label: Strings.tr("colPort"), width: 70 },
      { key: "network", label: Strings.tr("colNetwork"), width: 80 },
      { key: "security", label: Strings.tr("colSecurity"), width: 70 },
      { key: "subRemarks", label: Strings.tr("colSub"), width: 130 },
      { key: "delay", label: Strings.tr("colDelay"), width: 90 },
      { key: "speed", label: Strings.tr("colSpeed"), width: 100 },
      { key: "ipInfo", label: Strings.tr("colIp"), width: 140 }
    ]
    if (root.showStatsColumns) {
      cols = cols.concat([
        { key: "todayUp", label: Strings.tr("colTodayUp"), width: 80 },
        { key: "todayDown", label: Strings.tr("colTodayDown"), width: 80 },
        { key: "totalUp", label: Strings.tr("colTotalUp"), width: 80 },
        { key: "totalDown", label: Strings.tr("colTotalDown"), width: 80 }
      ])
    }
    return cols
  }

  function toggleStatsColumns() {
    root.showStatsColumns = !root.showStatsColumns
    root.uiState.columns = root.defaultColumns()
    root.scheduleUiSave()
  }

  function loadUiState() {
    rpc.call("ui.get", {}, function (state) {
      root.showStatsColumns = state && state.showStatsColumns === true
      var cols = state && state.columns && state.columns.length ? state.columns : root.defaultColumns()
      root.uiState.columns = cols
      if (state && state.windowWidth) window.width = state.windowWidth
      if (state && state.windowHeight) window.height = state.windowHeight
    })
  }

  Timer {
    id: uiSaveTimer
    interval: 900
    onTriggered: {
      if (!rpc.ready) return
      rpc.call("ui.set", { ui: {
        columns: root.uiState.columns,
        windowWidth: window.width,
        windowHeight: window.height,
        showStatsColumns: root.showStatsColumns
      } }, function () {})
    }
  }

  function scheduleUiSave() { uiSaveTimer.restart() }
  function onColumnWidthChanged(index, width) {
    if (index < 0 || index >= root.uiState.columns.length) return
    var cols = root.uiState.columns.slice()
    cols[index] = Common.clone(cols[index])
    cols[index].width = width
    root.uiState.columns = cols
    root.scheduleUiSave()
  }
  function autofitColumns() {
    root.uiState.columns = root.defaultColumns()
    root.scheduleUiSave()
  }

  // ---- window ---------------------------------------------------------------------
  property Item windowContent: null

  FloatingWindow {
    id: window
    title: root.appVersion !== "" ? "Rayarchy " + root.appVersion : "Rayarchy"
    color: root.background
    implicitWidth: 1280
    implicitHeight: 820
    minimumSize: Qt.size(900, 600)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function") {
        root.shell.hide("com.drunkleen.rayarchy")
      }
    }

    Connections {
      target: window
      function onWidthChanged() { root.scheduleUiSave() }
      function onHeightChanged() { root.scheduleUiSave() }
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true
      Component.onCompleted: root.windowContent = focusScope

      // ---- main layout -------------------------------------------------------------
      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ToolBar {
          id: toolBar
          Layout.fillWidth: true
          Layout.bottomMargin: 2
          app: root
          onAddRequested: root.openAddServer()
          onPasteRequested: root.importClipboard()
          onSubsRequested: root.openSubSetting()
          onRoutingRequested: root.openRoutingSetting()
          onDnsRequested: root.openDnsSetting()
          onOptionsRequested: root.openOptionSetting()
          onUpdateRequested: root.openCheckUpdate()
          onBackupRequested: root.openBackupRestore()
          onReloadRequested: root.reload()
          onCloseRequested: root.requestClose()
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Util.alpha(Color.muted, 0.25)
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 0

          ProfilesView {
            id: profilesView
            Layout.fillWidth: true
            Layout.fillHeight: true
            app: root
            rpc: root.rpc
            status: root.status
          }

          Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: Util.alpha(Color.muted, 0.3)
          }

          // Right-hand tab area (Msg + Clash Proxies/Connections while sing-box runs)
          Rectangle {
            Layout.preferredWidth: 400
            Layout.fillHeight: true
            color: Util.alpha(Color.background, 0.5)

            TabBar {
              id: tabBar
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              Repeater {
                model: root.tabModel
                delegate: TabButton {
                  required property var modelData
                  text: modelData.label
                }
              }
            }

            StackLayout {
              anchors.top: tabBar.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              currentIndex: tabBar.currentIndex

              MsgView {
                id: msgView
                app: root
                rpc: root.rpc
              }
              ClashProxies {
                id: clashProxies
                app: root
                rpc: root.rpc
              }
              ClashConnections {
                id: clashConnections
                app: root
                rpc: root.rpc
              }
            }
          }
        }

        StatusBar {
          id: statusBar
          Layout.fillWidth: true
          app: root
          rpc: root.rpc
          status: root.status
        }
      }

      Keys.onPressed: function (event) {
        if (sheetHost.stack.length > 0) {
          if (event.key === Qt.Key_Escape) { sheetHost.closeTop(); event.accepted = true; return }
          event.accepted = false
          return
        }
        if (contextMenu.visible) {
          if (event.key === Qt.Key_Escape) { contextMenu.hide(); event.accepted = true; return }
          event.accepted = false
          return
        }
        if (event.key === Qt.Key_F5) { root.reload(); event.accepted = true; return }
        if (event.key === Qt.Key_Escape) { root.requestClose(); event.accepted = true; return }
        if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_V) { root.importClipboard(); event.accepted = true; return }
      }

      // ---- overlays ----------------------------------------------------------------
      SheetHost {
        id: sheetHost
        anchors.fill: parent
        z: 400
      }

      ContextMenu {
        id: contextMenu
        anchors.fill: parent
        z: 500
      }

      Rectangle {
        id: snackbar
        z: 600
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(24)
        width: Math.min(360, parent.width - 40)
        height: snackbarText.implicitHeight + Style.space(16)
        visible: false
        radius: Style.cornerRadius
        color: Util.alpha(Color.background, 0.92)
        border.color: Color.muted
        border.width: 1
        Text {
          id: snackbarText
          anchors.fill: parent
          anchors.margins: Style.space(8)
          color: Color.foreground
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
        Timer {
          id: snackbarTimer
          interval: 2600
          onTriggered: snackbar.visible = false
        }
      }
    }
  }

  function openCheckUpdate() {
    sheetHost.open(Qt.createComponent("dialogs/CheckUpdate.qml"), {
      rpc: rpc, app: root, title: Strings.tr("checkUpdateTitle")
    })
  }

  function clearStatistics() {
    root.confirm(Strings.tr("clearServerStats") + "?", function () {
      rpc.call("statistics.clear", {}, function () { root.refreshStatus(); root.profilesView.refresh() })
    })
  }

  // Right-hand tabs: Msg always; Clash Proxies/Connections while sing-box runs.
  // The model is rebuilt only when the visibility actually changes (a freshly
  // filtered array on every status poll would churn the TabBar delegates).
  property bool _lastClashUI: false
  property var tabModel: [{ key: "msg", label: Strings.tr("tabMsg") }]
  readonly property bool showClashUI: root.status.core === "sing-box"
  onShowClashUIChanged: root.rebuildTabs()
  function rebuildTabs() {
    root._lastClashUI = root.showClashUI
    var tabs = [{ key: "msg", label: Strings.tr("tabMsg") }]
    if (root.showClashUI) {
      tabs.push({ key: "proxies", label: Strings.tr("tabProxies") })
      tabs.push({ key: "connections", label: Strings.tr("tabConnections") })
    }
    root.tabModel = tabs
  }

  // ---- status/action helpers ---------------------------------------------------------
  function notify(message) {
    snackbarText.text = message
    snackbar.visible = true
    snackbarTimer.restart()
  }

  function copyText(text) {
    Quickshell.clipboardText = text
    root.notify(Strings.tr("msgCopy") + " ✓")
  }

  function contextMenu(items, x, y, callback) {
    contextMenu.showAt(x, y, items, callback)
  }
  function contextMenuHide() { contextMenu.hide() }
  function sheetHostOpen() { return sheetHost.stack.length > 0 }

  function activateProfile(profile) {
    if (!rpc.ready) { root.notify(Strings.tr("backendNotInstalled")); return }
    if (root.status.profileId && String(root.status.profileId) === String(profile.id)) {
      rpc.call("profile.disconnect", {}, function () { root.refreshAll() })
      return
    }
    if (root.status.connecting) { root.notify(Strings.tr("runningConnecting")); return }
    rpc.call("profile.connect", { profileId: profile.id }, function (result) {
      if (result.error) root.notify(Strings.tr("connectFailed") + ": " + result.error)
      root.refreshAll()
    }, function (error) {
      root.notify(Strings.tr("connectFailed") + ": " + error)
      root.refreshAll()
    })
  }

  function disconnect() {
    rpc.call("profile.disconnect", {}, function () { root.refreshAll() })
  }

  function reload() {
    if (!rpc.ready) { root.notify(Strings.tr("backendNotInstalled")); return }
    rpc.call("system.reload", {}, function (result) {
      if (result.error) root.notify("Reload: " + result.error)
      root.refreshAll()
    })
  }

  function setDefault(id) {
    rpc.call("profile.setDefault", { profileId: id }, function () { root.profilesView.refresh() })
  }

  function checkAvailability() {
    rpc.call("test.proxy", {}, function (proxy) { root.refreshStatus() })
    rpc.call("test.ip", {}, function (ip) { root.refreshStatus() })
  }

  function openServerEditor(protocol, profile) {
    sheetHost.open(Qt.createComponent("dialogs/ServerEdit.qml"), {
      rpc: rpc, app: root, protocol: protocol, profile: profile,
      title: Strings.tr("serverEditTitle")
    })
  }

  function openAddServer() {
    sheetHost.open(Qt.createComponent("dialogs/AddServer.qml"), {
      rpc: rpc, app: root, title: Strings.tr("serverEditTitle")
    })
  }

  function editServer(profile) {
    root.openServerEditor(profile.protocol, profile)
  }

  function copyServer(profile) {
    rpc.call("profile.duplicate", { profileId: profile.id }, function () { root.profilesView.refresh() })
  }

  function removeServers(ids) {
    root.confirm(Strings.tr("removeServer") + " (" + ids.length + ")?", function () {
      var done = 0
      for (var i = 0; i < ids.length; i++) {
        rpc.call("profile.delete", { profileId: ids[i] }, function () {
          done++
          if (done === ids.length) root.profilesView.refresh()
        })
      }
    })
  }

  function removeDuplicates() {
    root.confirm(Strings.tr("removeDuplicate") + "?", function () {
      rpc.call("profile.duplicates.remove", {}, function () { root.profilesView.refresh() })
    })
  }

  function removeInvalid(profile) {
    if (!profile.lastTest || profile.lastTest.ok) { root.notify("—"); return }
    root.removeServers([profile.id])
  }

  function speedTestProfile(profile) {
    root.notify(Strings.tr("speedTest") + "…")
    rpc.call("test.speed.profile", { profileId: profile.id }, function (result) {
      if (result.error) root.notify(Strings.tr("speedTest") + ": " + result.error)
      else if (result.ok) root.notify(profile.name + ": " + Common.speedText(result.megabitsPerSecond))
      else root.notify(profile.name + ": failed")
      root.profilesView.refresh()
    })
  }

  function udpTestProfile(profile) {
    root.notify(Strings.tr("udpTest") + "…")
    rpc.call("test.udp", { profileId: profile.id }, function (result) {
      if (result.error) root.notify(Strings.tr("udpTest") + ": " + result.error)
      else if (result.ok) root.notify(profile.name + ": UDP " + result.latencyMs + " ms")
      else root.notify(profile.name + ": UDP failed")
      root.profilesView.refresh()
    })
  }

  function shareServer(profile, format) {
    var payload = profile.raw || ""
    if (format === "base64") {
      payload = Qt.btoa(unescape(encodeURIComponent(payload)))
    } else if (format === "inner") {
      rpc.call("profile.inner", { profileId: profile.id }, function (result) {
        if (!result || result.error) { root.notify("Inner URI unavailable"); return }
        root.sharePayload(profile, result.innerUri || "", true)
      })
      return
    }
    root.sharePayload(profile, payload, false)
  }

  function sharePayload(profile, payload, skipQr) {
    if (skipQr) {
      sheetHost.open(Qt.createComponent("dialogs/QrShare.qml"), {
        rpc: rpc, app: root, payload: payload, imagePath: "", error: "",
        title: Strings.tr("qrShareTitle")
      })
      return
    }
    rpc.call("profile.qr.image", { profileId: profile.id }, function (result) {
      sheetHost.open(Qt.createComponent("dialogs/QrShare.qml"), {
        rpc: rpc, app: root, payload: payload, imagePath: result.imagePath || "", error: result.error || "",
        title: Strings.tr("qrShareTitle")
      })
    })
  }

  function moveSelected(ids, direction) {
    rpc.call("profile.list", {}, function (rows) {
      var order = rows.map(function (p) { return p.id })
      var indexes = ids.map(function (id) { return order.indexOf(id) }).filter(function (i) { return i >= 0 })
      indexes.sort(function (a, b) { return a - b })
      if (direction === "top") {
        var top = indexes.map(function (i) { return order[i] })
        var rest = order.filter(function (id) { return top.indexOf(id) === -1 })
        order = top.concat(rest)
      } else if (direction === "bottom") {
        var bottom = indexes.map(function (i) { return order[i] })
        var rest2 = order.filter(function (id) { return bottom.indexOf(id) === -1 })
        order = rest2.concat(bottom)
      } else if (direction === "up") {
        for (var i = 0; i < indexes.length; i++) {
          if (indexes[i] > 0) {
            var tmp = order[indexes[i] - 1]
            order[indexes[i] - 1] = order[indexes[i]]
            order[indexes[i]] = tmp
            indexes[i]--
          }
        }
      } else if (direction === "down") {
        for (var j = indexes.length - 1; j >= 0; j--) {
          if (indexes[j] < order.length - 1) {
            var tmp2 = order[indexes[j] + 1]
            order[indexes[j] + 1] = order[indexes[j]]
            order[indexes[j]] = tmp2
            indexes[j]++
          }
        }
      }
      rpc.call("profile.reorder", { profileIds: order }, function () { root.profilesView.refresh() })
    })
  }

  function moveToGroup(ids, groupId) {
    var done = 0
    for (var i = 0; i < ids.length; i++) {
      rpc.call("profile.get", { profileId: ids[i] }, function (p) {
        if (p.error) { done++; return }
        p.group = groupId
        rpc.call("profile.update", { profile: p }, function () {
          done++
          if (done === ids.length) root.profilesView.refresh()
        })
      })
    }
  }

  // ---- subscriptions -----------------------------------------------------------
  function addSubscription() {
    sheetHost.open(Qt.createComponent("dialogs/SubscriptionEdit.qml"), {
      rpc: rpc, app: root, subscription: null, title: Strings.tr("subAdd")
    })
  }
  function editSubscription(id) {
    var sub = null
    for (var i = 0; i < root.profilesView.subscriptions.length; i++) {
      if (String(root.profilesView.subscriptions[i].id) === String(id)) sub = root.profilesView.subscriptions[i]
    }
    if (!sub) return
    sheetHost.open(Qt.createComponent("dialogs/SubscriptionEdit.qml"), {
      rpc: rpc, app: root, subscription: sub, title: Strings.tr("subEdit")
    })
  }
  function deleteSubscription(id) {
    root.confirm(Strings.tr("subDelete") + "?", function () {
      rpc.call("subscription.delete", { subscriptionId: id }, function () { root.refreshAll() })
    })
  }
  function refreshSubscription(id) {
    rpc.call("subscription.refresh", { subscriptionId: id }, function (result) {
      if (result.error) root.notify("Subscription: " + result.error)
      else root.notify(Strings.tr("subRefresh") + " ✓ (" + result.updated + ")")
      root.refreshAll()
    })
  }
  function updateAllSubscriptions() {
    var subs = root.profilesView.subscriptions
    var count = 0
    for (var i = 0; i < subs.length; i++) {
      if (!subs[i].enabled) continue
      count++
      root.refreshSubscription(subs[i].id)
    }
    if (count === 0) root.notify(Strings.tr("subSetting"))
  }
  function updateSubscription(id) {
    root.refreshSubscription(id)
  }
  function openSubSetting() {
    sheetHost.open(Qt.createComponent("dialogs/SubSetting.qml"), {
      rpc: rpc, app: root, title: Strings.tr("subSetting")
    })
  }

  // ---- settings sheets ------------------------------------------------------------
  function openOptionSetting() {
    sheetHost.open(Qt.createComponent("dialogs/OptionSetting.qml"), {
      rpc: rpc, app: root, title: Strings.tr("optSetting")
    })
  }
  function openRoutingSetting() {
    sheetHost.open(Qt.createComponent("dialogs/RoutingSetting.qml"), {
      rpc: rpc, app: root, title: Strings.tr("routingSetting")
    })
  }
  function openDnsSetting() {
    sheetHost.open(Qt.createComponent("dialogs/DnsSetting.qml"), {
      rpc: rpc, app: root, title: Strings.tr("dnsSetting")
    })
  }
  function openBackupRestore() {
    sheetHost.open(Qt.createComponent("dialogs/BackupRestore.qml"), {
      rpc: rpc, app: root, title: Strings.tr("backupTitle")
    })
  }

  // ---- import -------------------------------------------------------------------------
  function importClipboard() {
    var text = (Quickshell.clipboardText || "").trim()
    if (text === "") {
      // Fall back to the daemon's wl-paste (works when the clipboard type is
      // text but Quickshell hasn't mirrored it).
      rpc.call("import.clipboard", {}, function (result) {
        if (result.error) { root.notify(Strings.tr("importFromClipboard") + ": " + result.error); return }
        if (!result.profiles || result.profiles.length === 0) { root.notify(Strings.tr("importFromClipboard") + ": —"); return }
        root.confirm(Strings.tr("importFromClipboard") + " (" + result.profiles.length + ")?", function () {
          root.commitImport(result.input)
        })
      })
      return
    }
    rpc.call("import.clipboard.text", { text: text }, function (result) {
      if (result.error) { root.notify(Strings.tr("importFromClipboard") + ": " + result.error); return }
      if (!result.profiles || result.profiles.length === 0) { root.notify(Strings.tr("importFromClipboard") + ": —"); return }
      root.confirm(Strings.tr("importFromClipboard") + " (" + result.profiles.length + ")?", function () {
        root.commitImport(result.input)
      })
    })
  }

  function importImage() {
    sheetHost.open(Qt.createComponent("dialogs/FileBrowser.qml"), {
      rpc: rpc, app: root, mode: "image",
      onPicked: function (path) { root.scanImage(path) },
      title: Strings.tr("addViaImage")
    })
  }

  function scanImage(path) {
    rpc.call("import.qr.image", { path: path }, function (result) {
      if (result.error) { root.notify("Import: " + result.error); return }
      if (!result.profiles || result.profiles.length === 0) { root.notify("—"); return }
      root.confirm(Strings.tr("importFromImage") + " (" + result.profiles.length + ")?", function () {
        root.commitImport(result.input)
      })
    })
  }

  function commitImport(input) {
    rpc.call("import.commit", { input: input }, function (result) {
      if (result.error) root.notify("Import: " + result.error)
      else root.notify(Strings.tr("importFromClipboard") + " ✓")
      root.refreshAll()
    })
  }

  // ---- misc -------------------------------------------------------------------------------
  function confirm(message, onOk, okText, okDanger) {
    var sheet = sheetHost.open(Qt.createComponent("controls/ConfirmSheet.qml"), {
      message: message, okText: okText || Strings.tr("yes"), okDanger: okDanger !== false
    })
    sheet.ok.connect(function () { onOk(); sheetHost.close(sheet) })
    sheet.cancelled.connect(function () { sheetHost.close(sheet) })
  }

  function setActiveRouting(routing) {
    // Named routing configs arrive with Phase 2; the single "Default" rule set
    // is active by construction. Rebuild the core config so new rules apply.
    root.reload()
  }

  function openFileLocation() {
    root.notify(Strings.tr("openFileLocation"))
  }

  function clearLogs() {
    msgView.logs = []
  }
}