import QtQuick
import QtQuick.Controls
import qs.Commons

Dialog {
    id: root
    property var rpc: null
    property var items: []
    property string message: ""
    property string pendingDeleteId: ""
    property string pendingDeleteName: ""
    modal: true
    title: "Subscriptions"
    standardButtons: Dialog.Close

    function load() {
        if (rpc)
            rpc.call("subscription.list", {}, function (result, error) {
                if (error)
                    message = error.message;
                else
                    items = result || [];
            });
    }
    onOpened: load()

    contentItem: Column {
        spacing: 8
        Text {
            text: root.message
            visible: root.message !== ""
            color: "#ef6a6a"
            wrapMode: Text.WordWrap
        }
        ListView {
            width: 560
            height: Math.min(320, Math.max(80, root.items.length * 62))
            model: root.items
            delegate: Row {
                spacing: 6
                width: ListView.view.width
                Text {
                    width: 190
                    text: modelData.name
                    color: Color.foreground
                    elide: Text.ElideRight
                    Accessible.name: modelData.name
                }
                Text {
                    width: 170
                    text: modelData.lastRefreshAt ? new Date(modelData.lastRefreshAt * 1000).toLocaleString() : "Never refreshed"
                    color: Qt.darker(Color.foreground, 1.4)
                }
                Button {
                    text: modelData.enabled ? "On" : "Off"
                    Accessible.name: (modelData.enabled ? "Disable " : "Enable ") + modelData.name
                    onClicked: root.rpc.call("subscription.update", {
                        subscription: {
                            id: modelData.id,
                            name: modelData.name,
                            url: modelData.url,
                            enabled: !modelData.enabled,
                            autoUpdate: modelData.autoUpdate || "daily",
                            lastError: modelData.lastError,
                            lastRefreshAt: modelData.lastRefreshAt
                        }
                    }, function (result, error) {
                        if (error)
                            root.message = error.message;
                        else
                            root.load();
                    })
                }
                Button {
                    text: "Refresh"
                    Accessible.name: "Refresh " + modelData.name
                    onClicked: root.rpc.call("subscription.refresh", {
                        subscriptionId: modelData.id
                    }, function (result, error) {
                        if (error)
                            root.message = error.message;
                        else {
                            root.message = "Updated " + (result.updated || 0) + " profiles";
                            root.load();
                        }
                    })
                }
                Button {
                    text: "Edit"
                    Accessible.name: "Edit " + modelData.name
                    onClicked: {
                        editId.text = modelData.id;
                        editName.text = modelData.name;
                        editUrl.text = modelData.url;
                        editEnabled.checked = !!modelData.enabled;
                        editLastError.text = modelData.lastError || "";
                        editLastRefresh.text = modelData.lastRefreshAt === undefined || modelData.lastRefreshAt === null ? "" : String(modelData.lastRefreshAt);
                        editAuto.currentIndex = ["off", "startup", "daily", "every6_hours"].indexOf(modelData.autoUpdate || "daily");
                        edit.open();
                    }
                }
                Button {
                    text: "Delete"
                    Accessible.name: "Delete " + modelData.name
                    onClicked: {
                        root.pendingDeleteId = modelData.id;
                        root.pendingDeleteName = modelData.name;
                        deleteConfirm.open();
                    }
                }
            }
        }
        TextField {
            id: name
            placeholderText: "New subscription name"
            Accessible.name: "New subscription name"
        }
        TextField {
            id: url
            placeholderText: "https://example/subscribe"
            Accessible.name: "New subscription URL"
        }
        Button {
            text: "Add subscription"
            Accessible.name: "Add subscription"
            onClicked: root.rpc.call("subscription.create", {
                subscription: {
                    name: name.text,
                    url: url.text,
                    enabled: true,
                    autoUpdate: "daily"
                }
            }, function (result, error) {
                if (error)
                    root.message = error.message;
                else {
                    name.text = "";
                    url.text = "";
                    root.message = "Subscription added";
                    root.load();
                }
            })
        }
    }

    Dialog {
        id: deleteConfirm
        modal: true
        title: "Delete subscription?"
        width: Math.min(Style.space(560), Math.max(Style.space(320), root.width - Style.space(24)))
        standardButtons: Dialog.Yes | Dialog.No
        contentItem: Text {
            text: "Delete “" + root.pendingDeleteName + "”? This cannot be undone."
            color: Color.foreground
            wrapMode: Text.WordWrap
        }
        onAccepted: root.rpc.call("subscription.delete", {
            subscriptionId: root.pendingDeleteId
        }, function (result, error) {
            if (error)
                root.message = error.message;
            else {
                root.message = "Subscription deleted";
                root.load();
            }
            root.pendingDeleteId = "";
            root.pendingDeleteName = "";
        })
    }

    Dialog {
        id: edit
        modal: true
        title: "Edit subscription"
        standardButtons: Dialog.Save | Dialog.Cancel
        contentItem: Column {
            spacing: 8
            TextField {
                id: editId
                visible: false
            }
            TextField {
                id: editName
                placeholderText: "Name"
            }
            TextField {
                id: editUrl
                placeholderText: "https://example/subscribe"
            }
            CheckBox {
                id: editEnabled
                text: "Enabled"
            }
            ComboBox {
                id: editAuto
                model: ["off", "startup", "daily", "every6_hours"]
            }
            TextField {
                id: editLastError
                visible: false
            }
            TextField {
                id: editLastRefresh
                visible: false
            }
        }
        onAccepted: root.rpc.call("subscription.update", {
            subscription: {
                id: editId.text,
                name: editName.text,
                url: editUrl.text,
                enabled: editEnabled.checked,
                autoUpdate: editAuto.currentText,
                lastError: editLastError.text === "" ? null : editLastError.text,
                lastRefreshAt: editLastRefresh.text === "" ? null : Number(editLastRefresh.text)
            }
        }, function (result, error) {
            if (error)
                root.message = error.message;
            else {
                root.message = "Subscription saved";
                edit.close();
                root.load();
            }
        })
    }
}
