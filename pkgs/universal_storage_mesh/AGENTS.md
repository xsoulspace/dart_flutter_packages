# universal_storage_mesh — Working Agreement

## Scope (ADR 0010)

- Serverless P2P replica provider. Every device has equal standing; relay or
  bridge roles, if ever added, are nodes — never origins with conflict-
  resolution authority. Convergence belongs to
  `universal_storage_convergence` exclusively.
- Local reads/writes never block on connectivity; `sync()` is opportunistic
  and skips unreachable peers silently (`MeshConnectionException`).
- Each file is one LWW doc (`content` register) via the kernel. Opaque
  binary merging beyond object-level LWW is out of scope (ADR 0010 §5).
- Session encryption/key material arrives with real transports; the QR
  pairing registry stores peer identity records only for now.

## Known gaps (v1)

- Pairing records are unencrypted JSON; no Ed25519/X25519 handshake yet.
- LAN transport package not started; only `FakeMeshTransport` exists.

## Validation

```bash
just check universal_storage_mesh
```
