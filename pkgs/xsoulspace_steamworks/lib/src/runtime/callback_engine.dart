import '../events/steam_event.dart';
import '../native/steam_native_api.dart';
import 'async_call_registry.dart';

/// Callback pump/dispatch engine with async call completion bridge.
final class SteamCallbackEngine {
  SteamCallbackEngine({
    required final SteamNativeApi nativeApi,
    required final SteamAsyncCallRegistry asyncRegistry,
    required final void Function(SteamEvent event) emit,
  }) : _nativeApi = nativeApi,
       _asyncRegistry = asyncRegistry,
       _emit = emit;

  final SteamNativeApi _nativeApi;
  final SteamAsyncCallRegistry _asyncRegistry;
  final void Function(SteamEvent event) _emit;

  bool _manualDispatchInitialized = false;

  void initialize() {
    if (!_nativeApi.supportsManualDispatch) {
      return;
    }
    _nativeApi.initManualDispatch();
    _manualDispatchInitialized = true;
  }

  void pumpOnce() {
    _nativeApi.runCallbacks();

    if (!_manualDispatchInitialized) {
      return;
    }

    final callbacks = _nativeApi.drainManualCallbacks();
    for (final callback in callbacks) {
      _emit(
        SteamCallbackEvent(
          callbackId: callback.callbackId,
          payloadSize: callback.payloadSize,
        ),
      );

      final apiCallHandle = callback.apiCallHandle;
      final expectedCallbackId = callback.apiCallExpectedCallbackId;
      final callbackPayloadSize = callback.apiCallPayloadSize;
      if (apiCallHandle == null ||
          expectedCallbackId == null ||
          callbackPayloadSize == null) {
        continue;
      }

      final apiCallResult = _nativeApi.getApiCallResult(
        apiCallHandle: apiCallHandle,
        expectedCallbackId: expectedCallbackId,
        callbackBufferSize: callbackPayloadSize,
      );

      if (apiCallResult == null) {
        _emit(
          SteamErrorEvent(
            message:
                'Failed to read API call result for handle=$apiCallHandle '
                'expectedCallback=$expectedCallbackId.',
          ),
        );
        continue;
      }

      final completed = _asyncRegistry.complete(
        apiCallHandle: apiCallHandle,
        callbackId: apiCallResult.callbackId,
        payload: apiCallResult.payload,
        failed: apiCallResult.failed,
      );

      if (completed) {
        _emit(
          SteamAsyncCallResolvedEvent(
            apiCallHandle: apiCallHandle,
            callbackId: apiCallResult.callbackId,
            failed: apiCallResult.failed,
          ),
        );
      }
    }
  }

  void dispose() {}
}
