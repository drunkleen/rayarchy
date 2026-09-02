import QtQuick
import Quickshell
import Quickshell.Io
Item { id: rpc; property bool connected: false; signal response(var result); function call(method, params, done) { done({"ok":false,"method":method}, null) } }
