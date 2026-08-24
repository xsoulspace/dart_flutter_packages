# Debugging log — two-node TCP example hang (Phase 2)

Status: **unresolved** at time of writing. Sync exchanges complete on both
sides, but `await alice.sync()` never returns. This doc records everything
tried so far so the next agent does not repeat it.

## Reproduction

```sh
cd pkgs/universal_storage_mesh
fvm dart run example/mesh_two_nodes.dart
```

Output stops after "syncing…". Process stays alive indefinitely.

## Evidence gathered (instrumented run)

Temporary prints were added to `_runExchange` / `_recvOfType` in
`mesh_storage_provider.dart` and an inbound-connection print in the example's
TCP transport. Trace from a real run:

```
[bob] inbound connection          <- bob's server accepted alice's connect
[bob] exchange start              <- responder-side handler fired
[alice] exchange start            <- alice's initiator session started
[alice] recv type=hello waiting=hello
[alice] recv type=vv waiting=vv
[bob] recv type=hello waiting=hello
[bob] recv type=vv waiting=vv
[bob] recv type=delta waiting=delta
[bob] delta applied, persisting
[alice] recv type=delta waiting=delta
[alice] delta applied, persisting
[bob] exchange complete           <- _runExchange returned on both sides
[alice] exchange complete
```

Conclusion: `_runExchange` completes. The hang is between that return and
`sync()` resolving — i.e. inside `session.close()` in the `finally` block of
`MeshStorageProvider.sync()`, or in how initiator-close and responder-close
interleave across the two sessions.

Note: output file showed "syncing…" but NOT "alice.sync done" even though
exchange completed, confirming sync() itself never resolves.

## Things tried (do not repeat)

1. **Reordered close(): flush → destroy → frames.close()**
   Original order. Hang persisted.

2. **close(): frames.close() first, then socket.destroy(), no flush**
   Current state in `tcp_mesh_transport.dart`. Hang persisted.

3. **Minimal TCP repro (`example/close_repro.dart`)**
   Server sends bytes, destroys; client iterates stream to completion.
   Result: completes fine, prints "DONE - no hang". So plain TCP
   listen/destroy/close semantics are NOT the problem in isolation.

4. **onListen buffering variants for _frames controller**
   Tried starting socket.listen immediately vs wiring via onListen.
   No difference.

5. **InternetAddress(parts[0]) vs string host in Socket.connect**
   Cosmetic; no effect.

6. **flush() after send()**
   Added `await _socket.flush()` in `send()`; no effect on the hang.

7. **Checked StreamIterator consumption logic in _recvOfType**
   Each side has its own session/stream; no cross-consumption found.
   Both sides received hello, vv, delta in correct order per trace.

## Leading hypotheses (untested)

A. **Initiator/responder close interleaving deadlock.** When alice calls
   sync(), bob's inbound handler runs a concurrent exchange on the accepted
   session. Both sides eventually call close() on their respective sessions.
   Possible that one side's pending StreamIterator (`moveNext`) never wakes
   because its controller was closed while the iterator was suspended in a
   prior moveNext that already consumed the delta — i.e., an extra
   `moveNext()` call after the last frame parks forever if the close event
   was coalesced or missed.

B. **Double-close of the same underlying socket.** Alice's outbound session
   and Bob's accepted session wrap two different sockets, but each side also
   holds a subscription on its own transport's `incoming` stream. If closing
   one session triggers something that closes the other side's frames
   controller, a second `close()` on an already-closed single-subscription
   controller could misbehave (though Dart usually tolerates this).

C. **Process-exit confusion.** Even after sync resolves, bound ServerSockets
   keep the isolate alive. But the hang is before "alice.sync done" prints,
   so this is not the primary issue — worth remembering for cleanup though.

## Suggested next steps

1. Re-add targeted prints: one immediately before and after
   `await session.close()` in `sync()`, and one before/after close in the
   responder handler in `attachTransport`. Run once, read trace.
2. If close() is confirmed as the hang point: make close() fully
   synchronous-fire-and-forget (`_frames.close(); _socket.destroy();` with
   no awaits at all), and make it idempotent (guard with a bool).
3. Inspect whether `_recvOfType`'s final `moveNext()` (the one that returns
   false on close) is ever reached — add a print after the while loop.
4. Alternative protocol-level fix: send an explicit `bye` sentinel message
   instead of relying on stream close to signal end-of-session, so neither
   side waits on close semantics.

## Files involved

- `pkgs/universal_storage_mesh/lib/src/mesh_storage_provider.dart`
  (sync, _runExchange, _recvOfType, attachTransport)
- `pkgs/universal_storage_mesh/example/tcp_mesh_transport.dart`
  (_SocketMeshSession.close, TcpMeshTransport)
- `pkgs/universal_storage_mesh/example/mesh_two_nodes.dart` (main script)
- `pkgs/universal_storage_mesh/example/close_repro.dart` (minimal repro,
  passes — keep as regression evidence)
