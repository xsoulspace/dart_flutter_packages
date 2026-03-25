/// Base event type emitted by [SteamClient.events].
sealed class SteamEvent {
  const SteamEvent(this.timestamp);

  final DateTime timestamp;
}

/// Lifecycle state transitions.
enum SteamLifecycleState { initialized, shutdown }

/// Lifecycle event.
final class SteamLifecycleEvent extends SteamEvent {
  SteamLifecycleEvent({required this.state}) : super(DateTime.now().toUtc());

  final SteamLifecycleState state;
}

/// Raw callback dispatch event.
final class SteamCallbackEvent extends SteamEvent {
  SteamCallbackEvent({required this.callbackId, required this.payloadSize})
    : super(DateTime.now().toUtc());

  final int callbackId;
  final int payloadSize;
}

/// Async SteamAPICall completion event.
final class SteamAsyncCallResolvedEvent extends SteamEvent {
  SteamAsyncCallResolvedEvent({
    required this.apiCallHandle,
    required this.callbackId,
    required this.failed,
  }) : super(DateTime.now().toUtc());

  final int apiCallHandle;
  final int callbackId;
  final bool failed;
}

/// Async SteamAPICall timeout event.
final class SteamAsyncCallTimeoutEvent extends SteamEvent {
  SteamAsyncCallTimeoutEvent({
    required this.apiCallHandle,
    required this.expectedCallbackId,
    required this.timeout,
  }) : super(DateTime.now().toUtc());

  final int apiCallHandle;
  final int expectedCallbackId;
  final Duration timeout;
}

/// Generic runtime error event.
final class SteamErrorEvent extends SteamEvent {
  SteamErrorEvent({required this.message}) : super(DateTime.now().toUtc());

  final String message;
}
