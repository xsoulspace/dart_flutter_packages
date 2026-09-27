# universal_webrtc_raw

Raw client for the `xs-webrtc-sidecar/1` wire protocol — a webrtc-rs
engine wrapped behind JSON-lines stdio. **Pure Dart, no Flutter; the
engine is Rust** (per the mix-Rust-when-it-pays policy, ADR 0037).

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)).

## Layout

- `rust/webrtc_sidecar/` — the engine. `cargo build --release` produces
  `xs-webrtc-sidecar`. Handshake first (`{"sidecar":"xs-webrtc-sidecar/1"}`),
  then correlated requests (`create_peer`, `create_offer`,
  `accept_offer`, `accept_answer`, `add_remote_ice`, `send_frame`,
  `close_peer`, `shutdown`) plus async events (`open`, `ice`,
  `iceState`, `peerState`, `frame`).
- `lib/` — `SidecarTransport` (process vs in-memory fakes) and
  `SidecarClient` (correlation, events, close semantics).

## Frame-flow contract (proven by the loopback test)

**The offerer receives frames; the answerer sends them.** Concretely:
the viewer creates the peer with `createChannel` defaulting to true and
offers; the frame source accepts the offer (`createChannel: false`) and
pumps `send_frame`s. Frames are chunked into 12-byte-header envelopes
(see `universal_webrtc`'s `FrameChunkCodec`); the sidecar reassembles on
receipt.

Known issue: the reverse direction (created channel → received channel)
does not deliver under webrtc-rs 0.14; the contract above avoids it.
Revisit on engine upgrades.

## Non-claims

- Verified on macOS arm64 with cargo 1.98 / webrtc-rs 0.14;
  Windows/Linux builds are expected to work but untested.
- No media tracks yet (data channel only); no TURN/STUN configuration
  surface yet (host candidates only).
