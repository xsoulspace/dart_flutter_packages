import 'package:meta/meta.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Compatibility outcome for namespace profile capabilities.
enum CapabilityDecision {
  /// Requested mode/capabilities are supported.
  allowed,

  /// Namespace can run with downgraded behavior.
  degraded,

  /// Namespace configuration is invalid for runtime execution.
  blocked,
}

/// Result of evaluating one namespace profile against resolved capabilities.
@immutable
final class NamespaceCapabilityDecision {
  /// Creates decision result.
  const NamespaceCapabilityDecision({
    required this.namespace,
    required this.policy,
    required this.requestedInteractionLevel,
    required this.resolvedInteractionLevel,
    required this.decision,
    this.reason = '',
  });

  /// Namespace that was checked.
  final StorageNamespace namespace;

  /// Namespace policy.
  final StoragePolicy policy;

  /// Requested interaction level from profile.
  final SyncInteractionLevel requestedInteractionLevel;

  /// Resolved interaction level after capability negotiation.
  final SyncInteractionLevel resolvedInteractionLevel;

  /// Final decision.
  final CapabilityDecision decision;

  /// Human-readable reason for degraded/blocked outcomes.
  final String reason;
}

/// Aggregate result for full profile compatibility checks.
@immutable
final class ProfileCapabilityDecision {
  /// Creates aggregate result.
  const ProfileCapabilityDecision({required this.namespaces});

  /// Per-namespace decisions.
  final List<NamespaceCapabilityDecision> namespaces;

  /// Whether all namespaces are strictly allowed.
  bool get allAllowed => namespaces.every(
    (final entry) => entry.decision == CapabilityDecision.allowed,
  );

  /// Whether there is at least one degraded namespace.
  bool get hasDegraded => namespaces.any(
    (final entry) => entry.decision == CapabilityDecision.degraded,
  );

  /// Whether there is at least one blocked namespace.
  bool get hasBlocked => namespaces.any(
    (final entry) => entry.decision == CapabilityDecision.blocked,
  );
}

/// Utility for profile capability checks and safe degradation decisions.
final class StorageProfileCapabilityGuard {
  /// Creates capability guard.
  const StorageProfileCapabilityGuard();

  /// Evaluates one namespace profile against available capabilities.
  NamespaceCapabilityDecision evaluateNamespace({
    required final StorageNamespaceProfile profile,
    required final StorageCapabilities availableCapabilities,
  }) {
    if (profile.requiresRemote &&
        (profile.remoteEngineId == null || profile.remoteEngineId!.isEmpty)) {
      return NamespaceCapabilityDecision(
        namespace: profile.namespace,
        policy: profile.policy,
        requestedInteractionLevel: profile.syncInteractionLevel,
        resolvedInteractionLevel: profile.syncInteractionLevel,
        decision: CapabilityDecision.blocked,
        reason: 'Remote policy requires non-empty remote_engine_id.',
      );
    }

    final requested = profile.syncInteractionLevel;
    final resolved = profile.resolveInteractionLevel(availableCapabilities);

    if (requested == SyncInteractionLevel.complex &&
        resolved == SyncInteractionLevel.minimal) {
      return NamespaceCapabilityDecision(
        namespace: profile.namespace,
        policy: profile.policy,
        requestedInteractionLevel: requested,
        resolvedInteractionLevel: resolved,
        decision: CapabilityDecision.degraded,
        reason:
            'Complex interaction requested but available capabilities are '
            'insufficient. Runtime should degrade to minimal mode.',
      );
    }

    if (!availableCapabilities.satisfies(profile.requiredCapabilities)) {
      return NamespaceCapabilityDecision(
        namespace: profile.namespace,
        policy: profile.policy,
        requestedInteractionLevel: requested,
        resolvedInteractionLevel: resolved,
        decision: CapabilityDecision.blocked,
        reason: 'Required capabilities are not satisfied.',
      );
    }

    return NamespaceCapabilityDecision(
      namespace: profile.namespace,
      policy: profile.policy,
      requestedInteractionLevel: requested,
      resolvedInteractionLevel: resolved,
      decision: CapabilityDecision.allowed,
    );
  }

  /// Evaluates all namespaces in profile against per-namespace capabilities.
  ProfileCapabilityDecision evaluateProfile({
    required final StorageProfile profile,
    final Map<StorageNamespace, StorageCapabilities> capabilitiesByNamespace =
        const <StorageNamespace, StorageCapabilities>{},
  }) {
    final decisions = profile.namespaces
        .map((final namespaceProfile) {
          final available =
              capabilitiesByNamespace[namespaceProfile.namespace] ??
              StorageCapabilities.none;
          return evaluateNamespace(
            profile: namespaceProfile,
            availableCapabilities: available,
          );
        })
        .toList(growable: false);

    return ProfileCapabilityDecision(namespaces: decisions);
  }
}
