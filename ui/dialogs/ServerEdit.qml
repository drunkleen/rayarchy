import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../controls/Common.js" as Common
import "../strings.js" as Strings
import "../controls"

// Add / edit server for every protocol. Fields switch per protocol; groups
// and proxy chains get a member picker. Saves via profile.create/update.
Sheet {
  id: dialog

  property var rpc: null
  property var app: null
  property string protocol: "vless"
  property var profile: null
  property var members: []
  property var strategy: "manual"
  property string core: "auto"
  property bool enabledFlag: true
  property string rawText: ""
  property var fields: ({})
  property var savedFields: ({})
  property bool saving: false

  title: (dialog.profile ? Strings.tr("editServer") : Strings.tr("serverEditTitle"))
    + " — " + Common.protocolLabel(dialog.protocol)

  width: Math.min(parent ? parent.width * 0.62 : 720, 780)
  height: Math.min(parent ? parent.height * 0.8 : 640, 700)

  Component.onCompleted: {
    if (dialog.profile) {
      dialog.fields = Common.clone(dialog.profile.fields || {})
      dialog.members = dialog.profile.members ? dialog.profile.members.slice() : []
      dialog.strategy = dialog.profile.strategy || "manual"
      dialog.core = dialog.profile.core || "auto"
      dialog.enabledFlag = dialog.profile.enabled !== false
      dialog.rawText = dialog.profile.raw || ""
    }
  }

  content: Component {
    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      // ---- common fields ----
      GridLayout {
        columns: 4
        columnSpacing: Style.space(10)
        rowSpacing: Style.space(8)
        Layout.fillWidth: true

        Text { text: Strings.tr("serverEditName"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          id: nameField
          Layout.columnSpan: 3
          Layout.fillWidth: true
          text: dialog.profile ? dialog.profile.name : ""
          placeholderText: "Remarks"
        }

        Text { text: Strings.tr("serverEditAddress"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          id: serverField
          Layout.fillWidth: true
          text: dialog.profile ? (dialog.profile.server || "") : ""
        }
        Text { text: Strings.tr("serverEditPort"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        TextField {
          id: portField
          Layout.preferredWidth: 90
          text: dialog.profile && dialog.profile.port ? String(dialog.profile.port) : ""
          validator: IntValidator { bottom: 1; top: 65535 }
        }

        Text { text: Strings.tr("serverEditCoreType"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        ComboBox {
          id: coreField
          Layout.fillWidth: true
          model: ["auto", "xray", "sing-box"]
          currentIndex: Math.max(0, ["auto", "xray", "sing-box"].indexOf(dialog.core))
        }
        Text { text: Strings.tr("enabled"); color: Color.foreground; font.pixelSize: Style.font.bodySmall }
        CheckBox {
          id: enabledField
          checked: dialog.enabledFlag
        }
        Item { Layout.columnSpan: 2 }
      }

      // ---- protocol-specific fields ----
      GridLayout {
        id: protoGrid
        columns: 4
        columnSpacing: Style.space(10)
        rowSpacing: Style.space(8)
        Layout.fillWidth: true

        Repeater {
          model: dialog.fieldModel
          delegate: ProtoField {
            required property var modelData
            key: modelData.key
            label: modelData.label
            options: modelData.options || []
            value: dialog.fields[modelData.key]
            onValueChanged: function (key, value) {
              dialog.fields[key] = value
            }
          }
        }
      }

      // ---- group / chain members ----
      Column {
        visible: dialog.protocol === "policy-group" || dialog.protocol === "proxy-chain"
        Layout.fillWidth: true
        spacing: Style.space(8)

        RowLayout {
          Layout.fillWidth: true
          Text {
            text: dialog.protocol === "policy-group" ? Strings.tr("serverEditMembers") : Strings.tr("serverEditMembers")
            color: Color.foreground
            font.pixelSize: Style.font.bodySmall
          }
          Item { Layout.fillWidth: true }
          Button {
            text: Strings.tr("add")
            flat: true
            onClicked: dialog.pickMembers()
          }
        }

        Column {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Repeater {
            model: dialog.memberNamesOut
            delegate: RowLayout {
              required property var modelData
              width: parent.width
              Text {
                text: modelData.name
                color: Color.foreground
                font.pixelSize: Style.font.bodySmall
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
              Button {
                text: "✕"
                flat: true
                onClicked: {
                  var arr = dialog.members
                  arr = arr.filter(function (id) { return String(id) !== String(modelData.id) })
                  dialog.members = arr
                }
              }
            }
          }
        }

        Text {
          text: Strings.tr("serverEditStrategy")
          color: Color.foreground
          font.pixelSize: Style.font.bodySmall
          visible: dialog.protocol === "policy-group"
        }
        ComboBox {
          visible: dialog.protocol === "policy-group"
          model: ["manual", "latency", "fallback", "load_balance"]
          currentIndex: Math.max(0, ["manual", "latency", "fallback", "load_balance"].indexOf(dialog.strategy))
          onActivated: dialog.strategy = currentText
        }
      }

      // ---- custom config ----
      Column {
        visible: dialog.protocol === "custom"
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.space(6)
        Text {
          text: Strings.tr("serverEditRaw")
          color: Color.foreground
          font.pixelSize: Style.font.bodySmall
        }
        TextArea {
          Layout.fillWidth: true
          Layout.fillHeight: true
          text: dialog.rawText
          placeholderText: "{ ... }"
          font.family: "monospace"
          onTextChanged: dialog.rawText = text
        }
      }

      Item { Layout.fillHeight: true }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Item { Layout.fillWidth: true }
        Button {
          text: Strings.tr("cancel")
          flat: true
          onClicked: dialog.closeRequested()
        }
        Button {
          text: Strings.tr("save")
          highlighted: true
          enabled: !dialog.saving
          onClicked: dialog.save()
        }
      }
    }
  }

  // ---- per-protocol field model ----
  readonly property var fieldModel: {
    switch (dialog.protocol) {
      case "vless": return [
        { key: "user", label: Strings.tr("serverEditUuid") },
        { key: "security", label: Strings.tr("serverEditSecurity"), options: ["none", "tls", "reality"] },
        { key: "sni", label: Strings.tr("serverEditSni") },
        { key: "flow", label: Strings.tr("serverEditFlow") },
        { key: "type", label: Strings.tr("serverEditNetwork"), options: ["tcp", "ws", "grpc", "http", "httpupgrade", "xhttp"] },
        { key: "host", label: Strings.tr("serverEditHost") },
        { key: "path", label: Strings.tr("serverEditPath") }
      ]
      case "vmess": return [
        { key: "user", label: Strings.tr("serverEditUuid") },
        { key: "aid", label: "Alter ID", numeric: true },
        { key: "security", label: Strings.tr("serverEditSecurity"), options: ["auto", "aes-128-gcm", "chacha20-poly1305", "none"] },
        { key: "tls", label: Strings.tr("serverEditTls"), options: ["none", "tls"] },
        { key: "sni", label: Strings.tr("serverEditSni") },
        { key: "type", label: Strings.tr("serverEditNetwork"), options: ["tcp", "ws", "grpc", "http", "httpupgrade", "xhttp"] },
        { key: "host", label: Strings.tr("serverEditHost") },
        { key: "path", label: Strings.tr("serverEditPath") }
      ]
      case "trojan": return [
        { key: "password", label: Strings.tr("serverEditPassword") },
        { key: "security", label: Strings.tr("serverEditSecurity"), options: ["none", "tls", "reality"] },
        { key: "sni", label: Strings.tr("serverEditSni") },
        { key: "flow", label: Strings.tr("serverEditFlow") },
        { key: "type", label: Strings.tr("serverEditNetwork"), options: ["tcp", "ws", "grpc", "http", "httpupgrade", "xhttp"] },
        { key: "host", label: Strings.tr("serverEditHost") },
        { key: "path", label: Strings.tr("serverEditPath") }
      ]
      case "shadowsocks": return [
        { key: "method", label: Strings.tr("serverEditMethod"), options: ["aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305", "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm"] },
        { key: "password", label: Strings.tr("serverEditPassword") }
      ]
      case "socks": case "http": return [
        { key: "user", label: Strings.tr("serverEditUser") },
        { key: "password", label: Strings.tr("serverEditPassword") }
      ]
      case "hysteria2": return [
        { key: "password", label: Strings.tr("serverEditPassword") },
        { key: "sni", label: Strings.tr("serverEditSni") },
        { key: "obfs", label: Strings.tr("serverEditObfs"), options: ["", "salamander", "gecko"] },
        { key: "obfs-password", label: Strings.tr("serverEditObfsPassword") }
      ]
      case "tuic": return [
        { key: "user", label: Strings.tr("serverEditUser") },
        { key: "password", label: Strings.tr("serverEditPassword") },
        { key: "congestion_control", label: "Congestion control", options: ["cubic", "new_reno", "bbr"] },
        { key: "sni", label: Strings.tr("serverEditSni") }
      ]
      case "wireguard": return [
        { key: "private_key", label: Strings.tr("serverEditPrivateKey") },
        { key: "public_key", label: Strings.tr("serverEditPublicKey") },
        { key: "local_address", label: Strings.tr("serverEditLocalAddress") },
        { key: "mtu", label: Strings.tr("serverEditMtu"), numeric: true }
      ]
      case "anytls": return [
        { key: "user", label: Strings.tr("serverEditUser") },
        { key: "password", label: Strings.tr("serverEditPassword") },
        { key: "sni", label: Strings.tr("serverEditSni") },
        { key: "idle_session_check_interval", label: "Idle check (s)", numeric: true }
      ]
      case "naive": return [
        { key: "user", label: Strings.tr("serverEditUser") },
        { key: "password", label: Strings.tr("serverEditPassword") }
      ]
      default: return []
    }
  }

  readonly property var memberNames: [] // kept for compat; memberNamesOut drives the list

  function fillMemberNames() {
    if (dialog.members.length === 0) { dialog.memberNamesOut = []; return }
    if (!dialog.rpc) return
    dialog.rpc.call("profile.list", {}, function (rows) {
      var out = []
      for (var i = 0; i < rows.length; i++) {
        if (dialog.members.indexOf(rows[i].id) !== -1) out.push({ id: rows[i].id, name: rows[i].name })
      }
      dialog.memberNamesOut = out
    })
  }

  property var memberNamesOut: []
  onMembersChanged: dialog.fillMemberNames()
  Component.onCompleted: dialog.fillMemberNames()

  function pickMembers() {
    var picker = dialog.app ? null : null
    if (!dialog.app) return
    dialog.app.sheetHost.open(Qt.createComponent("../dialogs/ProfilesSelect.qml"), {
      rpc: dialog.rpc, app: dialog.app, multiSelect: true, selectedIds: dialog.members,
      title: Strings.tr("profilesSelectTitle")
    }).thenSelect = function (ids) {
      dialog.members = ids
    }
  }

  function buildProfile() {
    var p = {}
    if (dialog.profile) p.id = dialog.profile.id
    p.name = nameField.text.trim() || Common.protocolLabel(dialog.protocol)
    p.protocol = dialog.protocol
    p.core = coreField.currentText === "auto" ? "auto" : coreField.currentText
    p.enabled = enabledField.checked
    p.favorite = dialog.profile ? !!dialog.profile.favorite : false
    p.group = dialog.profile ? (dialog.profile.group || "") : ""
    if (dialog.protocol !== "custom"
        && dialog.protocol !== "policy-group"
        && dialog.protocol !== "proxy-chain") {
      var server = serverField.text.trim()
      var port = parseInt(portField.text, 10)
      if (!server || isNaN(port)) {
        dialog.app.notify(Strings.tr("serverEditInvalid"))
        return null
      }
      p.server = server
      p.port = port
    } else {
      p.server = dialog.profile ? dialog.profile.server : null
      p.port = dialog.profile ? dialog.profile.port : null
    }
    p.fields = {}
    for (var key in dialog.fields) {
      var value = dialog.fields[key]
      if (value === undefined || value === null || value === "") continue
      p.fields[key] = value
    }
    if (dialog.protocol === "policy-group" || dialog.protocol === "proxy-chain") {
      p.members = dialog.members
      if (dialog.protocol === "policy-group") p.strategy = dialog.strategy
    }
    if (dialog.protocol === "custom") {
      p.raw = dialog.rawText.trim()
      if (!p.raw) {
        dialog.app.notify(Strings.tr("serverEditInvalid"))
        return null
      }
    }
    return Common.stripObject(p)
  }

  function save() {
    var p = dialog.buildProfile()
    if (!p) return
    dialog.saving = true
    var method = dialog.profile ? "profile.update" : "profile.create"
    dialog.rpc.call(method, { profile: p }, function (result) {
      dialog.saving = false
      if (result.error) {
        dialog.app.notify(Strings.tr("serverEditSaved") + ": " + result.error)
        return
      }
      dialog.closeRequested()
      dialog.app.notify(Strings.tr("serverEditSaved") + " ✓")
      dialog.app.refreshAll()
    })
  }

  // ProtoField: labelled input, combo for options, numeric for numbers.
  component ProtoField: RowLayout {
    id: pf
    required property string key
    required property string label
    property var options: []
    property bool numeric: false
    property var value: ""

    Layout.columnSpan: 4
    Layout.fillWidth: true
    spacing: Style.space(10)

    Text {
      text: pf.label
      color: Color.foreground
      font.pixelSize: Style.font.bodySmall
      Layout.preferredWidth: 140
    }

    Loader {
      Layout.fillWidth: true
      sourceComponent: pf.options.length > 0 ? comboComp : textComp
      property var currentValue: pf.value
    }

    Component {
      id: comboComp
      ComboBox {
        width: parent.width
        property var currentValue: pf.value
        model: pf.options
        Component.onCompleted: {
          var idx = pf.options.indexOf(String(pf.value))
          currentIndex = idx >= 0 ? idx : 0
        }
        onActivated: pf.valueChanged(pf.key, currentText)
      }
    }
    Component {
      id: textComp
      TextField {
        width: parent.width
        text: pf.value !== undefined && pf.value !== null ? String(pf.value) : ""
        validator: pf.numeric ? IntValidator { bottom: 0 } : null
        onTextEdited: pf.valueChanged(pf.key, text)
      }
    }

    signal valueChanged(string key, var value)
  }
}