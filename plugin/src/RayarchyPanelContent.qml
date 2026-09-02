import QtQuick
import QtQuick.Controls
import qs.Commons

Item {
  id: root
  property var rpc: null
  property var profiles: []
  property var allProfiles: []
  property string query: ""
  property string groupFilter: ""
  property string sortMode: "manual"
  property bool favoritesOnly: false
  property bool connected: false
  property string selectedId: ""
  property string message: ""
  function refresh() {
    if (!root.rpc) return
    root.rpc.call("profile.list", {}, function(result, error) {
      if (!error) root.allProfiles = result || []
    })
    root.rpc.call("profile.list", { query: root.query, group: root.groupFilter, sort: root.sortMode, favoritesOnly: root.favoritesOnly }, function(result, error) {
      if (error) root.message = error.message
      else root.profiles = result || []
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
      if (!error) subscriptions.items = result || []
      else root.message = error.message || "Could not load subscriptions"
    })
  }
  Component.onCompleted: root.refresh()
  Connections { target: root.rpc; function onConnectedChanged() { if (root.rpc.connected) root.refresh() } }
  Timer { interval: 2000; repeat: true; running: root.visible; triggeredOnStart: true; onTriggered: root.refreshStatus() }
  Rectangle { anchors.fill: parent; color: Color.background }
  Loader { id: subscriptionStatusLoader; sourceComponent: Component { Dialog { modal: true; title: "Subscription status"; standardButtons: Dialog.Close; contentItem: TextArea { id: statusText; width: 520; height: 300; readOnly: true; wrapMode: TextEdit.NoWrap; selectByMouse: true } } } }
  Connections { target: subEdit; function onClosed() { root.refreshSubscriptions() } }
  Column {
    anchors.fill: parent; anchors.margins: 18; spacing: 12
    Row { spacing: 12; Text { text: "Rayarchy"; color: Color.foreground; font.bold: true; font.pixelSize: 22 } Button { text: root.connected ? "Disconnect" : "Connect"; enabled: root.selectedId !== "" || root.connected; onClicked: if (root.rpc) root.rpc.call(root.connected ? "profile.disconnect" : "profile.connect", root.connected ? {} : { profileId: root.selectedId }, function(result, error) { if (error) { root.message = error.message || "Connection failed" } else { root.message = root.connected ? "Disconnected" : "Connected"; root.refreshStatus() } }) } }
    TextField { width: parent.width; placeholderText: "Search profiles…"; onTextChanged: { root.query = text; root.refresh() } }
    Row {
      spacing: 8
      ComboBox { id: groupPicker; model: root.groups(); onActivated: { root.groupFilter = currentIndex === 0 ? "" : currentText; root.refresh() } }
      ComboBox { model: ["manual", "name", "server", "favorites"]; onActivated: { root.sortMode = currentText; root.refresh() } }
      CheckBox { text: "Favorites"; checked: root.favoritesOnly; onToggled: { root.favoritesOnly = checked; root.refresh() } }
    }
    Text { visible: root.profiles.length === 0; text: "No profiles yet. Add a profile or subscription to begin."; color: Color.foreground }
    Text { visible: root.message !== ""; text: root.message; color: Color.accent; width: parent.width; wrapMode: Text.WordWrap }
    ListView {
      width: parent.width; height: Math.max(80, parent.height - y - 54)
      model: root.profiles
      delegate: Rectangle {
        width: ListView.view.width; height: 58; color: "transparent"; border.color: Color.foreground; border.width: 1
        Row {
          anchors.fill: parent; anchors.margins: 8; spacing: 10
          Column { width: parent.width - 230; Text { text: modelData.name; color: Color.foreground; elide: Text.ElideRight } Text { text: (modelData.group ? modelData.group + " • " : "") + (modelData.server || "") + (modelData.port ? ":" + modelData.port : ""); color: Qt.darker(Color.foreground, 1.5) } }
          Button { text: modelData.favorite ? "★" : "☆"; onClicked: root.rpc.call("profile.favorite", { profileId: modelData.id, favorite: !modelData.favorite }, function(result, error) { root.message = error ? error.message : ""; if (!error) root.refresh() }) }
          Button { text: "↑"; enabled: root.sortMode === "manual" && root.query === "" && root.groupFilter === "" && !root.favoritesOnly; onClicked: root.moveProfile(modelData.id, -1) }
          Button { text: "↓"; enabled: root.sortMode === "manual" && root.query === "" && root.groupFilter === "" && !root.favoritesOnly; onClicked: root.moveProfile(modelData.id, 1) }
          Button { text: "Use"; onClicked: root.selectedId = modelData.id }
          Button { text: modelData.enabled ? "On" : "Off"; onClicked: root.rpc.call("profile.enable", { profileId:modelData.id, enabled:!modelData.enabled }, function(result, error) { root.message = error ? error.message : ""; if (!error) root.refresh() }) }
          Button { text: "•••"; onClicked: details.open() }
        }
        Dialog {
          id: details; title: modelData.name; modal: true; standardButtons: Dialog.Close
          contentItem: Column {
            spacing: 8
            Text { text: modelData.protocol + "  " + (modelData.server || "") + ":" + (modelData.port || ""); color: Color.foreground }
            Button { text: "TCP ping"; onClicked: root.rpc.call("test.tcp", { host:modelData.server || "", port:modelData.port || 443 }, function(result,error) { root.message = error ? error.message : ((result.ok ? "TCP reachable" : "TCP failed") + " • " + (result.latencyMs || "n/a") + " ms") }) }
            Button { text: "Validate core config"; onClicked: root.rpc.call("core.validate", { profileId:modelData.id }, function(result,error) { root.message = error ? error.message : (result.ok ? "Configuration accepted by " + result.core : "Configuration rejected") }) }
            Button { text: "Proxy ping"; onClicked: root.rpc.call("test.proxy", {}, function(result,error) { root.message = error ? error.message : ((result.ok ? "Proxy reachable" : "Proxy failed") + " • " + (result.latencyMs || "n/a") + " ms") }) }
            Button { text: "Check external IP"; onClicked: root.rpc.call("test.ip", {}, function(result,error) { root.message = error ? error.message : (result.protected ? "Proxy IP: " + result.proxyIp : "Proxy is not changing the external IP") }) }
            Button { text: "Speed test"; onClicked: root.rpc.call("test.speed", {}, function(result,error) { root.message = error ? error.message : ((result.ok ? "Speed" : "Speed test failed") + " • " + Number(result.megabitsPerSecond || 0).toFixed(1) + " Mbps") }) }
            Button { text: "Test history"; onClicked: { details.close(); root.rpc.call("test.history", {}, function(result,error) { historyText.text = error ? error.message : JSON.stringify(result, null, 2); history.open() }) } }
            Button { text: "Edit"; onClicked: { details.close(); nameEdit.text=modelData.name; groupEdit.text=modelData.group || ""; serverEdit.text=modelData.server || ""; portEdit.text=String(modelData.port || ""); fieldsEdit.text=JSON.stringify(modelData.fields || {}, null, 2); edit.open() } }
            Button { text: "Export"; onClicked: root.rpc.call("profile.export", { profileId: modelData.id }, function(result, error) { if (!error) exportText.text=result.payload || ""; exportDialog.open() }) }
            Button { text: "QR / share"; onClicked: root.rpc.call("profile.qr", { profileId: modelData.id }, function(result, error) { if (!error) qrText.text=result.payload || ""; qrDialog.open() }) }
            Button { text: "Delete"; onClicked: { details.close(); pendingDeleteId = modelData.id; pendingDeleteName = modelData.name; confirmDelete.open() } }
          }
        }
        Dialog { id: edit; title: "Edit profile"; modal: true; standardButtons: Dialog.Save | Dialog.Cancel; contentItem: Column { spacing: 8; TextField { id: nameEdit; placeholderText: "Profile name" } TextField { id: groupEdit; placeholderText: "Group (optional)" } TextField { id: serverEdit; placeholderText: "Server" } TextField { id: portEdit; placeholderText: "Port"; inputMethodHints: Qt.ImhDigitsOnly } TextArea { id: fieldsEdit; width: 460; height: 180; placeholderText: "Protocol fields (JSON)"; selectByMouse: true } } onAccepted: { var fields; try { fields=JSON.parse(fieldsEdit.text || "{}"); } catch(e) { root.message="Invalid protocol fields JSON"; edit.open(); return } root.rpc.call("profile.update", { profile: { id:modelData.id, name:nameEdit.text, protocol:modelData.protocol, core:modelData.core, enabled:modelData.enabled, favorite:modelData.favorite, group:groupEdit.text.trim(), server:serverEdit.text, port:Number(portEdit.text), sourceId:modelData.sourceId, fields:fields, raw:modelData.raw } }, function(result,error) { root.message=error ? error.message : "Profile saved"; if (!error) root.refresh() }) }
        Dialog { id: exportDialog; title: "Export payload"; modal: true; standardButtons: Dialog.Close; contentItem: TextArea { id: exportText; readOnly: true; wrapMode: TextEdit.Wrap; selectByMouse: true } }
        Dialog { id: qrDialog; title: "QR payload"; modal: true; standardButtons: Dialog.Close; contentItem: Column { spacing: 8; Text { text: "Use this payload with a QR scanner or copy it to another device."; color: Color.foreground; wrapMode: Text.WordWrap } TextArea { id: qrText; width: 400; height: 180; readOnly: true; wrapMode: TextEdit.Wrap; selectByMouse: true } } }
      }
    }
    Button { text: "Add profile"; onClicked: addDialog.open() }
    Button { text: "Subscriptions"; onClicked: { root.refreshSubscriptions(); subscriptions.open() } }
    Button { text: "Subscription status"; onClicked: { root.rpc.call("subscription.list", {}, function(result, error) { subscriptionStatusLoader.item.contentItem.children[0].text = error ? error.message : JSON.stringify(result, null, 2); subscriptionStatusLoader.item.open() }) } }
    Button { text: "Settings"; onClicked: settings.open() }
    Button { text: "Logs"; onClicked: { if (root.rpc) root.rpc.call("system.logs", {limit:200}, function(result,error) { logsText.text=error ? error.message : (result.lines || []).join("\n"); logs.open() }) } }
    Button { text: "Routing"; onClicked: routing.open() }
    Button { text: "Backup"; onClicked: { if (root.rpc) root.rpc.call("backup.export", {}, function(result,error) { backupText.text=error ? error.message : JSON.stringify(result); backup.open() }) } }
  }
  property string pendingDeleteId: ""
  property string pendingDeleteName: ""
  Dialog { id: confirmDelete; modal: true; title: "Delete profile?"; standardButtons: Dialog.Yes | Dialog.No; contentItem: Text { text: "Delete “" + root.pendingDeleteName + "”? This cannot be undone."; color: Color.foreground; wrapMode: Text.WordWrap } onAccepted: root.rpc.call("profile.delete", { profileId: root.pendingDeleteId }, function(result,error) { root.message = error ? error.message : "Profile deleted"; if (!error) { root.selectedId = ""; root.refresh() } }) }
  Dialog { id: history; modal: true; title: "Test history"; standardButtons: Dialog.Close; contentItem: TextArea { id: historyText; width: 520; height: 300; readOnly: true; wrapMode: TextEdit.NoWrap; selectByMouse: true } }
  Dialog { id: addDialog; modal: true; title: "Add profile"; standardButtons: Dialog.Ok | Dialog.Cancel; contentItem: TextArea { id: input; placeholderText: "Paste a vless://, vmess://, trojan://, ss://, JSON, or YAML configuration" } onAccepted: if (root.rpc) root.rpc.call("import.commit", { input: input.text }, function(result, error) { if (!error) { input.text = ""; root.refresh() } }) }
  Dialog { id: subscriptions; modal: true; title: "Subscriptions"; standardButtons: Dialog.Close; property var items: []; onOpened: if (root.rpc) root.rpc.call("subscription.list", {}, function(result,error) { if (!error) subscriptions.items=result || [] }); contentItem: Column { spacing: 8; Text { text: "Configured sources"; color: Color.foreground } ListView { width: 430; height: Math.min(260, Math.max(70, subscriptions.items.length * 52)); model: subscriptions.items; delegate: Row { spacing: 6; width: parent.width; Text { width: 140; text: modelData.name; color: Color.foreground; elide: Text.ElideRight } Button { text: modelData.enabled ? "On" : "Off"; onClicked: root.rpc.call("subscription.update", { subscription:{id:modelData.id,name:modelData.name,url:modelData.url,enabled:!modelData.enabled,autoUpdate:modelData.autoUpdate || "daily",lastError:modelData.lastError} }, function(result,error) { if (!error) subscriptions.open() }) } Button { text: "Edit"; onClicked: { subEditId.text=modelData.id; subEditName.text=modelData.name; subEditUrl.text=modelData.url; subEditAuto.currentIndex=["off","startup","daily","every6_hours"].indexOf(modelData.autoUpdate || "daily"); subEdit.open() } } Button { text: "Refresh"; onClicked: root.rpc.call("subscription.refresh", { subscriptionId:modelData.id }, function(result,error) { root.message = error ? error.message : "Updated " + (result.updated || 0) + " profiles"; root.refresh() }) } Button { text: "Delete"; onClicked: root.rpc.call("subscription.delete", { subscriptionId:modelData.id }, function() { subscriptions.items = subscriptions.items.filter(function(s) { return s.id !== modelData.id }); root.refresh() }) } } } TextField { id: subName; placeholderText: "New subscription name" } TextField { id: subUrl; placeholderText: "https://example/subscribe" } Button { text: "Add subscription"; onClicked: root.rpc.call("subscription.create", { subscription:{name:subName.text, url:subUrl.text, enabled:true, autoUpdate:"daily"} }, function(result,error) { if (!error) { subscriptions.items = subscriptions.items.concat([{id:result.subscriptionId,name:subName.text,url:subUrl.text,enabled:true}]); subName.text=""; subUrl.text="" } }) } }
  }
  Dialog { id: subEdit; modal: true; title: "Edit subscription"; standardButtons: Dialog.Save | Dialog.Cancel; contentItem: Column { spacing: 8; TextField { id: subEditId; visible: false } TextField { id: subEditName; placeholderText: "Name" } TextField { id: subEditUrl; placeholderText: "https://example/subscribe" } ComboBox { id: subEditAuto; model: ["off", "startup", "daily", "every6_hours"] } } onAccepted: root.rpc.call("subscription.update", { subscription:{id:subEditId.text,name:subEditName.text,url:subEditUrl.text,enabled:true,autoUpdate:subEditAuto.currentText} }, function(result,error) { root.message = error ? error.message : "Subscription saved"; if (!error) { subEdit.close(); subscriptions.open() } }) }
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
        dns.checked = !!settings.values.dnsLeakProtection
        lan.checked = !!settings.values.lanBypass
      }
    })
    contentItem: Column {
      spacing: 8
      ComboBox { id: mode; model: ["system_proxy", "local", "tun", "transparent"] }
      ComboBox { id: core; model: ["auto", "sing-box", "xray"] }
      TextField { id: port; placeholderText: "Local proxy port"; inputMethodHints: Qt.ImhDigitsOnly }
      CheckBox { id: dns; text: "DNS leak protection" }
      CheckBox { id: lan; text: "Bypass LAN" }
    }
    onAccepted: if (root.rpc) root.rpc.call("settings.update", { settings: { connectionMode: mode.currentText, preferredCore: core.currentText, localPort: Number(port.text), killSwitch: false, dnsLeakProtection: dns.checked, lanBypass: lan.checked } }, function(result, error) {
      root.message = error ? error.message : "Settings saved"
      if (error) settings.open()
    })
  }
  Dialog { id: logs; modal: true; title: "Rayarchy logs"; standardButtons: Dialog.Close; contentItem: TextArea { id: logsText; width: 520; height: 300; readOnly: true; wrapMode: TextEdit.NoWrap; selectByMouse: true } }
  Dialog { id: routing; modal: true; title: "Routing rules"; standardButtons: Dialog.Close; property var rules: []; onOpened: if (root.rpc) root.rpc.call("routing.list", {}, function(result,error) { if (!error) routing.rules=result || [] }); contentItem: Column { spacing: 8; ListView { width: 460; height: Math.min(240, Math.max(60, routing.rules.length * 46)); model:routing.rules; delegate: Row { spacing:6; Text { width:260; text:modelData.name + " • " + modelData.value; color:Color.foreground; elide:Text.ElideRight } Button { text:modelData.action; enabled:false } Button { text:"Delete"; onClicked: root.rpc.call("routing.delete", {ruleId:modelData.id}, function() { routing.rules=routing.rules.filter(function(r){return r.id!==modelData.id}) }) } } } TextField { id:ruleName; placeholderText:"Rule name" } TextField { id:ruleValue; placeholderText:"Domain or CIDR" } ComboBox { id:ruleAction; model:["proxy","direct","block"] } Button { text:"Add domain/CIDR rule"; onClicked: root.rpc.call("routing.create", {rule:{name:ruleName.text, matchType:ruleValue.text.indexOf("/")>=0 ? "cidr" : "domain_suffix", value:ruleValue.text, action:ruleAction.currentText, enabled:true}}, function(result,error) { if (!error) { routing.rules=routing.rules.concat([{id:result.ruleId,name:ruleName.text,value:ruleValue.text,action:ruleAction.currentText}]); ruleName.text=""; ruleValue.text="" } }) } } }
  Dialog { id: backup; modal: true; title: "Backup / restore"; standardButtons: Dialog.Close; contentItem: Column { spacing:8; TextArea { id:backupText; width:520; height:220; wrapMode:TextEdit.NoWrap; selectByMouse:true } Button { text:"Restore this JSON"; onClicked: { var parsed; try { parsed=JSON.parse(backupText.text) } catch(e) { root.message="Invalid backup JSON"; return } root.rpc.call("backup.import", parsed, function(result,error) { root.message=error ? error.message : "Backup restored"; if (!error) backup.close() }) } } } }
}
