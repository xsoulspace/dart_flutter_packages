# universal_storage_convergence_session

The anti-entropy session core over the
[convergence kernel](https://pub.dev/packages/universal_storage_convergence)
(dfp ADR 0063): the `MeshSyncProtocol` wire codec (hello / sub / vv / delta
frames), the `DeltaPlanner` decision core (what to send a peer: ops or a
snapshot), the `ReceiveWatermark` causality floor for local writes after
folding remote state, and the generic `SnapshotPolicy` compaction type.

Pure Dart. Knows nothing about transports or storage — messages in, messages
out. Two parents share it: Universal Storage's mesh sync and ecsly's world
sync; merge semantics stay in the kernel, transport seams stay outside.

## Receive watermark, in one paragraph

The kernel folds remote ops without ticking the local clock, so LWW orders a
post-fold local write by raw wall clock — a peer with an ahead wall clock
would outrank it forever. `ReceiveWatermark` keeps the (wall, counter) max of
everything RECEIVED, re-anchored to the local actor, purely logically; local
writers floor their tick time through `floorNow` and pass the watermark as the
kernel's `lastIssued`. Both together make a local write issued after folding a
remote op strictly outrank it, even on a frozen wall clock.
