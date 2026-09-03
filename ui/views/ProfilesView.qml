import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../controls/Common.js" as Common
import "../strings.js" as Strings
import "../controls"
import "../dialogs"

// The v2rayN server dashboard: subscription group chips, filter, toolbar
// test buttons, and the server table with its full context menu.
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

  property var columns: app ? app.uiState.columns : []

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
        row.todayUp = p.lastTest.todayUp
      }
      enriched.push(row)
    }
    root.profiles = enriched
  }

  onStatusChanged: root.refresh()
  onFilterTextChanged: refreshTimer.restart()

  Timer {
    id: refreshTimer
    interval: 500
    onTriggered: root.refresh()
  }

  Timer {
    id: pollTimer
    interval: 5000
    repeat: true
    running: true
    onTriggered: {
      if (!root.testing) root.refresh()
    }
  }

  // ---- toolbar --------------------------------------------------------------
  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)
      Layout.topMargin: Style.space(4)

      // Group chips
      ScrollView {
        Layout.preferredWidth: Math.min(root.width * 0.5, 460)
        Layout.preferredHeight: chipRow.height
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AlwaysOff

        RowLayout {
          id: chipRow
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

      Button {
        text: "✎"
        flat: true
        tooltip: Strings.tr("subEdit")
        onClicked: root.app.editSubscription(root.selectedGroup)
      }
      Button {
        text: "＋"
        flat: true
        tooltip: Strings.tr("subAdd")
        onClicked: root.app.addSubscription()
      }

      Item { Layout.fillWidth: true }

      TextField {
        id: filterField
        Layout.preferredWidth: 220
        placeholderText: Strings.tr("searchPlaceholder")
        onTextEdited: root.filterText = text
      }

      Button {
        text: "⇄"
        flat: true
        tooltip: Strings.tr("autofit")
        onClicked: root.app.autofitColumns()
      }
      Button {
        text: "⚡"
        flat: true
        tooltip: Strings.tr("fastRealPing")
        enabled: !root.testing
        onClicked: root.fastRealPing()
      }
      Button {
        text: "⧖"
        flat: true
        tooltip: Strings.tr("mixedTest")
        enabled: !root.testing
        onClicked: root.mixedTest()
      }
    }

    // ---- table ----------------------------------------------------------------
    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: "transparent"

      ServerTable {
        id: table
        anchors.fill: parent
        model: root.profiles
        columns: root.columns
        onRowActivated: function (profile) { root.app.activateProfile(profile) }
        onRowContextMenu: function (profile, x, y) {
          var pos = table.mapToItem(root.app.windowContent, x, y)
          root.rowMenu(profile, pos.x, pos.y)
        }
        onSelectionChanged: function (ids) { root.app.selection = ids }
        onHeaderClicked: function (column, index) { root.sortByColumn(column) }
        onColumnWidthChanged: function (index, width) {
          root.app.onColumnWidthChanged(index, width)
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

  function selectedProfiles() {
    var out = []
    for (var i = 0; i < root.profiles.length; i++) {
      if (table.isSelected(root.profiles[i].id)) out.push(root.profiles[i])
    }
    return out
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
    var sel = root.selectedProfiles()
    if (sel.length === 0) return
    var ids = sel.map(function (p) { return p.id })
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

  function sortByColumn(column) {
    if (column.key === "configType") {
      root.profiles.sort(function (a, b) { return a.protocol.localeCompare(b.protocol) })
    } else if (column.key === "delay") {
      root.profiles.sort(function (a, b) {
        var ad = a.lastTest ? a.lastTest.latencyMs : 999999
        var bd = b.lastTest ? b.lastTest.latencyMs : 999999
        return ad - bd
      })
    } else if (column.key === "speed") {
      root.profiles.sort(function (a, b) {
        var as = a.lastTest ? (a.lastTest.megabitsPerSecond || 0) : -1
        var bs = b.lastTest ? (b.lastTest.megabitsPerSecond || 0) : -1
        return bs - as
      })
    }
    root.profiles = root.profiles.slice()
  }

  // ---- context menu -----------------------------------------------------------
  function rowMenu(profile, x, y) {
    var ids = table.selectedIds
    var single = profile
    var isGroup = profile.protocol === "policy-group" || profile.protocol === "proxy-chain"
    var isComplex = profile.protocol === "custom" || isGroup

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
      { label: Strings.tr("speedTest"), action: "speed", enabled: ids.length === 1 },
      { label: Strings.tr("sortByDelay"), action: "sortByDelay", enabled: ids.length === 1 },
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
      case "speed": root.app.speedTestProfile(profile); break
      case "sortByDelay": root.sortByColumn({ key: "delay" }); break
      case "top": case "up": case "down": case "bottom":
        root.app.moveSelected(ids, item.action); break
      case "selectAll": table.selectAll(); break
      case "share": root.app.shareServer(profile, "raw"); break
      case "exportShare": root.app.shareServer(profile, "url"); break
      case "exportBase64": root.app.shareServer(profile, "base64"); break
      case "exportInner": root.app.shareServer(profile, "inner"); break
      default:
        if (String(item.action).indexOf("group:") === 0) {
          root.moveToGroup(String(item.action).slice(6))
        }
        break
    }
  }

  property string lastMoveGroup: ""

  function moveToGroup(target) {
    var ids = table.selectedIds
    root.lastMoveGroup = target
    root.app.moveToGroup(ids, target)
  }

  // Keyboard shortcuts: Ctrl+C export, Enter set default + connect behavior,
  // Delete remove, Ctrl+A select all, Ctrl+D edit, Ctrl+F share, etc.
  Keys.onPressed: function (event) {
    if (root.app && root.app.sheetHostOpen()) { event.accepted = false; return }
    var ctrl = event.modifiers & Qt.ControlModifier
    var key = event.key
    var sel = table.selectedIds
    var single = root.profiles[table.lastSelectedIndex]
    if (ctrl && key === Qt.Key_A) { table.selectAll(); event.accepted = true; return }
    if (ctrl && key === Qt.Key_C) { if (sel.length === 1 && single) { root.app.shareServer(single, "raw") } event.accepted = true; return }
    if (ctrl && key === Qt.Key_D) { if (sel.length === 1 && single) { root.app.editServer(single) } event.accepted = true; return }
    if (ctrl && key === Qt.Key_F) { if (sel.length === 1 && single) { root.app.shareServer(single, "url") } event.accepted = true; return }
    if (key === Qt.Key_Return) {
      if (sel.length === 1 && single) { root.app.activateProfile(single) } else if (single) { root.app.activateProfile(single) }
      event.accepted = true; return
    }
    if (key === Qt.Key_Delete || key === Qt.Key_Backspace) {
      if (sel.length > 0) { root.app.removeServers(sel) }
      event.accepted = true; return
    }
    if (ctrl && key === Qt.Key_O) { if (sel.length > 0) root.runBulk(sel, "test.bulk"); event.accepted = true; return }
    if (ctrl && key === Qt.Key_R) { if (sel.length > 0) root.runBulk(sel, "test.bulk.proxy"); event.accepted = true; return }
    if (ctrl && key === Qt.Key_T) { if (sel.length === 1 && single) root.app.speedTestProfile(single); event.accepted = true; return }
    if (key === Qt.Key_Escape) { root.app.contextMenuHide(); event.accepted = true; return }
  }
}