# universal_storage_world

The app- and game-agnostic world model over the
[convergence kernel](https://pub.dev/packages/universal_storage_convergence)
(dfp ADR 0047): stable member addressing (`WorldUrn`), interest policies and
their wire-stable `InterestSelection`, zone catalogs, the `MemberCodec` seam
between one member kind and kernel doc state, journey phases, and the
host-driven scheduling contract (`Pulseable`).

Layer law: this package — and everything below it — knows nothing about
Flutter, ecsly, the harness, or transports. A "member" is anything addressable
in a world — a chat document, a code surface, a binary asset manifest, a game
entity. Nothing here learns what any of those ARE.

## Usage

Hosts inject the domain: a `MemberCodec` writes one op (or more) per member
value change, an `InterestPolicy` resolves the member set once per sync pulse,
and the host drives `pulse()` on its own scheduler — the layer never owns a
loop.
