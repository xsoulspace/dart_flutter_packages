import 'dart:async';

/// Result payload for completed `SteamAPICall_t` requests.
final class SteamAsyncCallResult {
  const SteamAsyncCallResult({
    required this.apiCallHandle,
    required this.callbackId,
    required this.payload,
    required this.failed,
  });

  final int apiCallHandle;
  final int callbackId;
  final List<int> payload;
  final bool failed;
}

typedef SteamAsyncResolvedCallback = void Function(SteamAsyncCallResult result);
typedef SteamAsyncTimeoutCallback =
    void Function(int apiCallHandle, int expectedCallbackId, Duration timeout);

/// Registry that maps `SteamAPICall_t` handles to completers with timeout.
final class SteamAsyncCallRegistry {
  SteamAsyncCallRegistry({
    this.defaultTimeout = const Duration(seconds: 10),
    this.onResolved,
    this.onTimeout,
  });

  final Duration defaultTimeout;
  final SteamAsyncResolvedCallback? onResolved;
  final SteamAsyncTimeoutCallback? onTimeout;

  final Map<int, _PendingAsyncCall> _pendingCalls = <int, _PendingAsyncCall>{};

  Future<SteamAsyncCallResult> register({
    required final int apiCallHandle,
    required final int expectedCallbackId,
    final Duration? timeout,
  }) {
    if (_pendingCalls.containsKey(apiCallHandle)) {
      throw StateError('SteamAPICall_t $apiCallHandle is already pending.');
    }

    final completer = Completer<SteamAsyncCallResult>();
    final effectiveTimeout = timeout ?? defaultTimeout;

    final timer = Timer(effectiveTimeout, () {
      final pending = _pendingCalls.remove(apiCallHandle);
      if (pending == null || pending.completer.isCompleted) {
        return;
      }
      onTimeout?.call(apiCallHandle, expectedCallbackId, effectiveTimeout);
      pending.completer.completeError(
        TimeoutException('Steam async call timed out.', effectiveTimeout),
      );
    });

    _pendingCalls[apiCallHandle] = _PendingAsyncCall(
      completer: completer,
      expectedCallbackId: expectedCallbackId,
      timer: timer,
      timeout: effectiveTimeout,
    );

    return completer.future;
  }

  bool complete({
    required final int apiCallHandle,
    required final int callbackId,
    required final List<int> payload,
    required final bool failed,
  }) {
    final pending = _pendingCalls[apiCallHandle];
    if (pending == null) {
      return false;
    }
    if (pending.expectedCallbackId != callbackId) {
      return false;
    }

    _pendingCalls.remove(apiCallHandle);
    pending.timer.cancel();

    final result = SteamAsyncCallResult(
      apiCallHandle: apiCallHandle,
      callbackId: callbackId,
      payload: List<int>.unmodifiable(payload),
      failed: failed,
    );

    if (!pending.completer.isCompleted) {
      pending.completer.complete(result);
    }
    onResolved?.call(result);
    return true;
  }

  void dispose() {
    for (final entry in _pendingCalls.entries) {
      entry.value.timer.cancel();
      if (!entry.value.completer.isCompleted) {
        entry.value.completer.completeError(
          StateError('Steam async registry disposed before completion.'),
        );
      }
    }
    _pendingCalls.clear();
  }
}

final class _PendingAsyncCall {
  const _PendingAsyncCall({
    required this.completer,
    required this.expectedCallbackId,
    required this.timer,
    required this.timeout,
  });

  final Completer<SteamAsyncCallResult> completer;
  final int expectedCallbackId;
  final Timer timer;
  final Duration timeout;
}
