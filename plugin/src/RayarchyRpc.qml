import QtQuick
import Quickshell
import Quickshell.Io
Item {
  id: rpc
  property bool connected: socket.connected
  property int nextId: 1
  property var pending: ({})
  readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rayarchy/rayarchy.sock"
  signal response(var result)
  signal eventReceived(var event)

  function call(method, params, done) {
    if (!socket.connected) { if (done) done(null, {"message":"Rayarchy daemon is not running"}); return }
    var id = rpc.nextId++
    rpc.pending[id] = done
    socket.write(JSON.stringify({jsonrpc:"2.0", id:id, method:method, params:params || {}}) + "\n")
    socket.flush()
  }
  function handle(line) {
    var obj; try { obj = JSON.parse(line) } catch (e) { return }
    if (obj.id !== undefined && rpc.pending[obj.id]) { var done=rpc.pending[obj.id]; delete rpc.pending[obj.id]; done(obj.result || null, obj.error || null); return }
    rpc.eventReceived(obj)
  }
  Socket {
    id: socket
    path: rpc.socketPath
    connected: false
    parser: SplitParser { splitMarker: "\n"; onRead: function(data) { rpc.handle(data) } }
    onConnectedChanged: rpc.connectedChanged()
  }
  Timer { interval: 1500; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!socket.connected) { socket.path=rpc.socketPath; socket.connected=true } }
}
