import QtQuick
import QtQuick.Controls
import qs.Commons

Dialog {
    id: root
    modal: true
    title: "Protocol fields"
    standardButtons: Dialog.Save | Dialog.Cancel
    property var rpc: null
    property var profile: ({})
    signal saved
    function load(value) {
        profile = value || {};
        protocol.text = String(profile.protocol || "vless");
        user.text = profile.fields && profile.fields.user || "";
        password.text = profile.fields && profile.fields.password || "";
        method.text = profile.fields && profile.fields.method || "";
        security.text = profile.fields && (profile.fields.security || profile.fields.tls) || "";
        sni.text = profile.fields && profile.fields.sni || "";
        network.text = profile.fields && (profile.fields.type || profile.fields.network) || "";
        path.text = profile.fields && profile.fields.path || "";
        obfs.text = profile.fields && profile.fields.obfs || "";
        privateKey.text = profile.fields && profile.fields.private_key || "";
        publicKey.text = profile.fields && profile.fields.public_key || "";
        address.text = profile.fields && profile.fields.local_address || "";
    }
    contentItem: Column {
        spacing: 8
        Text {
            text: "Protocol: " + protocol.text
            color: Color.accent
        }
        TextField {
            id: protocol
            visible: false
        }
        TextField {
            id: user
            visible: ["vless", "vmess", "tuic", "anytls", "naive", "socks", "http"].indexOf(protocol.text) >= 0
            placeholderText: "UUID / user"
        }
        TextField {
            id: password
            visible: ["trojan", "shadowsocks", "hysteria2", "tuic", "anytls", "naive", "socks", "http"].indexOf(protocol.text) >= 0
            placeholderText: "Password"
            echoMode: TextInput.Password
        }
        TextField {
            id: method
            visible: protocol.text === "shadowsocks"
            placeholderText: "Encryption method"
        }
        TextField {
            id: security
            visible: ["vless", "vmess", "trojan", "hysteria2", "tuic", "anytls"].indexOf(protocol.text) >= 0
            placeholderText: "Security (tls/none)"
        }
        TextField {
            id: sni
            visible: ["vless", "vmess", "trojan", "hysteria2", "tuic"].indexOf(protocol.text) >= 0
            placeholderText: "SNI / server name"
        }
        TextField {
            id: network
            visible: ["vless", "vmess", "trojan"].indexOf(protocol.text) >= 0
            placeholderText: "Network (ws/tcp/grpc)"
        }
        TextField {
            id: path
            visible: network.visible && ["ws", "h2"].indexOf(network.text) >= 0
            placeholderText: "Path"
        }
        TextField {
            id: obfs
            visible: ["hysteria2", "tuic"].indexOf(protocol.text) >= 0
            placeholderText: "Obfuscation"
        }
        TextField {
            id: privateKey
            visible: protocol.text === "wireguard"
            placeholderText: "WireGuard private key"
            echoMode: TextInput.Password
        }
        TextField {
            id: publicKey
            visible: protocol.text === "wireguard"
            placeholderText: "WireGuard public key"
        }
        TextField {
            id: address
            visible: protocol.text === "wireguard"
            placeholderText: "WireGuard local address"
        }
    }
    onAccepted: {
        if (!rpc || !profile.id)
            return;
        rpc.call("profile.fields.update", {
            profileId: profile.id,
            fields: {
                user: user.text,
                password: password.text,
                method: method.text,
                security: security.text,
                sni: sni.text,
                type: network.text,
                path: path.text,
                obfs: obfs.text,
                private_key: privateKey.text,
                public_key: publicKey.text,
                local_address: address.text
            }
        }, function (result, error) {
            if (error)
                return;
            root.saved();
            root.close();
        });
    }
}
