import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../strings.js" as Strings

// Subscriptions: list with add/edit/refresh/delete and update-all.
Item {
  id: root

  property var app: null
  property var rpc: null
  property var status: ({})

  property var subscriptions: []

  function refresh() {
    if (!root.rpc || !root.rpc.ready) return
    root.rpc.call("subscription.list", {}, function (subs) {
      root.subscriptions = subs || []
    })
  }

  Component.onCompleted: root.refresh()

  Timer {
    id: pollTimer
    interval: 10000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

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
        ToolTip.text: Strings.tr("subAdd")
        ToolTip.visible: hovered
        onClicked: root.app.addSubscription()
      }
      Button {
        text: "⟳"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight + 2
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("subUpdate")
        ToolTip.visible: hovered
        onClicked: root.app.updateAllSubscriptions()
      }
      Button {
        text: "🛠"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight + 2
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("subSetting")
        ToolTip.visible: hovered
        onClicked: root.app.openSubSetting()
      }
      Item { Layout.fillWidth: true }
      Text {
        text: root.subscriptions.length + " " + Strings.tr("subSetting")
        color: Color.muted
        font.pixelSize: Style.font.caption
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Util.alpha(Color.muted, 0.25)
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: "transparent"

      ListView {
        anchors.fill: parent
        anchors.margins: Style.space(6)
        clip: true
        model: root.subscriptions
        spacing: 4
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: SubRow {
          required property var modelData
          sub: modelData
          onEditRequested: root.app.editSubscription(modelData.id)
          onRefreshRequested: root.app.refreshSubscription(modelData.id)
          onDeleteRequested: root.app.deleteSubscription(modelData.id)
          onToggleEnabled: function (enabled) {
            var s = {}
            for (var k in modelData) s[k] = modelData[k]
            s.enabled = enabled
            root.rpc.call("subscription.update", { subscription: s }, function () { root.refresh() })
          }
        }
      }

      Column {
        anchors.centerIn: parent
        visible: root.subscriptions.length === 0
        spacing: Style.space(8)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "No subscriptions yet"
          color: Color.muted
          font.pixelSize: Style.font.body
        }
      }
    }
  }

  component SubRow: Item {
    id: row
    property var sub: ({})
    signal editRequested()
    signal refreshRequested()
    signal deleteRequested()
    signal toggleEnabled(bool enabled)

    implicitHeight: Style.space(56)
    width: parent ? parent.width : 0

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: mouse.hovered ? Util.alpha(Color.foreground, 0.05) : Util.alpha(Color.background, 0.3)
      border.color: Util.alpha(Color.muted, 0.3)
      border.width: 1
    }

    // Below the controls so the Switch and buttons receive their own clicks;
    // only empty row space falls through to the row-click/edit action.
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: row.editRequested()
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text {
            text: row.sub.name || "Subscription"
            color: Color.foreground
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
          Text {
            text: row.sub.enabled !== false ? "· " + Strings.tr("enabled") : "· " + Strings.tr("disabled")
            color: row.sub.enabled !== false ? Color.accent : Color.muted
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          text: {
            var parts = [row.sub.url || ""]
            if (row.sub.autoUpdate && row.sub.autoUpdate !== "off") parts.push(row.sub.autoUpdate)
            if (row.sub.lastRefreshAt) parts.push(row.sub.lastRefreshAt)
            if (row.sub.lastError) parts.push("✗ " + row.sub.lastError)
            return parts.join("  ·  ")
          }
          color: row.sub.lastError ? Color.urgent : Color.muted
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      Switch {
        checked: row.sub.enabled !== false
        onToggled: row.toggleEnabled(checked)
      }

      Button {
        text: "⟳"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("subRefresh")
        ToolTip.visible: hovered
        onClicked: row.refreshRequested()
      }
      Button {
        text: "✎"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("subEdit")
        ToolTip.visible: hovered
        onClicked: row.editRequested()
      }
      Button {
        text: "🗑"
        flat: true
        Layout.preferredWidth: Style.spacing.controlHeight
        Layout.preferredHeight: Style.spacing.controlHeight
        ToolTip.text: Strings.tr("subDelete")
        ToolTip.visible: hovered
        onClicked: row.deleteRequested()
      }
    }
  }
}