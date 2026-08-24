# universal_storage_mesh_transport — Working Agreement

## Scope (ADR 0010 §1)

- Transports carry framed convergence envelopes only. No document, storage,
  or crypto knowledge here.
- Real transports live in separate packages (LAN first; BLE-class as
  platform-channel plugins). Rust bindings: rejected — see ADR 0010 context.
- `FakeMeshTransport` is the conformance anchor: provider semantics must be
  proven against it headless before any radio implementation starts.

## Invariants

- Inbound streams buffer events delivered before a listener attaches
  (single-subscription controllers in the fake); dropping early frames is a
  bug.
- Connection failures raise `MeshConnectionException`; callers treat them
  as "try again later", never as local-operation errors.

## Validation

```bash
just check universal_storage_mesh_transport
```
