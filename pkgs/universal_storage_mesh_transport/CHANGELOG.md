## 0.2.0-dev.1

- **WebSocketLanTransport (LanMeshTransport) — lifted from vosges'
  proven gesture mesh**: a direct same-LAN WebSocket control channel —
  nonce-bound hello/ack handshake, optional signed payload frames
  (closure crypto seams: `frameSealer`/`frameVerifier`/
  `identityPublisher`, so implementers adapt their own identity
  material in one lambda), strict inbound sequence monotonicity, and
  connection-fatal authentication (an unproven peer never remains a
  session source). Wire kinds/channel are parameters (`helloKind`,
  `channelId`) so an existing deployment's vocabulary interops.
  Unsigned mode is retained for deterministic tests only.

## 0.1.0-dev.1

- Initial development release.
