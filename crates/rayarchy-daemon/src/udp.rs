use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpStream, UdpSocket};

/// Minimal DNS query for `example.com` (A record) used as the UDP payload.
fn dns_query() -> Vec<u8> {
    let mut q = Vec::with_capacity(32);
    q.extend_from_slice(&[0x12, 0x34]); // id
    q.extend_from_slice(&[0x01, 0x00]); // flags: recursion desired
    q.extend_from_slice(&[0x00, 0x01]); // qdcount
    q.extend_from_slice(&[0x00, 0x00]); // ancount
    q.extend_from_slice(&[0x00, 0x00]); // nscount
    q.extend_from_slice(&[0x00, 0x00]); // arcount
    for label in ["example", "com"] {
        q.push(label.len() as u8);
        q.extend_from_slice(label.as_bytes());
    }
    q.push(0x00); // root
    q.extend_from_slice(&[0x00, 0x01]); // qtype A
    q.extend_from_slice(&[0x00, 0x01]); // qclass IN
    q
}

/// Probe UDP connectivity through a SOCKS5 proxy using the UDP ASSOCIATE
/// handshake, then a DNS query to `target` (default 8.8.8.8:53). Returns the
/// round-trip latency in milliseconds on success.
pub async fn probe(
    socks_host: &str,
    socks_port: u16,
    target_host: &str,
    target_port: u16,
) -> Result<u64, String> {
    let mut stream = TcpStream::connect((socks_host, socks_port))
        .await
        .map_err(|e| format!("could not reach socks proxy: {e}"))?;
    // Greeting: no authentication.
    stream
        .write_all(&[0x05, 0x01, 0x00])
        .await
        .map_err(|e| e.to_string())?;
    let mut greeting = [0u8; 2];
    stream
        .read_exact(&mut greeting)
        .await
        .map_err(|e| e.to_string())?;
    if greeting[0] != 0x05 || greeting[1] != 0x00 {
        return Err("proxy requires authentication; UDP test unsupported".into());
    }
    // UDP ASSOCIATE request (IPv4, zero address = let the relay pick).
    stream
        .write_all(&[0x05, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        .await
        .map_err(|e| e.to_string())?;
    let mut response = [0u8; 10];
    stream
        .read_exact(&mut response)
        .await
        .map_err(|e| e.to_string())?;
    if response[1] != 0x00 {
        return Err("proxy refused the UDP associate request".into());
    }
    if response[3] != 0x01 {
        return Err("proxy returned a non-IPv4 relay address".into());
    }
    let relay_port = u16::from_be_bytes([response[8], response[9]]);
    let relay_addr = format!("{socks_host}:{relay_port}");

    // Resolve the target to an IPv4 address.
    let target_ip = if let Ok(ip) = target_host.parse::<std::net::Ipv4Addr>() {
        ip
    } else {
        let resolved = tokio::net::lookup_host((target_host, target_port))
            .await
            .map_err(|e| format!("could not resolve target: {e}"))?;
        resolved
            .into_iter()
            .map(|addr| addr.ip())
            .find_map(|ip| match ip {
                std::net::IpAddr::V4(v4) => Some(v4),
                std::net::IpAddr::V6(v6) => v6.to_ipv4_mapped(),
            })
            .ok_or("target has no IPv4 address")?
    };

    let udp = UdpSocket::bind("0.0.0.0:0")
        .await
        .map_err(|e| e.to_string())?;
    udp.connect(&relay_addr).await.map_err(|e| e.to_string())?;

    let mut packet = Vec::with_capacity(32);
    packet.push(0x01); // ATYP IPv4
    packet.extend_from_slice(&target_ip.octets());
    packet.extend_from_slice(&target_port.to_be_bytes());
    packet.extend_from_slice(&dns_query());

    let start = Instant::now();
    udp.send(&packet).await.map_err(|e| e.to_string())?;
    let mut buffer = [0u8; 4096];
    let _count = tokio::time::timeout(Duration::from_secs(5), udp.recv(&mut buffer))
        .await
        .map_err(|_| "UDP test timed out".to_string())?
        .map_err(|e| e.to_string())?;
    Ok(start.elapsed().as_millis() as u64)
}

/// Convenience: DNS round trip through the proxy (8.8.8.8:53).
pub async fn probe_dns(socks_host: &str, socks_port: u16) -> Result<u64, String> {
    probe(socks_host, socks_port, "8.8.8.8", 53).await
}
