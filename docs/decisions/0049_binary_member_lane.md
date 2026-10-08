# ADR 0049: Binary members — the manifest/lane split

**Status:** Accepted (2026-10-08)
**Amends:** 0042 (content-addressed chunk store — this is its mesh
integration), consumes 0047 (world members) and 0048 (the exchange).

## Context

ADR 0042 shipped the pieces — a gear-hash content-defined chunker, a
sha256 CAS store with the proof-of-possession law, manifests as
kernel-doc values, and `MeshChunkExchange` fetch/serve over a session —
but nothing told an app HOW to make a binary a MEMBER: which docId holds
the manifest, who serves requests on a shared server, and (the gap that
actually blocked adoption) how a dialer-only topology (a phone that can
push but never be dialed) ships its bytes.

## Decision

**The manifest is the member; the bytes are the lane.**

- `MeshBlobLane` (universal_storage_mesh) binds a `StorageService` (where
  manifests live as ordinary members — sync ships them like anything
  else) to a `ChunkedBlobStore` (where bytes live, content-addressed).
  `publish(docId, bytes)` → chunks + manifest member + a census entry
  ([ZoneCatalog] meta carries root/size/chunk-count so a peer can warm
  from the catalog alone); `fetchFrom` dials and requests the gap set;
  `unpublish` tombstones (chunks stay — the store is immutable and
  shared; collection stays a separate policy).
- **Dialer symmetry** is the new protocol half: `MeshChunkExchange.push`
  sends unsolicited verified chunks; `serve` now ABSORBS unsolicited
  `chunk` frames on the same session (hash-checked — the PoP law holds
  for pushes). A phone dials one session and pushes its capture; no
  second server ever exists.
- **Plane routing**: `looksLikeChunkFrame` classifies a session's first
  frame (`chunk-req` or `chunk`), so the blob plane is CLAIMED off the
  same server the sync plane rides — sync → blobs → realtime passthrough,
  chained `ClaimingMeshTransport`s. `looksLikeWorldSyncFrame` moved into
  the family (mesh_sync_protocol) — plane classifiers live with their
  protocols.

## Property obligations

- A chunk is adopted (fetched OR pushed) only when the bytes hash to its
  address; manifests are trusted only through the sync's own
  convergence.
- `getBytes` re-verifies the root; `MissingChunksException` names the
  gap set (retryable against another peer/pulse).
- Blob members never enter app-state folds; the census enumerates them.

## Non-claims

- No compression, no encryption beyond the transport's, no progressive
  streaming UI, no chunk GC — ADR 0042 v1's posture stands.
- The lane does not schedule; hosts attach it to their own loops.
