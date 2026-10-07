/// The world model for zone journeys (ADR 0047).
///
/// App- and game-agnostic layer over the convergence kernel: stable member
/// addressing ([WorldUrn]), interest policies and their wire-stable
/// [InterestSelection], zone catalogs ([ZoneCatalog]), the member-codec
/// seam ([MemberCodec]), journey phases ([JourneyPhase]), and the
/// host-driven scheduling contract ([Pulseable]).
///
/// Layer law (ADR 0047 §1): this package — and everything below it — knows
/// nothing about Flutter, ecsly, the harness, or transports. Domains above
/// (apps, games, the harness) bring their own codecs and interest policies;
/// the sync/session layer stays generic over member kinds.
///
/// Concurrent worlds naming note: "member" means anything addressable in a
/// world — a chat document, a code surface, a binary asset manifest, a game
/// entity. Nothing here learns what any of those ARE.
library;

export 'src/interest_policy.dart';
export 'src/journey.dart';
export 'src/member_codec.dart';
export 'src/member_ref.dart';
export 'src/pulseable.dart';
export 'src/urn_resolver.dart';
export 'src/world_urn.dart';
export 'src/zone_catalog.dart';
