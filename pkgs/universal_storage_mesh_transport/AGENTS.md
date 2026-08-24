# universal_storage_mesh_transport — Working Agreement

## North Star

The transport seam serves the mesh North Star:
[pkgs/universal_storage_mesh/docs/north_star.mdx](../universal_storage_mesh/docs/north_star.mdx).
This package owns exactly one slice of it: the radio/document boundary.

## Scope (ADR 0010 §1)

- Transports carry framed convergence envelopes only. No document, storage,
  or crypto knowledge here.
- Real transports live in separate packages (LAN first; BLE-class as
  platform-channel plugins). Rust bindings: rejected — see ADR 0010 context.
- `FakeMeshTransport` is the conformance anchor: provider semantics must be
  proven against it headless before any radio implementation starts.

## Invariants

- `connect(peer)` must fail with `MeshConnectionException` when the
  transport cannot reach `peer.peerId` — never silently connect somewhere
  else. Providers rely on this to route across multiple transports.
- Inbound streams buffer events delivered before a listener attaches
  (single-subscription controllers in the fake); dropping early frames is a
  bug.
- Connection failures raise `MeshConnectionException`; callers treat them
  as "try again later", never as local-operation errors.

## Validation

```bash
just check universal_storage_mesh_transport
# or, headless:
cd pkgs/universal_storage_mesh_transport && dart test
```
