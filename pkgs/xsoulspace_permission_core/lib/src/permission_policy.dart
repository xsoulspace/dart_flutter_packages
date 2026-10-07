import 'permission_decision.dart';
import 'permission_request.dart';

/// One decider in a permission chain: total, pure, synchronous.
///
/// A policy ANSWERS a request from the authority it actually holds —
/// [PermissionAllow]/[PermissionDeny] when it can decide,
/// [PermissionEscalate] when it cannot. It never throws for a
/// well-formed request, never performs I/O, and never consults a
/// human: human-in-the-loop is what escalate routes TO.
abstract interface class PermissionPolicy {
  PermissionDecision decide(final PermissionRequest request);
}
