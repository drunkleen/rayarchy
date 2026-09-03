import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "controls/Common.js" as Common
import "strings.js" as Strings
import "controls"
import "dialogs"

// Rayarchy compact panel content. Rendered inside the bar-widget KeyboardPanel;
// a left icon-rail sidebar switches between pages. Editors (add/edit server,
// subscription add/edit, routing, dns, settings sheets) open as full-cover
// sheets over the content area. Outside-click dismissal of the popup is
// suppressed while a sheet is open (see panelOwner.suppressClose).
Item {
  id: root
  focus: true

  // ---- plugin lifecycle ------------------------------------------------------
  property bool closingFromHost: false
  property var panelOwner: null

  function open(payloadJson) {
    closingFromHost = false
    Qt.callLater(function () { root.activate() })
  }

  function close() {
    closingFromHost = true
    if (panelOwner) panelOwner.close()
    closingFromHost = false
  }

  function requestClose() {
    if (root.sheetHostOpen()) { root.sheetHostCloseTop(); return }
    if (panelOwner) panelOwner.close()
    else if (shell && typeof shell.hide === "function") shell.hide("com.drunkleen.rayarchy")
  }

  function ping() { return "ok" }

  function activate() {
    rpc.setSocketPath(runtimeSocket)
    Qt.callLater(function () { root.forceActiveFocus() })
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
    if (pageLoader.item && typeof pageLoader.item.refresh === "function") pageLoader.item.refresh()
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
  property string activePageId: "overview"

  // sing-box exposes the clash API; show those pages only when available.
  readonly property bool showClashUI: root.status.connected === true && root.status.core === "sing-box"

  function loadUiState() {
    rpc.call("ui.get", {}, function (state) {
      if (state && state.activePageId) {
        for (var i = 0; i < root.navPages.length; i++) {
          if (root.navPages[i].id === state.activePageId) {
            root.activePageId = state.activePageId
            return
          }
        }
      }
    })
  }

  Timer {
    id: uiSaveTimer
    interval: 900
    onTriggered: {
      if (!rpc.ready) return
      rpc.call("ui.set", { ui: { activePageId: root.activePageId } }, function () {})
    }
  }
  function scheduleUiSave() { uiSaveTimer.restart() }

  // ---- navigation ----------------------------------------------------------------
  property var pages: [
    { id: "overview", label: "Overview", icon: "⌂", source: "pages/OverviewPage.qml" },
    { id: "servers", label: "Servers", icon: "☰", source: "pages/ServersPage.qml" },
    { id: "subs", label: "Subscriptions", icon: "⇄", source: "pages/SubscriptionsPage.qml" },
    { id: "routing", label: "Routing", icon: "➦", source: "pages/RoutingPage.qml" },
    { id: "dns", label: "DNS", icon: "☁", source: "pages/DnsPage.qml" },
    { id: "settings", label: "Settings", icon: "⚙", source: "pages/SettingsPage.qml" },
    { id: "logs", label: "Logs", icon: "≣", source: "pages/LogsPage.qml" },
    { id: "proxies", label: "Proxies", icon: "◈", source: "pages/ProxiesPage.qml" },
    { id: "connections", label: "Connections", icon: "⇅", source: "pages/ConnectionsPage.qml" },
    { id: "tools", label: "Tools", icon: "⚒", source: "pages/ToolsPage.qml" }
  ]

  function currentPage() {
    for (var i = 0; i < root.navPages.length; i++) {
      if (root.navPages[i].id === root.activePageId) return root.navPages[i]
    }
    return root.navPages[0]
  }

  // Sidebar shows clash pages only while a sing-box connection is active.
  readonly property var navPages: {
    var out = []
    for (var i = 0; i < root.pages.length; i++) {
      var p = root.pages[i]
      if ((p.id === "proxies" || p.id === "connections") && !root.showClashUI) continue
      out.push(p)
    }
    return out
  }

  readonly property string pageSource: {
    var id = root.activePageId
    for (var i = 0; i < root.navPages.length; i++) {
      if (root.navPages[i].id === id) return root.navPages[i].source
    }
    return root.navPages.length > 0 ? root.navPages[0].source : ""
  }

  readonly property string pageTitle: {
    var id = root.activePageId
    for (var i = 0; i < root.navPages.length; i++) {
      if (root.navPages[i].id === id) return root.navPages[i].label
    }
    return root.navPages.length > 0 ? root.navPages[0].label : ""
  }

  function setPage(id) {
    if (root.activePageId === id) return
    root.activePageId = id
    root.scheduleUiSave()
  }

  property alias contentArea: contentArea

  // ---- main layout -------------------------------------------------------------
  RowLayout {
    anchors.fill: parent
    spacing: 0

    // Left icon-rail sidebar
    Rectangle {
      Layout.fillHeight: true
      Layout.preferredWidth: Style.space(46)
      color: Util.alpha(Color.foreground, 0.05)

      Column {
        anchors.fill: parent
        anchors.topMargin: Style.space(6)
        anchors.bottomMargin: Style.space(6)
        spacing: Style.space(2)

        Repeater {
          model: root.navPages
          delegate: NavButton {
            required property var modelData
            icon: modelData.icon
            label: modelData.label
            selected: root.activePageId === modelData.id
            onClicked: root.setPage(modelData.id)
          }
        }

        Item { Layout.fillHeight: true; height: 8 }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredWidth: 1
      color: Util.alpha(Color.muted, 0.25)
    }

    // Content area
    Item {
      id: contentArea
      Layout.fillWidth: true
      Layout.fillHeight: true

      Loader {
        id: pageLoader
        anchors.fill: parent
        source: root.pageSource
        onLoaded: {
          item.app = root
          item.rpc = root.rpc
          item.status = Qt.binding(function () { return root.status })
        }
      }

      // Page title strip
      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.spacing.controlHeight + Style.space(10)
        z: 50
        color: Util.alpha(Color.background, 0.55)
        visible: root.activePageId !== "overview"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          Text {
            text: root.pageTitle
            color: Color.foreground
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
          Button {
            text: "✕"
            flat: true
            visible: root.sheetHostOpen()
            onClicked: root.sheetHostCloseTop()
          }
        }
      }

      // Editors / dialogs open as full-cover sheets over the content area.
      SheetHost {
        id: sheetHost
        anchors.top: (root.activePageId !== "overview") ? parent.top + Style.spacing.controlHeight + Style.space(10) : parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
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

  Keys.onPressed: function (event) {
    if (root.sheetHostOpen()) {
      if (event.key === Qt.Key_Escape) { root.sheetHostCloseTop(); event.accepted = true; return }
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

  // Let the active page handle page-specific shortcuts (Delete, Ctrl+C, …)
  // even though focus stays on this root. The page accepts what it owns and
  // falls through to the handlers above otherwise.
  Keys.forwardTo: pageLoader.item ? [pageLoader.item] : []

  function contextMenuVisible() { return contextMenu.visible }

  // suppress outside-click dismissal while a sheet is open
  readonly property bool anySheetOpen: sheetHost.stack.length > 0
  onAnySheetOpenChanged: {
    if (panelOwner) panelOwner.suppressClose = root.anySheetOpen
  }

  function sheetHostOpen() { return sheetHost.stack.length > 0 }
  function sheetHostCloseTop() { sheetHost.closeTop() }

  // ---- sheet openers ---------------------------------------------------------
  function openCheckUpdate() {
    sheetHost.open(Qt.createComponent("dialogs/CheckUpdate.qml"), {
      rpc: rpc, app: root, title: Strings.tr("checkUpdateTitle")
    })
  }

  function clearStatistics() {
    root.confirm(Strings.tr("clearServerStats") + "?", function () {
      rpc.call("statistics.clear", {}, function () { root.refreshStatus(); if (pageLoader.item && typeof pageLoader.item.refresh === "function") pageLoader.item.refresh() })
    })
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

  function connectDefault() {
    rpc.call("profile.default", {}, function (p) {
      if (p && p.id) root.activateProfile(p)
      else root.notify(Strings.tr("statusNotConnected") + " — " + Strings.tr("empty"))
    })
  }

  function reload() {
    if (!rpc.ready) { root.notify(Strings.tr("backendNotInstalled")); return }
    rpc.call("system.reload", {}, function (result) {
      if (result.error) root.notify("Reload: " + result.error)
      root.refreshAll()
    })
  }

  function setDefault(id) {
    rpc.call("profile.setDefault", { profileId: id }, function () {
      if (pageLoader.item && typeof pageLoader.item.refresh === "function") pageLoader.item.refresh()
    })
  }

  function checkAvailability() {
    rpc.call("test.proxy", {}, function (proxy) { root.refreshStatus() })
    rpc.call("test.ip", {}, function (ip) { root.refreshStatus() })
  }

  function openServerEditor(protocol, profile) {
    sheetHost.open(Qt.createComponent("dialogs/ServerEdit.qml"), {
      rpc: rpc, app: root, protocol: protocol, profile: profile,
      title: Strings.tr("serverEditTitle"), maximized: true
    })
  }

  function openAddServer() {
    sheetHost.open(Qt.createComponent("dialogs/AddServer.qml"), {
      rpc: rpc, app: root, title: Strings.tr("serverEditTitle"), maximized: true
    })
  }

  function editServer(profile) {
    root.openServerEditor(profile.protocol, profile)
  }

  function copyServer(profile) {
    rpc.call("profile.duplicate", { profileId: profile.id }, function () {
      if (pageLoader.item && typeof pageLoader.item.refresh === "function") pageLoader.item.refresh()
    })
  }

  function removeServers(ids) {
    root.confirm(Strings.tr("removeServer") + " (" + ids.length + ")?", function () {
      var done = 0
      for (var i = 0; i < ids.length; i++) {
        rpc.call("profile.delete", { profileId: ids[i] }, function () {
          done++
          if (done === ids.length) root.refreshAll()
        })
      }
    })
  }

  function removeDuplicates() {
    root.confirm(Strings.tr("removeDuplicate") + "?", function () {
      rpc.call("profile.duplicates.remove", {}, function () { root.refreshAll() })
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
      root.refreshAll()
    })
  }

  function udpTestProfile(profile) {
    root.notify(Strings.tr("udpTest") + "…")
    rpc.call("test.udp", { profileId: profile.id }, function (result) {
      if (result.error) root.notify(Strings.tr("udpTest") + ": " + result.error)
      else if (result.ok) root.notify(profile.name + ": UDP " + result.latencyMs + " ms")
      else root.notify(profile.name + ": UDP failed")
      root.refreshAll()
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
        title: Strings.tr("qrShareTitle"), maximized: true
      })
      return
    }
    rpc.call("profile.qr.image", { profileId: profile.id }, function (result) {
      sheetHost.open(Qt.createComponent("dialogs/QrShare.qml"), {
        rpc: rpc, app: root, payload: payload, imagePath: result.imagePath || "", error: result.error || "",
        title: Strings.tr("qrShareTitle"), maximized: true
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
      rpc.call("profile.reorder", { profileIds: order }, function () { root.refreshAll() })
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
          if (done === ids.length) root.refreshAll()
        })
      })
    }
  }

  // ---- subscriptions -----------------------------------------------------------
  function addSubscription() {
    sheetHost.open(Qt.createComponent("dialogs/SubscriptionEdit.qml"), {
      rpc: rpc, app: root, subscription: null, title: Strings.tr("subAdd"), maximized: true
    })
  }
  function editSubscription(id) {
    var sub = null
    if (pageLoader.item && typeof pageLoader.item.subscriptions === "object" && pageLoader.item.subscriptions) {
      for (var i = 0; i < pageLoader.item.subscriptions.length; i++) {
        if (String(pageLoader.item.subscriptions[i].id) === String(id)) sub = pageLoader.item.subscriptions[i]
      }
    }
    if (!sub) { root.notify(Strings.tr("subEdit")); return }
    sheetHost.open(Qt.createComponent("dialogs/SubscriptionEdit.qml"), {
      rpc: rpc, app: root, subscription: sub, title: Strings.tr("subEdit"), maximized: true
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
    var subs = []
    if (pageLoader.item && typeof pageLoader.item.subscriptions === "object" && pageLoader.item.subscriptions) subs = pageLoader.item.subscriptions
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
      rpc: rpc, app: root, title: Strings.tr("subSetting"), maximized: true
    })
  }

  // ---- settings sheets ------------------------------------------------------------
  function openBackupRestore() {
    sheetHost.open(Qt.createComponent("dialogs/BackupRestore.qml"), {
      rpc: rpc, app: root, title: Strings.tr("backupTitle"), maximized: true
    })
  }

  // ---- import -------------------------------------------------------------------------
  function importClipboard() {
    var text = (Quickshell.clipboardText || "").trim()
    if (text === "") {
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
      title: Strings.tr("addViaImage"), maximized: true
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
    root.reload()
  }

  function openFileLocation() {
    root.notify(Strings.tr("openFileLocation"))
  }

  function clearLogs() {
    if (rpc.ready) rpc.call("system.logs.clear", {}, function () {})
    if (pageLoader.item && typeof pageLoader.item.clearLogs === "function") pageLoader.item.clearLogs()
  }

  component NavButton: Item {
    id: nav
    property string icon: ""
    property string label: ""
    property bool selected: false
    property bool hovered: false
    signal clicked()

    width: parent.width
    height: Style.space(38)

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      radius: Style.cornerRadius
      color: nav.selected
        ? Util.alpha(Color.accent, 0.22)
        : (nav.hovered ? Util.alpha(Color.foreground, 0.08) : "transparent")
      border.color: nav.selected ? Color.accent : "transparent"
      border.width: 1
    }
    Text {
      anchors.centerIn: parent
      text: nav.icon
      color: nav.selected ? Color.accent : Color.foreground
      font.pixelSize: Style.font.body
    }
    MouseArea {
      id: navMouse
      anchors.fill: parent
      hoverEnabled: true
      onEntered: nav.hovered = true
      onExited: nav.hovered = false
      onClicked: nav.clicked()
    }

    ToolTip {
      visible: nav.hovered
      text: nav.label
      delay: 400
    }
  }
}