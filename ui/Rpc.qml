import QtQuick
import Quickshell.Io
import "strings.js" as Strings

// JSON-RPC 2.0 client over the Rayarchy daemon's newline-delimited Unix
// socket. Keeps one persistent connection, queues requests until the socket
// is up, and starts the daemon (systemd --user unit, falling back to a direct
// spawn) when it is not running yet.
Item {
  id: root

  property bool connected: false
  property bool starting: false
  property string socketPath: ""
  property string startError: ""
  // 0 = idle, 1 = connecting, 2 = starting daemon
  property int state: 0
  readonly property bool ready: connected && !starting

  signal response(var method, var result)
  signal statusChanged()

  function setSocketPath(path) {
    root.socketPath = path
    socket.path = path
    root.retry()
  }

  function retry() {
    if (root.socketPath === "") return
    socket.path = root.socketPath
    socket.connected = true
  }

  function onConnectedChanged() {
    if (socket.connected) {
      root.connected = true
      root.starting = false
      root.startError = ""
      root.state = 1
      flushQueue()
      root.statusChanged()
    } else {
      root.connected = false
      root.state = 0
      root.statusChanged()
    }
  }

  function onSocketError(error) {
    if (root.connected) return
    if (root.starting) {
      // A request is pending but the daemon is not reachable; surface it once.
      root.startError = Strings.tr("daemonUnreachable")
    }
    ensureDaemon()
  }

  function ensureDaemon() {
    if (root.starting) return
    root.starting = true
    root.state = 2
    startTimer.restart()
  }

  // Give the systemd unit a moment to bring the socket up; if that fails,
  // spawn the daemon binary directly so a fresh install still works.
  Timer {
    id: startTimer
    interval: 700
    onTriggered: root.startViaSystemd()
  }

  function startViaSystemd() {
    startProc.command = "systemctl --user start rayarchy"
    startProc.running = true
  }

  Process {
    id: startProc
    onFinished: function (exitCode, exitStatus) {
      if (exitCode !== 0) {
        // Fall back to a direct spawn of the daemon binary on PATH.
        directProc.command = "rayarchy-daemon"
        directProc.running = true
        return
      }
      waitConnect.restart()
    }
  }

  Process {
    id: directProc
    onFinished: function () {
      waitConnect.restart()
    }
  }

  Timer {
    id: waitConnect
    interval: 600
    repeat: true
    onTriggered: {
      if (socket.connected) {
        root.starting = false
        root.state = 1
        root.statusChanged()
        waitConnect.stop()
      } else {
        socket.connected = true
        if (retryCount.value >= 4) {
          waitConnect.stop()
          root.starting = false
          root.startError = Strings.tr("daemonUnreachable")
          root.state = 0
          root.statusChanged()
          rejectAll(Strings.tr("daemonUnreachable"))
        } else {
          retryCount.value += 1
        }
      }
    }
  }

  QtObject {
    id: retryCount
    property int value: 0
  }

  Socket {
    id: socket
    connected: false
    parser: SplitParser {
      onRead: function (message) {
        root.handleMessage(message)
      }
    }
    function onSocketConnected() { root.onConnectedChanged() }
    function onSocketDisconnected() { root.onConnectedChanged() }
    function onSocketError(error) { root.onSocketError(error) }
  }

  property int nextId: 1
  property var pending: ({})
  // Listeners registered by views for "push-style" notifications. The daemon
  // has no push channel, so views poll via call(); this exists for symmetry.
  property var listeners: ({})

  function handleMessage(message) {
    var line = String(message).trim()
    if (line === "") return
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg === null || typeof msg !== "object") return
    if (msg.id !== undefined && msg.id !== null) {
      var key = String(msg.id)
      var entry = root.pending[key]
      if (entry) {
        delete root.pending[key]
        if (msg.error) entry.reject(msg.error.message !== undefined ? msg.error.message : String(msg.error))
        else entry.resolve(msg.result)
      }
      return
    }
    if (msg.method) root.response(msg.method, msg.params || {})
  }

  function call(method, params, onResult, onError) {
    var id = root.nextId++
    var entry = {
      method: method,
      params: params || {},
      resolve: function (result) {
        if (onResult) onResult(result)
        root.response(method, result)
      },
      reject: function (error) {
        if (onError) onError(error)
        else root.response(method, { error: error })
      }
    }
    root.pending[String(id)] = entry
    var request = JSON.stringify({ jsonrpc: "2.0", id: id, method: method, params: params || {} })
    if (socket.connected) {
      socket.write(request)
      socket.flush()
    } else {
      if (!root.starting) root.ensureDaemon()
    }
    return id
  }

  function flushQueue() {
    // Any writes that raced the connect are replayed here (rare; the daemon
    // buffers nothing, so we simply keep the pending map and re-send).
    var keys = Object.keys(root.pending)
    for (var i = 0; i < keys.length; i++) {
      var entry = root.pending[keys[i]]
      var request = JSON.stringify({ jsonrpc: "2.0", id: Number(keys[i]), method: entry.method, params: entry.params })
      socket.write(request)
    }
    socket.flush()
  }

  function rejectAll(message) {
    var keys = Object.keys(root.pending)
    for (var i = 0; i < keys.length; i++) {
      var entry = root.pending[keys[i]]
      delete root.pending[keys[i]]
      entry.reject(message)
    }
  }

  function callAndForget(method, params) {
    root.call(method, params, function () {}, function () {})
  }
}