//! `xs-webrtc-sidecar/1` — WebRTC engine sidecar.
//!
//! Contract (ADR 0037): JSON-lines over stdio. The first outbound line is
//! the handshake `{"sidecar":"xs-webrtc-sidecar/1"}`. Requests carry an
//! integer `id`; responses echo it. Asynchronous messages carry `"event"`
//! (`open`, `ice`, `closed`).
//!
//! v1 transport is the WebRTC **data channel** (ICE/DTLS/SRTP-secured
//! SCTP) with a chunked frame envelope; media tracks are the v2 roadmap.
//! Frames arrive base64-encoded via `send_frame` and leave the sidecar
//! as one or more binary data-channel messages with a 12-byte header:
//! `[u16 magic = 0x5853 ('XS'), u8 type = 1, u8 flags, u32 seq,
//! u32 revision]`, where flags bit0 = first chunk, bit1 = last chunk.

use anyhow::Result;
use serde::Deserialize;
use bytes::Bytes;
use base64::Engine;
use serde_json::{json, Value};
use std::pin::Pin;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::Mutex;
use webrtc::api::APIBuilder;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::data_channel::RTCDataChannel;

#[derive(Deserialize, Clone, Debug)]
struct IceServerSpec {
    /// STUN/TURN URL(s): stun:host:port, turn:host:port?transport=udp/tcp
    urls: ValueOrList,
    #[serde(default)]
    username: Option<String>,
    #[serde(default)]
    credential: Option<String>,
}

/// Accepts either a single URL string or a list of URLs.
#[derive(Deserialize, Clone, Debug)]
#[serde(untagged)]
enum ValueOrList {
    One(String),
    Many(Vec<String>),
}

impl ValueOrList {
    fn to_vec(&self) -> Vec<String> {
        match self {
            ValueOrList::One(url) => vec![url.clone()],
            ValueOrList::Many(urls) => urls.clone(),
        }
    }
}

const MAGIC: u16 = 0x5853;
const FRAME_TYPE: u8 = 1;
const FLAG_FIRST: u8 = 1;
const FLAG_LAST: u8 = 2;
const CHUNK_PAYLOAD: usize = 16 * 1024;

type Connections = Arc<Mutex<HashMap<String, Arc<RTCPeerConnection>>>>;
type StdoutGuard = Arc<Mutex<()>>;
type Channels = Arc<Mutex<HashMap<String, Arc<RTCDataChannel>>>>;
type PartialFrames = Arc<Mutex<HashMap<String, Vec<u8>>>>;

/// All stdout writes (handshake, responses, events) serialize through
/// this lock: interleaved async writes would corrupt the JSON-lines
/// protocol.
static STDOUT_LOCK: std::sync::OnceLock<StdoutGuard> =
    std::sync::OnceLock::new();

async fn write_line(line: &str) -> Result<()> {
    let guard = STDOUT_LOCK.get_or_init(|| Arc::new(Mutex::new(())));
    let _guard = guard.lock().await;
    let mut stdout = tokio::io::stdout();
    stdout.write_all(line.as_bytes()).await?;
    stdout.write_all(b"\n").await?;
    stdout.flush().await?;
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let connections: Connections = Arc::new(Mutex::new(HashMap::new()));
    let channels: Channels = Arc::new(Mutex::new(HashMap::new()));
    let partial_frames: PartialFrames =
        Arc::new(Mutex::new(HashMap::new()));

    let handshake = json!({"sidecar": "xs-webrtc-sidecar/1"});
    write_line(&handshake.to_string()).await?;

    let stdin = tokio::io::stdin();
    let mut lines = BufReader::new(stdin).lines();

    while let Some(line) = lines.next_line().await? {
        if line.trim().is_empty() {
            continue;
        }
        let Ok(message) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let Some(id) = message.get("id").and_then(Value::as_i64) else {
            continue;
        };
        let op = message.get("op").and_then(Value::as_str).unwrap_or("");
        let result =
            handle_op(op, &message, &connections, &channels, &partial_frames)
                .await;
        let response = match result {
            Ok(value) => json!({"id": id, "result": value}),
            Err(error) => json!({"id": id, "error": error.to_string()}),
        };
        write_line(&response.to_string()).await?;
        if op == "shutdown" {
            break;
        }
    }
    Ok(())
}

/// Builds the data-channel message handler shared by both directions:
/// validates the `XS` magic, reassembles chunked frames per peer, and
/// emits one `frame` event per complete frame. Chunking is
/// direction-agnostic — the offerer's created channel and the
/// answerer's received channel MUST behave identically.
fn on_frame_message(
    peer_id: String,
    partials: PartialFrames,
) -> Box<
    dyn FnMut(webrtc::data_channel::data_channel_message::DataChannelMessage)
        -> Pin<Box<dyn std::future::Future<Output = ()> + Send>>
        + Send
        + Sync,
> {
    Box::new(move |message| {
        let peer_id = peer_id.clone();
        let partials = Arc::clone(&partials);
        Box::pin(async move {
            let bytes = &message.data[..];
            if bytes.len() < 12
                || u16::from_be_bytes([bytes[0], bytes[1]]) != MAGIC
            {
                return;
            }
            let flags = bytes[2];
            let seq = u32::from_be_bytes([
                bytes[4], bytes[5], bytes[6], bytes[7],
            ]);
            let revision = u32::from_be_bytes([
                bytes[8], bytes[9], bytes[10], bytes[11],
            ]);
            let payload = &bytes[12..];
            let complete = {
                let mut partials = partials.lock().await;
                if flags & FLAG_FIRST != 0 {
                    partials.insert(peer_id.clone(), payload.to_vec());
                } else if let Some(buffer) = partials.get_mut(&peer_id) {
                    buffer.extend_from_slice(payload);
                }
                if flags & FLAG_LAST != 0 {
                    partials.remove(&peer_id)
                } else {
                    None
                }
            };
            if let Some(buffer) = complete {
                let _ = emit(
                    event("frame", &peer_id, json!({
                        "seq": seq,
                        "revision": revision,
                        "bytes": base64::engine::general_purpose::
                            STANDARD.encode(buffer),
                    })),
                )
                .await;
            }
        })
    })
}

fn event(kind: &str, peer_id: &str, extra: Value) -> Value {
    let mut payload = json!({"event": kind, "peerId": peer_id});
    if let (Value::Object(event), Value::Object(extra)) =
        (&mut payload, extra)
    {
        for (key, value) in extra {
            event.insert(key, value);
        }
    }
    payload
}

async fn emit(value: Value) -> Result<()> {
    write_line(&value.to_string()).await
}

async fn handle_op(
    op: &str,
    message: &Value,
    connections: &Connections,
    channels: &Channels,
    partial_frames: &PartialFrames,
) -> Result<Value> {
    match op {
        "ping" => Ok(json!({"pong": true})),
        "create_peer" => {
            create_peer(message, connections, channels, partial_frames).await
        }
        "create_offer" => create_offer(message, connections).await,
        "accept_answer" => accept_answer(message, connections).await,
        "accept_offer" => accept_offer(message, connections).await,
        "add_remote_ice" => add_remote_ice(message, connections).await,
        "send_frame" => send_frame(message, channels).await,
        "close_peer" => close_peer(message, connections, channels).await,
        "shutdown" => Ok(json!({"bye": true})),
        other => Err(anyhow::anyhow!("unknown op: {other}")),
    }
}

fn peer_id_of(message: &Value) -> Result<String> {
    Ok(message["peerId"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("peerId required"))?
        .to_string())
}

async fn new_peer_connection(
    ice_servers: Vec<webrtc::ice_transport::ice_server::RTCIceServer>,
    relay_only: bool,
) -> Result<RTCPeerConnection> {
    // Data-channel-only sidecar: the bare API (no media engine, no
    // interceptors) matches the upstream data-channels example and keeps
    // the wire free of unused media m-lines.
    let api = APIBuilder::new().build();
    // `transportPolicy: "relay"` restricts gathering to relayed
    // candidates — the knob the TURN proof uses to FORCE the media
    // through the TURN allocation (with the default `all`, same-host
    // peers would quietly connect via host candidates and prove
    // nothing about the relay path).
    let ice_transport_policy = if relay_only {
        webrtc::peer_connection::policy::ice_transport_policy::
            RTCIceTransportPolicy::Relay
    } else {
        webrtc::peer_connection::policy::ice_transport_policy::
            RTCIceTransportPolicy::All
    };
    let config = RTCConfiguration {
        ice_servers,
        ice_transport_policy,
        ..Default::default()
    };
    Ok(api.new_peer_connection(config).await?)
}

async fn create_peer(
    message: &Value,
    connections: &Connections,
    channels: &Channels,
    partial_frames: &PartialFrames,
) -> Result<Value> {
    let partial_frames = Arc::clone(partial_frames);
    let peer_id = peer_id_of(message)?;
    let create_channel =
        message["createChannel"].as_bool().unwrap_or(true);
    // TURN/STUN: absent iceServers means host candidates only, which
    // reaches same-host and LAN peers. Cross-network pairings need STUN
    // and, behind symmetric NATs, TURN — configure both here.
    let mut ice_servers: Vec<webrtc::ice_transport::ice_server::
        RTCIceServer> = Vec::new();
    if let Some(specs) = message.get("iceServers").and_then(|v| {
        serde_json::from_value::<Vec<IceServerSpec>>(v.clone()).ok()
    }) {
        for spec in specs {
            ice_servers.push(webrtc::ice_transport::ice_server::
                RTCIceServer {
                urls: spec.urls.to_vec(),
                username: spec.username.unwrap_or_default(),
                credential: spec.credential.unwrap_or_default(),
                ..Default::default()
            });
        }
    }
    let relay_only = message["transportPolicy"].as_str() == Some("relay");
    let connection = Arc::new(
        new_peer_connection(ice_servers, relay_only).await?,
    );
    // Only the offerer creates the channel; the answerer receives it via
    // on_data_channel. Both sides creating collides on SCTP stream ids.
    let channel = if create_channel {
        let created = connection.create_data_channel("frames", None).await?;
        {
            let peer_id = peer_id.clone();
            let open_handle = Arc::clone(&created);
            created.on_open(Box::new(move || {
                let peer_id = peer_id.clone();
                let keep_alive = Arc::clone(&open_handle);
                Box::pin(async move {
                    let _ =
                        emit(event("open", &peer_id, json!({}))).await;
                    let _ = keep_alive;
                })
            }));
        }
        // The created (offerer) side uses the same reassembling handler
        // as the received side — chunked frames are direction-agnostic.
        {
            let peer_id = peer_id.clone();
            let partials = Arc::clone(&partial_frames);
            created.on_message(on_frame_message(
                peer_id,
                partials,
            ));
        }
        Some(created)
    } else {
        None
    };
    {
        let peer_id = peer_id.clone();
        connection.on_ice_candidate(Box::new(move |candidate| {
            let peer_id = peer_id.clone();
            Box::pin(async move {
                let Some(candidate) = candidate else { return };
                let json_candidate = candidate
                    .to_json()
                    .map(|c| serde_json::to_value(c).unwrap_or(Value::Null))
                    .unwrap_or(Value::Null);
                let _ = emit(
                    event("ice", &peer_id, json!({
                        "candidate": json_candidate,
                    })),
                )
                .await;
            })
        }));
    }
    {
        let peer_id = peer_id.clone();
        connection.on_ice_connection_state_change(Box::new(move |state| {
            let peer_id = peer_id.clone();
            Box::pin(async move {
                let _ = emit(
                    event("iceState", &peer_id, json!({
                        "state": state.to_string(),
                    })),
                )
                .await;
            })
        }));
    }
    {
        let peer_id = peer_id.clone();
        connection.on_peer_connection_state_change(Box::new(move |state| {
            let peer_id = peer_id.clone();
            Box::pin(async move {
                let _ = emit(
                    event("peerState", &peer_id, json!({
                        "state": state.to_string(),
                    })),
                )
                .await;
            })
        }));
    }

    {
        let peer_id = peer_id.clone();
        let channels = Arc::clone(channels);
        connection.on_data_channel(Box::new(move |channel| {
            let peer_id = peer_id.clone();
            let channels = Arc::clone(&channels);
            let partials_for_outer = Arc::clone(&partial_frames);
            Box::pin(async move {
                let inserted = channels
                    .lock()
                    .await
                    .insert(peer_id.clone(), Arc::clone(&channel))
                    .is_none();
                let _ = emit(
                    event("open", &peer_id, json!({
                        "label": channel.label(),
                        "newChannel": inserted,
                    })),
                )
                .await;
                channel.on_message(on_frame_message(
                    peer_id.clone(),
                    partials_for_outer,
                ));
            })
        }));
    }

    connections
        .lock()
        .await
        .insert(peer_id.clone(), Arc::clone(&connection));
    if let Some(channel) = channel {
        channels.lock().await.insert(peer_id.clone(), channel);
    }
    Ok(json!({"created": peer_id}))
}

async fn create_offer(
    message: &Value,
    connections: &Connections,
) -> Result<Value> {
    let peer_id = peer_id_of(message)?;
    let connection = connections
        .lock()
        .await
        .get(&peer_id)
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("unknown peer: {peer_id}"))?;
    let offer = connection.create_offer(None).await?;
    connection.set_local_description(offer.clone()).await?;
    Ok(json!({
        "type": offer.sdp_type.to_string(),
        "sdp": offer.sdp,
    }))
}

async fn accept_answer(
    message: &Value,
    connections: &Connections,
) -> Result<Value> {
    let peer_id = peer_id_of(message)?;
    let sdp = message["sdp"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("sdp (plain string) required"))?
        .to_string();
    let connection = connections
        .lock()
        .await
        .get(&peer_id)
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("unknown peer: {peer_id}"))?;
    let answer = RTCSessionDescription::answer(sdp)?;
    connection.set_remote_description(answer).await?;
    Ok(json!({"accepted": peer_id}))

}

/// Answerer path: apply the remote offer, produce and apply the local
/// answer, and return it for signaling back to the offerer.
async fn accept_offer(
    message: &Value,
    connections: &Connections,
) -> Result<Value> {
    let peer_id = peer_id_of(message)?;
    let sdp = message["sdp"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("sdp (plain string) required"))?
        .to_string();
    let connection = connections
        .lock()
        .await
        .get(&peer_id)
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("unknown peer: {peer_id}"))?;
    let offer = RTCSessionDescription::offer(sdp)?;
    connection.set_remote_description(offer).await?;
    let answer = connection.create_answer(None).await?;
    connection
        .set_local_description(answer.clone())
        .await?;
    Ok(json!({
        "type": answer.sdp_type.to_string(),
        "sdp": answer.sdp,
    }))
}

async fn add_remote_ice(
    message: &Value,
    connections: &Connections,
) -> Result<Value> {
    let peer_id = peer_id_of(message)?;
    let connection = connections
        .lock()
        .await
        .get(&peer_id)
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("unknown peer: {peer_id}"))?;
    let candidate = &message["candidate"];
    if candidate.is_null() {
        return Ok(json!({"endOfCandidates": true}));
    }
    let init: webrtc::ice_transport::ice_candidate::RTCIceCandidateInit =
        serde_json::from_value(candidate.clone())?;
    connection.add_ice_candidate(init).await?;
    Ok(json!({"added": true}))
}

async fn send_frame(
    message: &Value,
    channels: &Channels,
) -> Result<Value> {
    let peer_id = peer_id_of(message)?;
    let seq = message["seq"].as_u64().unwrap_or(0) as u32;
    let revision = message["revision"].as_u64().unwrap_or(0) as u32;
    let bytes_b64 = message["bytes"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("bytes (base64) required"))?;
    let payload = base64::engine::general_purpose::STANDARD
        .decode(bytes_b64)?;
    let channel = channels
        .lock()
        .await
        .get(&peer_id)
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("unknown peer: {peer_id}"))?;
    let ready_state = channel.ready_state().to_string();
    let total_chunks = payload.len().div_ceil(CHUNK_PAYLOAD).max(1);
    for index in 0..total_chunks {
        let start = index * CHUNK_PAYLOAD;
        let end = (start + CHUNK_PAYLOAD).min(payload.len());
        let mut chunk = Vec::with_capacity(12 + end - start);
        chunk.extend_from_slice(&MAGIC.to_be_bytes());
        chunk.push(FRAME_TYPE);
        let mut flags = 0u8;
        if index == 0 {
            flags |= FLAG_FIRST;
        }
        if index == total_chunks - 1 {
            flags |= FLAG_LAST;
        }
        chunk.push(flags);
        chunk.extend_from_slice(&seq.to_be_bytes());
        chunk.extend_from_slice(&revision.to_be_bytes());
        chunk.extend_from_slice(&payload[start..end]);
        channel.send(&Bytes::from(chunk)).await?;
    }
    Ok(json!({"seq": seq, "chunks": total_chunks, "readyState": ready_state}))
}

async fn close_peer(
    message: &Value,
    connections: &Connections,
    channels: &Channels,
) -> Result<Value> {
    let peer_id = peer_id_of(message)?;
    if let Some(channel) = channels.lock().await.remove(&peer_id) {
        let _ = channel.close().await;
    }
    let connection = connections.lock().await.remove(&peer_id);
    if let Some(connection) = connection {
        connection.close().await?;
    }
    Ok(json!({"closed": peer_id}))
}

