# universal_storage_mesh — Working Agreement

## North Star

Read [docs/north_star.mdx](docs/north_star.mdx) before durable structural
changes. Classify `north_star_impact` per repo AGENTS.md; `amends`/`conflicts`
need an ADR first.

## Debugging logs

- [docs/debug_tcp_hang.md](docs/debug_tcp_hang.md) — **open**: two-node TCP
  example hangs at sync() despite exchanges completing. Evidence, tried
  fixes, and next steps recorded.
- [docs/debug_pairing_keys.md](docs/debug_pairing_keys.md) — resolved: HKDF
  info-string canonicalization bug in PairingService.

## Scope (ADR 0010)

- Serverless P2P replica provider. Every device has equal standing; relay or
  bridge roles, if ever added, are nodes — never origins with conflict-
  resolution authority. Convergence belongs to
  `universal_storage_convergence` exclusively.
- Local reads/writes never block on connectivity; `sync()` is opportunistic
  and skips unreachable peers silently (`MeshConnectionException`).
- Each file is one LWW doc (`content` register) via the kernel. Opaque
  binary merging beyond object-level LWW is out of scope (ADR 0010 §5).
- A replica may hold multiple transports simultaneously (`attachTransport`
  is additive); sync tries each transport per peer.
- Compaction is app-driven via `compactAll()`; lagging peers catch up via
  snapshots afterwards.

## Known gaps (v1)

- Pairing records are unencrypted JSON; no Ed25519/X25519 handshake yet.
  The QR pairing layer is the next milestone.
- LAN transport package not started; only `FakeMeshTransport` exists.

## Validation

```bash
just check universal_storage_mesh
# or, headless:
cd pkgs/universal_storage_mesh && dart test
```

Conformance suite (`universal_storage_conformance`) + two-replica scenarios +
integration suite (multi-hop, snapshot adoption) must all stay green.
