import QtQuick
import QtQuick.Controls
import qs.Commons

Item {
  id: root
  focus: true
  Keys.onPressed: function(event) {
    if ((event.key === Qt.Key_F) && (event.modifiers & Qt.ControlModifier || event.modifiers & Qt.MetaModifier)) { searchField.forceActiveFocus(); event.accepted = true }
    else if (event.key === Qt.Key_Return && root.selectedId !== "" && !root.connected) { root.rpc.call("profile.connect", { profileId: root.selectedId }, function(result, error) { root.message = error ? error.message : "Connection established"; if (!error) root.refreshStatus() }); event.accepted = true }
    else if (event.key === Qt.Key_Escape && (root.query !== "" || root.groupFilter !== "" || root.favoritesOnly || root.healthOnly || root.sortMode !== "manual")) { searchField.text = ""; root.query = ""; root.groupFilter = ""; root.favoritesOnly = false; root.healthOnly = false; root.sortMode = "manual"; groupPicker.currentIndex = 0; root.refresh(); event.accepted = true }
  }
  property var rpc: null
  property var profiles: []
  property var allProfiles: []
  property string query: ""
  property string groupFilter: ""
  property string sortMode: "manual"
  property bool favoritesOnly: false
  property bool healthOnly: false
  property bool connected: false
  property string selectedId: ""
  property string message: ""
  property string subscriptionSummary: ""
  property var bulkResults: []
  property string bulkSortMode: "fastest"
  property bool subscriptionRefreshing: false
  ProtocolEditor { id: structuredEditor; rpc: root.rpc; onSaved: root.refresh() }
  function refresh() {
    if (!root.rpc) return
    root.rpc.call("profile.list", {}, function(result, error) {
      if (!error) root.allProfiles = result || []
    })
    root.rpc.call("profile.list", { query: root.query, group: root.groupFilter, sort: root.sortMode, favoritesOnly: root.favoritesOnly }, function(result, error) {
      if (error) root.message = error.message
      else root.profiles = root.healthOnly ? (result || []).filter(function(profile) { return profile.lastTest && profile.lastTest.ok }) : (result || [])
    })
    root.rpc.call("system.status", {}, function(result, error) {
      if (!error) { root.connected = !!result.connected; root.selectedId = result.profileId || root.selectedId }
    })
  }
  function groups() {
    var values = ["All groups"]
    root.allProfiles.forEach(function(profile) {
      var group = String(profile.group || "").trim()
      if (group && values.indexOf(group) < 0) values.push(group)
    })
    return values
  }
  function formatBulkResults(results) {
    if (!results || results.length === 0) return "No profiles were tested."
    var ordered = results.slice().sort(function(a, b) {
      if (root.bulkSortMode === "successful") return Number(b.ok) - Number(a.ok) || Number(a.latencyMs || 999999) - Number(b.latencyMs || 999999)
      if (root.bulkSortMode === "failed") return Number(a.ok) - Number(b.ok) || Number(a.latencyMs || 999999) - Number(b.latencyMs || 999999)
      return Number(a.latencyMs || 999999) - Number(b.latencyMs || 999999)
    })
    return ordered.map(function(row) {
      var status = row.ok ? "PASS" : "FAIL"
      var latency = Number(row.latencyMs || 0)
      var detail = row.ok ? (latency + " ms") : (row.error || "health check failed")
      return status + "  " + row.name + "  —  " + detail
    }).join("\n")
  }
  function cycleBulkSort() {
    root.bulkSortMode = root.bulkSortMode === "fastest" ? "successful" : (root.bulkSortMode === "successful" ? "failed" : "fastest")
  }
  function showSuccess(text) {
    root.message = text
    settingsMessageTimer.restart()
  }
  function refreshAllSubscriptions() {
    if (!root.rpc || root.subscriptionRefreshing) return
    root.subscriptionRefreshing = true
    var pending = subscriptionManager.items.slice()
    var updated = 0
    function next() {
      if (pending.length === 0) { root.subscriptionRefreshing = false; showSuccess("Subscriptions refreshed (" + updated + " profiles updated)"); root.refresh(); return }
      var item = pending.shift()
      root.message = "Refreshing " + item.name + "…"
      root.rpc.call("subscription.refresh", { subscriptionId: item.id }, function(result, error) { if (error) { root.subscriptionRefreshing = false; root.message = error.message; return } updated += Number(result.updated || 0); next() })
    }
    next()
  }
  function moveProfile(profileId, delta) {
    var ids = root.allProfiles.map(function(profile) { return profile.id })
    var from = ids.indexOf(profileId)
    var to = from + delta
    if (from < 0 || to < 0 || to >= ids.length) return
    var moved = ids.splice(from, 1)[0]
    ids.splice(to, 0, moved)
    root.rpc.call("profile.reorder", { profileIds: ids }, function(result, error) {
      root.message = error ? error.message : "Profile order saved"
      if (!error) root.refresh()
    })
  }
  function refreshStatus() {
    if (!root.rpc || !root.rpc.connected) return
    root.rpc.call("system.status", {}, function(result, error) {
      if (!error) {
        root.connected = !!result.connected
        if (result.profileId) root.selectedId = result.profileId
      }
    })
  }
  function refreshSubscriptions() {
    if (!root.rpc) return
    root.rpc.call("subscription.list", {}, function(result, error) {
      if (!error) {
        subscriptionManager.items = result || []
        var errors = subscriptionManager.items.filter(function(s) { return !!s.lastError }).length
        var enabled = subscriptionManager.items.filter(function(s) { return !!s.enabled }).length
        root.subscriptionSummary = subscriptionManager.items.length + " sources • " + enabled + " enabled" + (errors ? " • " + errors + " with errors" : "")
      }
      else root.message = error.message || "Could not load subscriptions"
    })
  }
  Component.onCompleted: root.refresh()
  Connections { target: root.rpc; function onConnectedChanged() { if (root.rpc.connected) root.refresh() } }
  Timer { interval: 2000; repeat: true; running: root.visible; triggeredOnStart: true; onTriggered: root.refreshStatus() }
  Timer { interval: 1000; repeat: true; running: subscriptionManager.visible; triggeredOnStart: true; onTriggered: root.refreshSubscriptions() }
  Timer { id: settingsMessageTimer; interval: 3500; repeat: false; onTriggered: root.message = "" }
  Rectangle { anchors.fill: parent; color: Color.background }
  Loader { id: subscriptionStatusLoader; sourceComponent: Component { Dialog { modal: true; title: "Subscription status"; standardButtons: Dialog.Close; contentItem: TextArea { id: statusText; width: 520; height: 300; readOnly: true; wrapMode: TextEdit.NoWrap; selectByMouse: true } } } }
  Loader { id: rawEditorLoader; sourceComponent: Component { Dialog { modal: true; title: "Raw profile configuration"; standardButtons: Dialog.Save | Dialog.Cancel; property string profileId: ""; contentItem: TextArea { id: rawText; width: 560; height: 320; wrapMode: TextEdit.NoWrap; selectByMouse: true } onAccepted: root.rpc.call("profile.raw.update", { profileId: rawEditorLoader.item.profileId, raw: rawText.text }, function(result, error) { root.message = error ? error.message : "Raw configuration saved"; if (!error) rawEditorLoader.item.close(); root.refresh() }) } } }
  Loader { id: protocolEditorLoader; sourceComponent: Component { Dialog { modal: true; title: "Quick protocol fields"; standardButtons: Dialog.Save | Dialog.Cancel; property string profileId: ""; function load(profile) { profileId = profile.id; uuid.text = profile.fields && profile.fields.user || ""; password.text = profile.fields && profile.fields.password || ""; security.text = profile.fields && (profile.fields.security || profile.fields.tls) || ""; sni.text = profile.fields && profile.fields.sni || ""; network.text = profile.fields && (profile.fields.type || profile.fields.network) || ""; path.text = profile.fields && profile.fields.path || ""; method.text = profile.fields && profile.fields.method || ""; obfs.text = profile.fields && (profile.fields.obfs || profile.fields["obfs-password"]) || ""; privateKey.text = profile.fields && profile.fields.private_key || ""; publicKey.text = profile.fields && profile.fields.public_key || ""; address.text = profile.fields && profile.fields.local_address || "" } contentItem: Column { spacing: 8; TextField { id: uuid; placeholderText: "UUID / user" } TextField { id: password; placeholderText: "Password"; echoMode: TextInput.Password } TextField { id: security; placeholderText: "Security (tls/none)" } TextField { id: sni; placeholderText: "SNI / server name" } TextField { id: network; placeholderText: "Network (ws/tcp)" } TextField { id: path; placeholderText: "Path" } TextField { id: method; placeholderText: "Shadowsocks method" } TextField { id: obfs; placeholderText: "Obfuscation / obfs password" } TextField { id: privateKey; placeholderText: "WireGuard private key"; echoMode: TextInput.Password } TextField { id: publicKey; placeholderText: "WireGuard public key" } TextField { id: address; placeholderText: "WireGuard local address" } } onAccepted: root.rpc.call("profile.fields.update", { profileId: protocolEditorLoader.item.profileId, fields: { user:uuid.text, password:password.text, security:security.text, sni:sni.text, type:network.text, path:path.text, method:method.text, obfs:obfs.text, private_key:privateKey.text, public_key:publicKey.text, local_address:address.text } }, function(result,error) { root.message = error ? error.message : "Protocol fields saved"; if (!error) { protocolEditorLoader.item.close(); root.refresh() } }) } } }
  Loader { id: qrImageLoader; sourceComponent: Component { Dialog { modal: true; title: "QR code"; standardButtons: Dialog.Close; contentItem: Image { id: qrImage; width: 320; height: 320; fillMode: Image.PreserveAspectFit } } } }
  Column {
    anchors.fill: parent; anchors.margins: 18; spacing: 12
    Row { spacing: 12; Text { text: "Rayarchy"; color: Color.foreground; font.bold: true; font.pixelSize: 22 } Button { text: root.connected ? "Disconnect" : "Connect"; enabled: root.selectedId !== "" || root.connected; onClicked: if (root.rpc) root.rpc.call(root.connected ? "profile.disconnect" : "profile.connect", root.connected ? {} : { profileId: root.selectedId }, function(result, error) { if (error) { root.message = error.message || "Connection failed" } else { root.message = root.connected ? "Disconnected" : "Connected"; root.refreshStatus() } }) } }
    TextField { id: searchField; width: parent.width; placeholderText: "Search profiles…"; onTextChanged: { root.query = text; root.refresh() } }
    Row {
      spacing: 8
      ComboBox { id: groupPicker; model: root.groups(); onActivated: { root.groupFilter = currentIndex === 0 ? "" : currentText; root.refresh() } }
      ComboBox { model: ["manual", "name", "server", "favorites"]; onActivated: { root.sortMode = currentText; root.refresh() } }
      CheckBox { text: "Favorites"; checked: root.favoritesOnly; onToggled: { root.favoritesOnly = checked; root.refresh() } }
      CheckBox { text: "Healthy only"; checked: root.healthOnly; onToggled: { root.healthOnly = checked; root.refresh() } }
      Button { text: "Clear filters"; visible: root.query !== "" || root.groupFilter !== "" || root.favoritesOnly || root.healthOnly || root.sortMode !== "manual"; onClicked: { searchField.text = ""; root.query = ""; root.groupFilter = ""; root.favoritesOnly = false; root.healthOnly = false; root.sortMode = "manual"; groupPicker.currentIndex = 0; root.refresh() } }
    }
    Text { visible: root.profiles.length === 0; text: "No profiles yet. Add a profile or subscription to begin."; color: Color.foreground }
    Text { visible: root.message !== ""; text: root.message; color: Color.accent; width: parent.width; wrapMode: Text.WordWrap }
    ListView {
      width: parent.width; height: Math.max(80, parent.height - y - 54); focus: true; keyNavigationEnabled: true; activeFocusOnTab: true
      model: root.profiles; onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex < root.profiles.length) root.selectedId = root.profiles[currentIndex].id
      delegate: Rectangle {
        width: ListView.view.width; height: 58; color: "transparent"; Accessible.name: modelData.name + ", " + (modelData.protocol || "profile") + (modelData.server ? ", " + modelData.server : ""); border.color: root.selectedId === modelData.id ? Color.accent : (ListView.view.activeFocus ? Qt.lighter(Color.foreground, 1.2) : Color.foreground); border.width: root.selectedId === modelData.id ? 2 : 1
        Row {
          anchors.fill: parent; anchors.margins: 8; spacing: 10
          Column { width: parent.width - 230; Text { text: modelData.name; color: Color.foreground; elide: Text.ElideRight } Text { text: (modelData.group ? modelData.group + " • " : "") + (modelData.server || "") + (modelData.port ? ":" + modelData.port : ""); color: Qt.darker(Color.foreground, 1.5) } Text { property var health: root.bulkResults.find(function(r) { return r.profileId === modelData.id }) || modelData.lastTest; visible: health !== undefined; text: health && health.ok ? "✓ Verified • " + health.latencyMs + " ms" : "✗ Failed • " + ((health && health.error) || "health check failed"); color: health && health.ok ? "#74d99f" : "#ef6a6a" } }
          Button { text: modelData.favorite ? "★" : "☆"; onClicked: root.rpc.call("profile.favorite", { profileId: modelData.id, favorite: !modelData.favorite }, function(result, error) { root.message = error ? error.message : ""; if (!error) root.refresh() }) }
          Button { text: "↑"; enabled: root.sortMode === "manual" && root.query === "" && root.groupFilter === "" && !root.favoritesOnly; onClicked: root.moveProfile(modelData.id, -1) }
          Button { text: "↓"; enabled: root.sortMode === "manual" && root.query === "" && root.groupFilter === "" && !root.favoritesOnly; onClicked: root.moveProfile(modelData.id, 1) }
          Button { text: "Use"; Accessible.name: "Select " + modelData.name; onClicked: root.selectedId = modelData.id }
          Button { text: modelData.enabled ? "On" : "Off"; onClicked: root.rpc.call("profile.enable", { profileId:modelData.id, enabled:!modelData.enabled }, function(result, error) { root.message = error ? error.message : ""; if (!error) root.refresh() }) }
          Button { text: "•••"; Accessible.name: "Open actions for " + modelData.name; onClicked: details.open() }
        }
        Dialog {
          id: details; title: modelData.name; modal: true; standardButtons: Dialog.Close
          contentItem: Column {
            spacing: 8
            Text { text: modelData.protocol + "  " + (modelData.server || "") + ":" + (modelData.port || ""); color: Color.foreground }
            Button { text: "TCP ping"; onClicked: root.rpc.call("test.tcp", { host:modelData.server || "", port:modelData.port || 443 }, function(result,error) { root.message = error ? error.message : ((result.ok ? "TCP reachable" : "TCP failed") + " • " + (result.latencyMs || "n/a") + " ms") }) }
            Button { text: "Validate core config"; onClicked: root.rpc.call("core.validate", { profileId:modelData.id }, function(result,error) { root.message = error ? error.message : (result.ok ? "Configuration accepted by " + result.core : "Configuration rejected") }) }
            Button { text: "Protocol fields"; onClicked: root.rpc.call("profile.schema", { protocol:modelData.protocol }, function(result,error) { subscriptionStatusLoader.item.contentItem.children[0].text = error ? error.message : JSON.stringify(result, null, 2); subscriptionStatusLoader.item.open() }) }
            Button { text: "Quick edit fields"; onClicked: { structuredEditor.load(modelData); structuredEditor.open() } }
            Button { text: "Proxy ping"; onClicked: root.rpc.call("test.proxy", {}, function(result,error) { root.message = error ? error.message : ((result.ok ? "Proxy reachable" : "Proxy failed") + " • " + (result.latencyMs || "n/a") + " ms") }) }
            Button { text: "Check external IP"; onClicked: root.rpc.call("test.ip", {}, function(result,error) { root.message = error ? error.message : (result.protected ? "Proxy IP: " + result.proxyIp : "Proxy is not changing the external IP") }) }
            Button { text: "Speed test"; onClicked: root.rpc.call("test.speed", {}, function(result,error) { root.message = error ? error.message : ((result.ok ? "Speed" : "Speed test failed") + " • " + Number(result.megabitsPerSecond || 0).toFixed(1) + " Mbps") }) }
            Button { text: "Test history"; onClicked: { details.close(); root.rpc.call("test.history", {}, function(result,error) { historyText.text = error ? error.message : JSON.stringify(result, null, 2); history.open() }) } }
            Button { text: "Clear health result"; onClicked: root.rpc.call("test.history.clear", { profileId:modelData.id }, function(result,error) { root.message = error ? error.message : "Health result cleared"; if (!error) root.refresh() }) }
          Button { text: "Edit"; Accessible.name: "Edit " + modelData.name; onClicked: { details.close(); nameEdit.text=modelData.name; groupEdit.text=modelData.group || ""; serverEdit.text=modelData.server || ""; portEdit.text=String(modelData.port || ""); fieldsEdit.text=JSON.stringify(modelData.fields || {}, null, 2); edit.open() } }
            Button { text: "Edit raw configuration"; onClicked: { rawEditorLoader.item.profileId = modelData.id; rawEditorLoader.item.contentItem.children[0].text = modelData.raw || ""; rawEditorLoader.item.open() } }
            Button { text: "Export"; onClicked: root.rpc.call("profile.export", { profileId: modelData.id }, function(result, error) { if (!error) exportText.text=result.payload || ""; exportDialog.open() }) }
            Button { text: "QR / share"; onClicked: root.rpc.call("profile.qr", { profileId: modelData.id }, function(result, error) { if (!error) qrText.text=result.payload || ""; qrDialog.open() }) }
            Button { text: "QR image"; onClicked: root.rpc.call("profile.qr.image", { profileId: modelData.id }, function(result, error) { if (error) root.message = error.message; else { qrImageLoader.item.contentItem.source = result.imagePath; qrImageLoader.item.open() } }) }
            Button { text: "Delete"; Accessible.name: "Delete " + modelData.name; onClicked: { details.close(); pendingDeleteId = modelData.id; pendingDeleteName = modelData.name; confirmDelete.open() } }
          }
        }
        Dialog { id: edit; title: "Edit profile"; modal: true; standardButtons: Dialog.Save | Dialog.Cancel; contentItem: Column { spacing: 8; Text { text: "Protocol: " + modelData.protocol + " • use Protocol fields for supported options"; color: Color.accent; wrapMode: Text.WordWrap } TextField { id: nameEdit; placeholderText: "Profile name" } TextField { id: groupEdit; placeholderText: "Group (optional)" } TextField { id: serverEdit; placeholderText: "Server" } TextField { id: portEdit; placeholderText: "Port"; inputMethodHints: Qt.ImhDigitsOnly } TextArea { id: fieldsEdit; width: 460; height: 180; placeholderText: "Protocol fields (JSON)"; selectByMouse: true } } onAccepted: { var fields; try { fields=JSON.parse(fieldsEdit.text || "{}"); } catch(e) { root.message="Invalid protocol fields JSON"; edit.open(); return } root.rpc.call("profile.update", { profile: { id:modelData.id, name:nameEdit.text, protocol:modelData.protocol, core:modelData.core, enabled:modelData.enabled, favorite:modelData.favorite, group:groupEdit.text.trim(), server:serverEdit.text, port:Number(portEdit.text), sourceId:modelData.sourceId, fields:fields, raw:modelData.raw } }, function(result,error) { if (error) root.message=error.message; else showSuccess("Profile saved"); if (!error) root.refresh() }) }
        Dialog { id: exportDialog; title: "Export payload"; modal: true; standardButtons: Dialog.Close; contentItem: TextArea { id: exportText; readOnly: true; wrapMode: TextEdit.Wrap; selectByMouse: true } }
        Dialog { id: qrDialog; title: "QR payload"; modal: true; standardButtons: Dialog.Close; contentItem: Column { spacing: 8; Text { text: "Use this payload with a QR scanner or copy it to another device."; color: Color.foreground; wrapMode: Text.WordWrap } TextArea { id: qrText; width: 400; height: 180; readOnly: true; wrapMode: TextEdit.Wrap; selectByMouse: true } } }
      }
    }
    Button { text: "Add profile"; onClicked: addDialog.open() }
    Button { text: "Subscriptions"; Accessible.name: "Manage subscriptions"; onClicked: { subscriptionManager.open() } }
    Button { text: "Subscription status"; onClicked: { root.rpc.call("subscription.list", {}, function(result, error) { subscriptionStatusLoader.item.contentItem.children[0].text = error ? error.message : JSON.stringify(result, null, 2); if (!error) root.refreshSubscriptions(); subscriptionStatusLoader.item.open() }) } }
    Button { text: "Refresh history"; onClicked: { root.refreshSubscriptions(); subscriptionHistoryView.open() } }
    Button { text: root.subscriptionRefreshing ? "Refreshing subscriptions…" : "Refresh all subscriptions"; Accessible.name: "Refresh all subscriptions"; enabled: !root.subscriptionRefreshing; onClicked: refreshAllSubscriptions() }
    Button { text: "Bulk TCP test"; Accessible.name: "Test TCP connectivity for all profiles"; onClicked: { root.rpc.call("test.bulk", { profileIds: root.profiles.map(function(p) { return p.id }) }, function(result, error) { subscriptionStatusLoader.item.contentItem.children[0].text = error ? error.message : JSON.stringify(result, null, 2); subscriptionStatusLoader.item.open() }) } }
    Button { text: "Clear all test history"; onClicked: clearHistoryConfirm.open() }
    Button { text: "Test all proxy connections"; onClicked: { root.rpc.call("test.bulk.proxy", { profileIds: root.profiles.map(function(p) { return p.id }) }, function(result, error) { if (!error) root.bulkResults = result.results || []; subscriptionStatusLoader.item.contentItem.children[0].text = error ? error.message : root.formatBulkResults(root.bulkResults); subscriptionStatusLoader.item.open() }) } }
    Button { text: "Use best working profile"; enabled: root.bulkResults.some(function(r) { return r.ok }); onClicked: { var candidates = root.bulkResults.filter(function(r) { return r.ok }).sort(function(a, b) { return Number(a.latencyMs || 999999) - Number(b.latencyMs || 999999) }); if (candidates.length) { root.selectedId = candidates[0].profileId; root.message = "Selected " + candidates[0].name + " (" + candidates[0].latencyMs + " ms)" } } }
    Button { text: "Sort results: " + root.bulkSortMode; enabled: root.bulkResults.length > 0; onClicked: { root.cycleBulkSort(); subscriptionStatusLoader.item.contentItem.children[0].text = root.formatBulkResults(root.bulkResults) } }
    Text { visible: root.bulkResults.length > 0; text: { var passing = root.bulkResults.filter(function(r) { return r.ok }).length; return "Health: " + passing + "/" + root.bulkResults.length + " passing • " + (root.bulkResults.length - passing) + " failing" }; color: root.bulkResults.every(function(r) { return r.ok }) ? "#74d99f" : "#efb06a" }
    Button { text: "Connect selected profile"; enabled: root.selectedId !== "" && !root.connected; onClicked: { root.rpc.call("profile.connect", { profileId: root.selectedId }, function(result, error) { root.message = error ? error.message : "Connection established"; if (!error) root.refreshStatus(); subscriptionStatusLoader.item.close() }) } }
    Button { text: "Cancel bulk test"; onClicked: root.rpc.call("test.bulk.cancel", {}, function(result, error) { root.message = error ? error.message : "Bulk test cancellation requested" }) }
    Text { text: root.subscriptionSummary; visible: text !== ""; color: root.subscriptionSummary.indexOf("errors") >= 0 ? "#ef6a6a" : Qt.darker(Color.foreground, 1.5) }
    Button { text: "Settings"; Accessible.name: "Open Rayarchy settings"; onClicked: settings.open() }
    Button { text: "Logs"; onClicked: { if (root.rpc) root.rpc.call("system.logs", {limit:200}, function(result,error) { logsText.text=error ? error.message : (result.lines || []).join("\n"); logs.open() }) } }
    Button { text: "Routing"; Accessible.name: "Manage routing rules"; onClicked: routing.open() }
    Button { text: "Backup"; onClicked: { if (root.rpc) root.rpc.call("backup.export", {}, function(result,error) { backupText.text=error ? error.message : JSON.stringify(result); backup.open() }) } }
  }
  property string pendingDeleteId: ""
  property string pendingDeleteName: ""
  Dialog { id: confirmDelete; modal: true; title: "Delete profile?"; standardButtons: Dialog.Yes | Dialog.No; contentItem: Text { text: "Delete “" + root.pendingDeleteName + "”? This cannot be undone."; color: Color.foreground; wrapMode: Text.WordWrap } onAccepted: root.rpc.call("profile.delete", { profileId: root.pendingDeleteId }, function(result,error) { root.message = error ? error.message : "Profile deleted"; if (!error) { root.selectedId = ""; root.refresh() } }) }
  Dialog { id: history; modal: true; title: "Test history"; standardButtons: Dialog.Close; contentItem: TextArea { id: historyText; width: 520; height: 300; readOnly: true; wrapMode: TextEdit.NoWrap; selectByMouse: true } }
  Dialog { id: clearHistoryConfirm; modal: true; title: "Clear test history?"; standardButtons: Dialog.Yes | Dialog.No; contentItem: Text { text: "Remove all saved connectivity and health test results?"; color: Color.foreground; wrapMode: Text.WordWrap } onAccepted: root.rpc.call("test.history.clear", {}, function(result,error) { if (error) root.message=error.message; else { root.bulkResults=[]; showSuccess("Test history cleared"); root.refresh() } }) }
  Dialog {
    id: addDialog
    modal: true
    title: "Add profile"
    standardButtons: Dialog.Ok | Dialog.Cancel
    property string previewText: ""
    contentItem: Column {
      spacing: 8
      TextArea { id: input; width: 520; height: 180; placeholderText: "Paste a vless://, vmess://, trojan://, ss://, JSON, or YAML configuration"; wrapMode: TextEdit.Wrap; selectByMouse: true }
      Button { text: "Preview parsed profiles"; onClicked: if (root.rpc) root.rpc.call("import.preview", { input: input.text }, function(result, error) { addDialog.previewText = error ? error.message : JSON.stringify(result, null, 2) }) }
      TextArea { width: 520; height: 150; text: addDialog.previewText; readOnly: true; wrapMode: TextEdit.Wrap; selectByMouse: true; placeholderText: "Preview results appear here" }
    }
    onAccepted: if (root.rpc) root.rpc.call("import.commit", { input: input.text }, function(result, error) { if (error) { root.message = error.message || "Import failed"; addDialog.open() } else { input.text = ""; addDialog.previewText = ""; showSuccess("Profiles imported"); root.refresh() } })
  }
  Dialog { id: subscriptions; modal: true; title: "Subscriptions"; standardButtons: Dialog.Close; property var items: []; onOpened: if (root.rpc) root.rpc.call("subscription.list", {}, function(result,error) { if (!error) subscriptions.items=result || [] }); contentItem: Column { spacing: 8; Text { text: "Configured sources"; color: Color.foreground } ListView { width: 430; height: Math.min(260, Math.max(70, subscriptions.items.length * 52)); model: subscriptions.items; delegate: Row { spacing: 6; width: parent.width; Text { width: 140; text: modelData.name; color: Color.foreground; elide: Text.ElideRight } Button { text: modelData.enabled ? "On" : "Off"; onClicked: root.rpc.call("subscription.update", { subscription:{id:modelData.id,name:modelData.name,url:modelData.url,enabled:!modelData.enabled,autoUpdate:modelData.autoUpdate || "daily",lastError:modelData.lastError} }, function(result,error) { if (error) root.message=error.message; else { showSuccess("Subscription updated"); subscriptions.open() } }) } Button { text: "Edit"; onClicked: { subEditId.text=modelData.id; subEditName.text=modelData.name; subEditUrl.text=modelData.url; subEditAuto.currentIndex=["off","startup","daily","every6_hours"].indexOf(modelData.autoUpdate || "daily"); subEdit.open() } } Button { text: "Refresh"; onClicked: root.rpc.call("subscription.refresh", { subscriptionId:modelData.id }, function(result,error) { if (error) root.message=error.message; else showSuccess("Updated " + (result.updated || 0) + " profiles"); root.refresh() }) } Button { text: "Delete"; onClicked: root.rpc.call("subscription.delete", { subscriptionId:modelData.id }, function(result,error) { if (error) root.message=error.message; else { subscriptions.items = subscriptions.items.filter(function(s) { return s.id !== modelData.id }); showSuccess("Subscription deleted"); root.refresh() } }) } } } TextField { id: subName; placeholderText: "New subscription name" } TextField { id: subUrl; placeholderText: "https://example/subscribe" } Button { text: "Add subscription"; onClicked: root.rpc.call("subscription.create", { subscription:{name:subName.text, url:subUrl.text, enabled:true, autoUpdate:"daily"} }, function(result,error) { if (error) root.message=error.message; else { subscriptions.items = subscriptions.items.concat([{id:result.subscriptionId,name:subName.text,url:subUrl.text,enabled:true}]); subName.text=""; subUrl.text=""; showSuccess("Subscription added") } }) } }
  }
  Dialog { id: subscriptionHistory; modal: true; title: "Subscription refresh history"; standardButtons: Dialog.Close; contentItem: ListView { width: 560; height: Math.min(360, Math.max(80, subscriptions.items.length * 54)); model: subscriptions.items; delegate: Column { width: parent.width; spacing: 2; Text { text: modelData.name; color: Color.foreground; font.bold: true } Text { text: modelData.lastRefreshAt ? "Last attempt: " + new Date(modelData.lastRefreshAt * 1000).toLocaleString() : "Never refreshed"; color: Qt.darker(Color.foreground, 1.4) } Text { visible: !!modelData.lastError; text: "Error: " + modelData.lastError; color: "#ef6a6a" } } } }
  SubscriptionHistoryView { id: subscriptionHistoryView; subscriptions: subscriptionManager.items }
  SubscriptionManager { id: subscriptionManager; rpc: root.rpc }
  Component.onCompleted: subscriptions.visible = false
  Dialog { id: subEdit; modal: true; title: "Edit subscription"; standardButtons: Dialog.Save | Dialog.Cancel; contentItem: Column { spacing: 8; TextField { id: subEditId; visible: false } TextField { id: subEditName; placeholderText: "Name" } TextField { id: subEditUrl; placeholderText: "https://example/subscribe" } ComboBox { id: subEditAuto; model: ["off", "startup", "daily", "every6_hours"] } } onAccepted: root.rpc.call("subscription.update", { subscription:{id:subEditId.text,name:subEditName.text,url:subEditUrl.text,enabled:true,autoUpdate:subEditAuto.currentText} }, function(result,error) { if (error) root.message = error.message; else showSuccess("Subscription saved"); if (!error) { subEdit.close(); subscriptions.open() } }) }
  Dialog {
    id: settings
    modal: true
    title: "Rayarchy settings"
    standardButtons: Dialog.Save | Dialog.Cancel
    property var values: ({})
    onOpened: if (root.rpc) root.rpc.call("settings.get", {}, function(result, error) {
      if (!error) {
        settings.values = result || {}
        mode.currentIndex = ["system_proxy", "local", "tun", "transparent"].indexOf(settings.values.connectionMode)
        core.currentIndex = ["auto", "sing-box", "xray"].indexOf(settings.values.preferredCore)
        port.text = String(settings.values.localPort || 1080)
        retention.text = String(settings.values.healthRetentionHours || 24)
        dns.checked = !!settings.values.dnsLeakProtection
        lan.checked = !!settings.values.lanBypass
      }
    })
    contentItem: Column {
      spacing: 8
      ComboBox { id: mode; model: ["system_proxy", "local", "tun", "transparent"] }
      ComboBox { id: core; model: ["auto", "sing-box", "xray"] }
      TextField { id: port; placeholderText: "Local proxy port"; inputMethodHints: Qt.ImhDigitsOnly }
      TextField { id: retention; placeholderText: "Health result retention (hours)"; inputMethodHints: Qt.ImhDigitsOnly }
      CheckBox { id: dns; text: "DNS leak protection" }
      CheckBox { id: lan; text: "Bypass LAN" }
    }
    onAccepted: { var localPort = Number(port.text); var hours = Number(retention.text); if (!Number.isInteger(localPort) || localPort < 1 || localPort > 65535) { root.message = "Local proxy port must be between 1 and 65535"; settings.open(); return } if (!Number.isInteger(hours) || hours < 1 || hours > 720) { root.message = "Health retention must be between 1 and 720 hours"; settings.open(); return } if (root.rpc) root.rpc.call("settings.update", { settings: { connectionMode: mode.currentText, preferredCore: core.currentText, localPort: localPort, healthRetentionHours: hours, killSwitch: false, dnsLeakProtection: dns.checked, lanBypass: lan.checked } }, function(result, error) {
      root.message = error ? error.message : "Settings saved"
      if (!error) settingsMessageTimer.restart()
      if (error) settings.open()
    }) }
  }
  Dialog { id: logs; modal: true; title: "Rayarchy logs"; standardButtons: Dialog.Close; contentItem: TextArea { id: logsText; width: 520; height: 300; readOnly: true; wrapMode: TextEdit.NoWrap; selectByMouse: true } }
  Dialog { id: routing; modal: true; title: "Routing rules"; standardButtons: Dialog.Close; property var rules: []; onOpened: if (root.rpc) root.rpc.call("routing.list", {}, function(result,error) { if (error) root.message=error.message; else routing.rules=result || [] }); contentItem: Column { spacing: 8; ListView { width: 460; height: Math.min(240, Math.max(60, routing.rules.length * 46)); model:routing.rules; delegate: Row { spacing:6; Text { width:260; text:modelData.name + " • " + modelData.value; color:Color.foreground; elide:Text.ElideRight } Button { text:modelData.action; enabled:false } Button { text:"Delete"; onClicked: root.rpc.call("routing.delete", {ruleId:modelData.id}, function(result,error) { if (error) root.message=error.message; else { routing.rules=routing.rules.filter(function(r){return r.id!==modelData.id}); showSuccess("Routing rule deleted") } }) } } } TextField { id:ruleName; placeholderText:"Rule name" } TextField { id:ruleValue; placeholderText:"Domain or CIDR" } ComboBox { id:ruleAction; model:["proxy","direct","block"] } Button { text:"Add domain/CIDR rule"; onClicked: root.rpc.call("routing.create", {rule:{name:ruleName.text, matchType:ruleValue.text.indexOf("/")>=0 ? "cidr" : "domain_suffix", value:ruleValue.text, action:ruleAction.currentText, enabled:true}}, function(result,error) { if (error) root.message=error.message; else { routing.rules=routing.rules.concat([{id:result.ruleId,name:ruleName.text,value:ruleValue.text,action:ruleAction.currentText}]); ruleName.text=""; ruleValue.text=""; showSuccess("Routing rule added") } }) } } }
  Dialog { id: backup; modal: true; title: "Backup / restore"; standardButtons: Dialog.Close; contentItem: Column { spacing:8; TextArea { id:backupText; width:520; height:220; wrapMode:TextEdit.NoWrap; selectByMouse:true } Button { text:"Restore this JSON"; onClicked: { var parsed; try { parsed=JSON.parse(backupText.text) } catch(e) { root.message="Invalid backup JSON"; return } root.rpc.call("backup.import", parsed, function(result,error) { if (error) root.message=error.message; else { showSuccess("Backup restored"); backup.close(); root.refresh() } }) } } } }
}
