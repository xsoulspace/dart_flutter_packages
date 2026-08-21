/// Agency lifecycle management for the agent harness.
///
/// Defines the rules for when Agency is granted, consumed, and retried.
///
/// ## Lifecycle
///
/// 1. **OpenDecision** exists on an Actor entity
/// 2. **AgencyGrant** schedule grants `Agency` component
/// 3. **Project** schedule builds a `Situation` for the actor
/// 4. **ActorAct** schedule sends LLM request, adds `AwaitingResponse`
/// 5. **ProcessResponses** schedule processes response, consumes
///    `Agency` + `AwaitingResponse`
/// 6. On failure: creates new `OpenDecision` with error note for retry
library;

import 'package:ecsly/ecsly.dart';

import 'data_models/data_models.dart';

/// Rules for agency lifecycle management.
///
/// This class encapsulates the policy for when to grant, consume, and
/// retry agency. It's a stateless utility — all state lives in the
/// ECS world as components.
// ignore: avoid_classes_with_only_static_members
class AgencyLifecycle {
  /// Maximum retry attempts for a failed LLM call.
  static const int maxRetries = 3;

  /// Check if an actor can be granted agency.
  ///
  /// Returns true when the actor has an [OpenDecision] but no [Agency]
  /// and no [AwaitingResponse].
  static bool canGrantAgency(WorldEntity entity) =>
      entity.has<Actor>() &&
      entity.has<OpenDecision>() &&
      !entity.has<Agency>() &&
      !entity.has<AwaitingResponse>();

  /// Check if an actor is awaiting a response.
  ///
  /// Returns true when the actor has [AwaitingResponse] but no [Agency].
  static bool isAwaitingResponse(WorldEntity entity) =>
      entity.has<Actor>() &&
      entity.has<AwaitingResponse>() &&
      !entity.has<Agency>();

  /// Create a retry decision for a failed LLM call.
  ///
  /// Adds an [OpenDecision] with an error note to the actor entity.
  static void createRetryDecision(WorldEntity entity, String errorNote) {
    entity.insert(
      OpenDecision(prompt: 'Error: $errorNote. Retry with tighter context.'),
    );
  }
}
