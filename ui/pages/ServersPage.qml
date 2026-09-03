import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../controls/Common.js" as Common
import "../strings.js" as Strings

// Compact server list: searchable rows with a subscription group filter.
// Left-click selects, double-click connects, right-click opens the full
// v2rayN-style context menu.
Item {
  id: root

  property var app: null
  property var rpc: null
  property var status: ({})

  property var subscriptions: []
  property var profiles: []
  property string selectedGroup: ""
  property string filterText: ""
  property bool testing: false
  property var selectedIds: []
  property string lastMoveGroup: ""

  function refresh() {
    if (!root.rpc || !root.rpc.ready) return
    root.rpc.call("subscription.list", {}, function (subs) {
      root.subscriptions = subs || []
    })
    var params = { query: root.filterText, group: root.selectedGroup }
    root.rpc.call("profile.list", params, function (rows) {
      root.enrichProfiles(rows || [])
    })
  }

  function enrichProfiles(rows) {
    var subsByName = {}
    for (var i = 0; i < root.subscriptions.length; i++) {
      subsByName[root.subscriptions[i].id] = root.subscriptions[i].name
    }
    var connectedId = root.status.profileId || null
    var enriched = []
    for (var j = 0; j < rows.length; j++) {
      var p = rows[j]
      var row = Common.clone(p)
      row.subRemarks = p.sourceId && subsByName[p.sourceId] ? subsByName[p.sourceId] : ""
      row.connected = connectedId !== null && String(p.id) === String(connectedId)
      if (p.lastTest) {
        row.ipInfo = p.lastTest.ipInfo || ""
      }
      enriched.push(row)
    }
    root.profiles = enriched
    // prune selection of rows no longer present
    var pruned = []
    for (var k = 0; k < root.selectedIds.length; k++) {
      for (var m = 0; m < enriched.length; m++) {
        if (String(enriched[m].id) === String(root.selectedIds[k])) { pruned.push(root.selectedIds[k]); break }
      }
    }
    root.selectedIds = pruned
  }

  onStatusChanged: root.refresh()
  onFilterTextChanged: refreshTimer.restart()

  Timer { id: refreshTimer; interval: 400; onTriggered: root.refresh() }
  Timer {
    id: pollTimer
    interval: 5000
    repeat: true
    running: true
    onTriggered: { if (!root.testing) root.refresh() }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    // ---- header toolbar ----
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)
      Layout.topMargin: Style.space(8)
      Layout.leftMargin: Style.space(8)
      Layout.rightMargin: Style.space(8)
      Layout.bottomMargin: Style.space(6)

      Button {
        text: "＋"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight + 2
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("serverEditTitle")
        ToolTip.visible: hovered
        onClicked: root.app.openAddServer()
      }
      Button {
        text: "⧉"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight + 2
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("importFromClipboard")
        ToolTip.visible: hovered
        onClicked: root.app.importClipboard()
      }
      Button {
        text: "🖼"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight + 2
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("importFromImage")
        ToolTip.visible: hovered
        onClicked: root.app.importImage()
      }
      Button {
        text: "⚡"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight + 2
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("fastRealPing")
        ToolTip.visible: hovered
        enabled: !root.testing
        onClicked: root.fastRealPing()
      }
      Button {
        text: "⧖"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight + 2
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("mixedTest")
        ToolTip.visible: hovered
        enabled: !root.testing
        onClicked: root.mixedTest()
      }

      Item { Layout.fillWidth: true }

      TextField {
        id: filterField
        Layout.preferredWidth: 150
        Layout.preferredHeight: Style.spacing.controlHeight
        placeholderText: Strings.tr("searchPlaceholder")
        onTextEdited: root.filterText = text
      }
    }

    // ---- group chips ----
    ScrollView {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.spacing.controlHeight + Style.space(4)
      Layout.leftMargin: Style.space(8)
      Layout.rightMargin: Style.space(8)
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: ScrollBar.AlwaysOff

      RowLayout {
        spacing: Style.space(4)
        GroupChip {
          label: Strings.tr("group")
          selected: root.selectedGroup === ""
          onClicked: { root.selectedGroup = ""; root.refresh() }
        }
        Repeater {
          model: root.subscriptions
          delegate: GroupChip {
            required property var modelData
            label: modelData.name
            selected: root.selectedGroup === modelData.id
            onClicked: { root.selectedGroup = modelData.id; root.refresh() }
            onContextMenuRequested: function (x, y) {
              root.subChipMenu(modelData, x, y)
            }
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Util.alpha(Color.muted, 0.25)
    }

    // ---- list ----
    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: "transparent"

      ListView {
        id: listView
        anchors.fill: parent
        anchors.margins: Style.space(4)
        clip: true
        model: root.profiles
        spacing: 2
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: ServerRow {
          required property var modelData
          profile: modelData
          selected: root.selectedIds.indexOf(String(modelData.id)) !== -1
          connected: modelData.connected === true
          onClicked: root.toggleSelect(String(modelData.id))
          onDoubleClicked: root.app.activateProfile(modelData)
          onContextMenuRequested: function (x, y) {
            var pos = serverRowMouse.mapToItem(root.app.contentArea, x, y)
            root.rowMenu(modelData, pos.x, pos.y)
          }
        }
      }

      Column {
        anchors.centerIn: parent
        visible: root.profiles.length === 0
        spacing: Style.space(8)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Strings.tr("empty")
          color: Color.muted
          font.pixelSize: Style.font.body
        }
      }
    }

    // ---- selection action bar ----
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: root.selectedIds.length > 0 ? Style.spacing.controlHeight : 0
      color: Util.alpha(Color.foreground, 0.05)
      visible: root.selectedIds.length > 0

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(4)
        Text {
          text: root.selectedIds.length + " ·"
          color: Color.muted
          font.pixelSize: Style.font.caption
        }
        ActionChip { label: Strings.tr("editServer"); onClicked: root.singleAction("edit") }
        ActionChip { label: Strings.tr("copyServer"); onClicked: root.singleAction("copy") }
        ActionChip { label: Strings.tr("removeServer"); onClicked: root.multiAction("remove") }
        ActionChip { label: Strings.tr("tcping"); onClicked: root.multiAction("tcping") }
        ActionChip { label: Strings.tr("speedTest"); onClicked: root.singleAction("speed") }
        ActionChip { label: Strings.tr("udpTest"); onClicked: root.singleAction("udp") }
        ActionChip { label: Strings.tr("shareServer"); onClicked: root.singleAction("share") }
        Item { Layout.fillWidth: true }
      }
    }
  }

  // ---- row component ----
  component ServerRow: Item {
    id: row
    property var profile: ({})
    property bool selected: false
    property bool connected: false
    signal clicked()
    signal doubleClicked()
    signal contextMenuRequested(real x, real y)

    implicitHeight: Style.space(46)
    width: parent ? parent.width : 0

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: row.connected
        ? Util.alpha(Color.accent, 0.16)
        : (row.selected ? Util.alpha(Color.foreground, 0.10) : (mouse.hovered ? Util.alpha(Color.foreground, 0.05) : "transparent"))
      border.color: row.connected ? Color.accent : (row.selected ? Util.alpha(Color.foreground, 0.4) : "transparent")
      border.width: 1
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Rectangle {
        Layout.preferredWidth: 8
        Layout.preferredHeight: 8
        radius: 4
        color: Common.protocolColor(row.profile.protocol)
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text {
            text: row.profile.name || ""
            color: Color.foreground
            font.pixelSize: Style.font.bodySmall
            font.bold: row.connected
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
          Text {
            text: Common.protocolLabel(row.profile.protocol)
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: row.profile.favorite
            text: "★"
            color: Color.accent
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          text: {
            var s = row.profile.server || ""
            if (row.profile.port) s += ":" + row.profile.port
            if (row.profile.subRemarks) s += "  ·  " + row.profile.subRemarks
            return s
          }
          color: Color.muted
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      Text {
        text: row.profile.lastTest && row.profile.lastTest.ok
          ? row.profile.lastTest.latencyMs + " ms"
          : (row.profile.lastTest ? "✗" : "")
        color: row.profile.lastTest && row.profile.lastTest.ok ? Color.accent : Color.urgent
        font.pixelSize: Style.font.caption
      }
      Text {
        text: row.connected ? "●" : ""
        color: Color.accent
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: serverRowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function (mouse) {
        if (mouse.button === Qt.RightButton) row.contextMenuRequested(mouse.x, mouse.y)
        else row.clicked()
      }
      onDoubleClicked: function (mouse) {
        if (mouse.button === Qt.LeftButton) row.doubleClicked()
      }
    }
  }

  component GroupChip: Item {
    id: chip
    property string label: ""
    property bool selected: false
    signal clicked()
    signal contextMenuRequested(int x, int y)

    width: chipLabel.implicitWidth + Style.space(16)
    height: Style.spacing.controlHeight

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: chip.selected
        ? Util.alpha(Color.accent, 0.22)
        : (chipHover.hovered ? Util.alpha(Color.foreground, 0.08) : "transparent")
      border.color: chip.selected ? Color.accent : "transparent"
      border.width: 1
    }
    Text {
      id: chipLabel
      anchors.centerIn: parent
      text: chip.label
      color: chip.selected ? Color.accent : Color.foreground
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
    MouseArea {
      id: chipHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function (mouse) {
        if (mouse.button === Qt.RightButton) chip.contextMenuRequested(mouse.x, mouse.y)
        else chip.clicked()
      }
    }
  }

  component ActionChip: Item {
    id: action
    property string label: ""
    signal clicked()
    Layout.preferredHeight: Style.spacing.controlHeight - 6
    implicitWidth: actionLabel.implicitWidth + Style.space(12)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: mouse.hovered || mouse.pressed
        ? Util.alpha(Color.foreground, mouse.pressed ? 0.14 : 0.07)
        : "transparent"
    }
    Text {
      id: actionLabel
      anchors.centerIn: parent
      text: action.label
      color: Color.foreground
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: action.clicked()
    }
  }

  // ---- selection + actions --------------------------------------------------
  function toggleSelect(id) {
    var idx = root.selectedIds.indexOf(String(id))
    if (idx === -1) root.selectedIds = root.selectedIds.concat([String(id)])
    else {
      var arr = root.selectedIds.slice()
      arr.splice(idx, 1)
      root.selectedIds = arr
    }
  }

  function profileById(id) {
    for (var i = 0; i < root.profiles.length; i++) {
      if (String(root.profiles[i].id) === String(id)) return root.profiles[i]
    }
    return null
  }

  function singleProfile() {
    if (root.selectedIds.length !== 1) return null
    return root.profileById(root.selectedIds[0])
  }

  function singleAction(kind) {
    var p = root.singleProfile()
    if (!p) return
    switch (kind) {
      case "edit": root.app.editServer(p); break
      case "copy": root.app.copyServer(p); break
      case "speed": root.app.speedTestProfile(p); break
      case "udp": root.app.udpTestProfile(p); break
      case "share": root.app.shareServer(p, "raw"); break
    }
  }

  function multiAction(kind) {
    var ids = root.selectedIds
    if (ids.length === 0) return
    switch (kind) {
      case "remove": root.app.removeServers(ids); break
      case "tcping": root.runBulk(ids, "test.bulk"); break
      case "realping": root.runBulk(ids, "test.bulk.proxy"); break
    }
  }

  function fastRealPing() {
    var ids = []
    for (var i = 0; i < root.profiles.length; i++) {
      if (root.profiles[i].enabled) ids.push(root.profiles[i].id)
    }
    if (ids.length === 0) return
    root.runBulk(ids, "test.bulk")
  }

  function mixedTest() {
    var ids = root.selectedIds
    if (ids.length === 0) {
      for (var i = 0; i < root.profiles.length; i++) ids.push(root.profiles[i].id)
    }
    if (ids.length === 0) return
    root.runBulk(ids, "test.bulk.proxy")
  }

  function runBulk(ids, method) {
    root.testing = true
    root.app.notify("Testing…")
    root.rpc.call(method, { profileIds: ids }, function () {
      root.testing = false
      root.app.notify(Strings.tr("done"))
      root.refresh()
      root.app.refreshStatus()
    }, function (error) {
      root.testing = false
      root.app.notify("Error: " + error)
    })
  }

  function subChipMenu(sub, x, y) {
    var items = [
      { label: Strings.tr("subRefresh"), action: "refresh", enabled: sub.enabled },
      { label: Strings.tr("subEdit"), action: "edit" },
      { label: Strings.tr("subDelete"), action: "delete", enabled: true }
    ]
    root.app.contextMenu(items, x, y, function (item) {
      switch (item.action) {
        case "refresh": root.app.refreshSubscription(sub.id); break
        case "edit": root.app.editSubscription(sub.id); break
        case "delete": root.app.deleteSubscription(sub.id); break
      }
    })
  }

  function rowMenu(profile, x, y) {
    var ids = root.selectedIds
    if (ids.indexOf(String(profile.id)) === -1) ids = [String(profile.id)]
    var single = profile
    var isGroup = profile.protocol === "policy-group" || profile.protocol === "proxy-chain"

    var items = [
      { label: Strings.tr("setDefaultServer"), action: "default", checked: !!profile.default },
      { label: Strings.tr("editServer"), action: "edit" },
      { label: Strings.tr("copyServer"), action: "copy" },
      { label: Strings.tr("removeServer"), action: "remove" },
      { label: Strings.tr("removeDuplicate"), action: "dedup", enabled: ids.length === 1 },
      { label: Strings.tr("removeInvalid"), action: "removeInvalid", enabled: ids.length === 1 },
      { separator: true },
      { label: Strings.tr("tcping"), action: "tcping" },
      { label: Strings.tr("realPing"), action: "realping" },
      { label: Strings.tr("udpTest"), action: "udp", enabled: ids.length === 1 },
      { label: Strings.tr("speedTest"), action: "speed", enabled: ids.length === 1 },
      { separator: true },
      { label: Strings.tr("moveToGroup"), action: "moveGroup", submenu: root.moveGroupMenu() },
      { label: Strings.tr("moveTop"), action: "top", enabled: ids.length === 1 },
      { label: Strings.tr("moveUp"), action: "up", enabled: ids.length === 1 },
      { label: Strings.tr("moveDown"), action: "down", enabled: ids.length === 1 },
      { label: Strings.tr("moveBottom"), action: "bottom", enabled: ids.length === 1 },
      { label: Strings.tr("selectAll"), action: "selectAll" },
      { separator: true },
      { label: Strings.tr("shareServer"), action: "share", enabled: ids.length === 1 },
      { label: Strings.tr("exportShareUrl"), action: "exportShare", enabled: ids.length === 1 },
      { label: Strings.tr("exportShareUrlBase64"), action: "exportBase64", enabled: ids.length === 1 },
      { label: Strings.tr("exportInnerUri"), action: "exportInner", enabled: ids.length === 1 }
    ]

    root.app.contextMenu(items, x, y, function (item) {
      root.handleRowAction(item, single, ids)
    })
  }

  function moveGroupMenu() {
    var out = []
    for (var i = 0; i < root.subscriptions.length; i++) {
      out.push({ label: root.subscriptions[i].name, action: "group:" + root.subscriptions[i].id })
    }
    out.push({ label: Strings.tr("group"), action: "group:" })
    return out
  }

  function handleRowAction(item, profile, ids) {
    switch (item.action) {
      case "default": root.app.setDefault(profile.id); break
      case "edit": root.app.editServer(profile); break
      case "copy": root.app.copyServer(profile); break
      case "remove": root.app.removeServers(ids); break
      case "dedup": root.app.removeDuplicates(); break
      case "removeInvalid": root.app.removeInvalid(profile); break
      case "tcping": root.runBulk(ids, "test.bulk"); break
      case "realping": root.runBulk(ids, "test.bulk.proxy"); break
      case "udp": root.app.udpTestProfile(profile); break
      case "speed": root.app.speedTestProfile(profile); break
      case "top": case "up": case "down": case "bottom":
        root.app.moveSelected(ids, item.action); break
      case "selectAll":
        var all = []
        for (var i = 0; i < root.profiles.length; i++) all.push(String(root.profiles[i].id))
        root.selectedIds = all
        break
      case "share": root.app.shareServer(profile, "raw"); break
      case "exportShare": root.app.shareServer(profile, "url"); break
      case "exportBase64": root.app.shareServer(profile, "base64"); break
      case "exportInner": root.app.shareServer(profile, "inner"); break
      default:
        if (String(item.action).indexOf("group:") === 0) {
          var target = String(item.action).slice(6)
          root.app.moveToGroup(ids, target)
        }
        break
    }
  }

  Keys.onPressed: function (event) {
    var ctrl = event.modifiers & Qt.ControlModifier
    if (event.key === Qt.Key_Escape) { root.app.contextMenuHide(); event.accepted = true; return }
    if (root.selectedIds.length === 1) {
      var p = root.singleProfile()
      if (ctrl && event.key === Qt.Key_C) { if (p) root.app.shareServer(p, "raw"); event.accepted = true; return }
      if (ctrl && event.key === Qt.Key_D) { if (p) root.app.editServer(p); event.accepted = true; return }
      if (event.key === Qt.Key_Return) { if (p) root.app.activateProfile(p); event.accepted = true; return }
    }
    if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
      if (root.selectedIds.length > 0) root.app.removeServers(root.selectedIds)
      event.accepted = true; return
    }
  }
}