// Formatting and protocol helpers shared across the Rayarchy UI.
.pragma library

function protocolLabel(protocol) {
  var map = {
    vless: "VLESS",
    vmess: "VMess",
    trojan: "Trojan",
    shadowsocks: "SS",
    socks: "SOCKS",
    http: "HTTP",
    hysteria2: "Hysteria2",
    tuic: "TUIC",
    wireguard: "WireGuard",
    anytls: "Anytls",
    naive: "Naive",
    custom: "Custom",
    "policy-group": "Policy Group",
    "proxy-chain": "Proxy Chain",
  }
  return map[protocol] !== undefined ? map[protocol] : protocol
}

function protocolColor(protocol) {
  var colors = {
    vless: "#8be9fd",
    vmess: "#bd93f9",
    trojan: "#ff79c6",
    shadowsocks: "#f1fa8c",
    socks: "#50fa7b",
    http: "#6272a4",
    hysteria2: "#ffb86c",
    tuic: "#ff5555",
    wireguard: "#f8f8f2",
    anytls: "#ff79c6",
    naive: "#66d9ef",
    custom: "#a6e22e",
    "policy-group": "#e6db74",
    "proxy-chain": "#f92672",
  }
  return colors[protocol] !== undefined ? colors[protocol] : "#cacccc"
}

function securityLabel(fields) {
  var security = fields && (fields.security || fields.tls)
  if (!security) return ""
  if (security === "none") return ""
  if (security === "reality") return "reality"
  return "tls"
}

function networkLabel(fields) {
  if (!fields) return "raw"
  var network = fields.type || fields.network || "raw"
  if (network === "tcp" || network === "raw") return "raw"
  return network
}

function delayColor(delay) {
  if (delay === undefined || delay === null) return "#707880"
  if (delay <= 0) return "#ff5555"
  if (delay <= 500) return "#50fa7b"
  return "#f1fa8c"
}

function delayText(delay) {
  if (delay === undefined || delay === null) return ""
  if (delay <= 0) return "fail"
  return delay + " ms"
}

function speedText(mbps) {
  if (mbps === undefined || mbps === null) return ""
  return mbps.toFixed(2) + " Mbps"
}

function field(profile, key) {
  return profile && profile.fields ? profile.fields[key] : undefined
}

function str(value, fallback) {
  if (value === undefined || value === null) return fallback !== undefined ? fallback : ""
  return String(value)
}

function int(value, fallback) {
  var n = parseInt(value, 10)
  return isNaN(n) ? (fallback !== undefined ? fallback : 0) : n
}

function displayAddress(profile) {
  var addr = str(profile.server)
  // Obfuscate like v2rayN's GetSummary: keep first + last characters.
  if (addr.length > 4) return addr[0] + "***" + addr[addr.length - 1]
  return addr
}

function lastTest(profile, kind) {
  if (!profile || !profile.lastTest) return null
  if (kind && profile.lastTest.kind !== kind) return null
  return profile.lastTest
}

function timeAgo(timestamp) {
  if (!timestamp) return ""
  var seconds = Math.floor(Date.now() / 1000) - timestamp
  if (seconds < 60) return seconds + "s"
  if (seconds < 3600) return Math.floor(seconds / 60) + "m"
  if (seconds < 86400) return Math.floor(seconds / 3600) + "h"
  return Math.floor(seconds / 86400) + "d"
}

function formatBytes(bytes) {
  if (bytes === undefined || bytes === null) return ""
  var value = Number(bytes)
  if (value < 1024) return value.toFixed(0) + " B"
  if (value < 1048576) return (value / 1024).toFixed(1) + " KB"
  if (value < 1073741824) return (value / 1048576).toFixed(1) + " MB"
  return (value / 1073741824).toFixed(2) + " GB"
}

function clone(obj) {
  if (!obj) return {}
  try { return JSON.parse(JSON.stringify(obj)) } catch (e) { return {} }
}

function stripObject(obj) {
  // Remove undefined/null so serialization stays clean for the RPC layer.
  var out = {}
  if (!obj) return out
  for (var key in obj) {
    var value = obj[key]
    if (value === undefined || value === null) continue
    if (typeof value === "object" && !Array.isArray(value) && value !== null) {
      value = stripObject(value)
    }
    out[key] = value
  }
  return out
}