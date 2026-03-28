import 'dart:ffi';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:xsoulspace_steamworks_raw/xsoulspace_steamworks_raw.dart';

import '../client/steam_exception.dart';
import '../client/steam_init.dart';
import '../runtime/steam_memory.dart';
import 'steam_native_api.dart';

/// Native factory backed by `xsoulspace_steamworks_raw` loader + bindings.
final class SteamRawNativeApiFactory implements SteamNativeApiFactory {
  const SteamRawNativeApiFactory();

  @override
  SteamNativeApi create(final SteamInitConfig config) {
    final loader = SteamRawLibraryLoader(
      librarySearchPaths: config.librarySearchPaths,
    );
    final library = loader.load();
    final bindings = SteamRawBindings(library);
    return SteamRawNativeApi(
      bindings: bindings,
      enableVerboseLogs: config.enableVerboseLogs,
    );
  }
}

/// Production adapter that performs pointer marshalling and native calls.
final class SteamRawNativeApi implements SteamNativeApi {
  SteamRawNativeApi({
    required final SteamRawBindings bindings,
    required final bool enableVerboseLogs,
  }) : _bindings = bindings,
       _enableVerboseLogs = enableVerboseLogs;

  final SteamRawBindings _bindings;
  final bool _enableVerboseLogs;

  Pointer<Void>? _steamUser;
  Pointer<Void>? _steamFriends;
  Pointer<Void>? _steamUserStats;

  Pointer<Void> _requireSteamUser() {
    final cached = _steamUser;
    if (cached != null && cached != nullptr) {
      return cached;
    }
    final resolved = _bindings.steamUser();
    if (resolved == nullptr) {
      throw const SteamException(
        code: SteamExceptionCode.nativeUnavailable,
        message: 'SteamUser interface pointer is null.',
      );
    }
    _steamUser = resolved;
    return resolved;
  }

  Pointer<Void> _requireSteamFriends() {
    final cached = _steamFriends;
    if (cached != null && cached != nullptr) {
      return cached;
    }
    final resolved = _bindings.steamFriends();
    if (resolved == nullptr) {
      throw const SteamException(
        code: SteamExceptionCode.nativeUnavailable,
        message: 'SteamFriends interface pointer is null.',
      );
    }
    _steamFriends = resolved;
    return resolved;
  }

  Pointer<Void> _requireSteamUserStats() {
    final cached = _steamUserStats;
    if (cached != null && cached != nullptr) {
      return cached;
    }
    final resolved = _bindings.steamUserStats();
    if (resolved == nullptr) {
      throw const SteamException(
        code: SteamExceptionCode.nativeUnavailable,
        message: 'SteamUserStats interface pointer is null.',
      );
    }
    _steamUserStats = resolved;
    return resolved;
  }

  void _log(final String message) {
    if (!_enableVerboseLogs) {
      return;
    }
    // ignore: avoid_print
    print('[steamworks] $message');
  }

  @override
  bool restartAppIfNecessary(final int appId) =>
      _bindings.restartAppIfNecessary(appId);

  @override
  SteamNativeInitResult initialize() {
    final arena = SteamPointerArena();
    try {
      final errorBuffer = arena.alloc<Uint8>(
        count: SteamRawBindings.steamErrMsgMax,
      );
      final initCode = _bindings.initializeFlat(errorBuffer);
      final errorMessage = arena.readNullTerminated(
        errorBuffer,
        maxBytes: SteamRawBindings.steamErrMsgMax,
      );
      _log('initializeFlat result=$initCode message="$errorMessage"');
      return SteamNativeInitResult(
        initCode: initCode,
        errorMessage: errorMessage,
      );
    } finally {
      arena.releaseAll();
    }
  }

  @override
  void shutdown() {
    _bindings.shutdown();
    _steamUser = null;
    _steamFriends = null;
    _steamUserStats = null;
  }

  @override
  void runCallbacks() {
    _bindings.runCallbacks();
  }

  @override
  bool get supportsManualDispatch => _bindings.hasManualDispatch();

  @override
  void initManualDispatch() {
    _bindings.manualDispatchInit();
  }

  @override
  int get hSteamPipe => _bindings.getHSteamPipe();

  @override
  List<SteamManualCallback> drainManualCallbacks() {
    if (!supportsManualDispatch) {
      return const <SteamManualCallback>[];
    }

    final callbacks = <SteamManualCallback>[];
    final callbackPtr = calloc<SteamCallbackMessageNative>();
    try {
      _bindings.manualDispatchRunFrame(hSteamPipe);

      for (var i = 0; i < 256; i++) {
        final hasNext = _bindings.manualDispatchGetNextCallback(
          hSteamPipe,
          callbackPtr,
        );
        if (!hasNext) {
          break;
        }

        try {
          final callback = callbackPtr.ref;

          int? apiCallHandle;
          int? apiCallExpectedCallbackId;
          int? apiCallPayloadSize;

          if (callback.callbackId ==
                  SteamRawBindings.steamApiCallCompletedCallbackId &&
              callback.pubParam != nullptr &&
              callback.cubParam >= sizeOf<SteamApiCallCompletedNative>()) {
            final completed = callback.pubParam
                .cast<SteamApiCallCompletedNative>()
                .ref;
            apiCallHandle = completed.apiCall;
            apiCallExpectedCallbackId = completed.callbackId;
            apiCallPayloadSize = completed.cubParam;
          }

          callbacks.add(
            SteamManualCallback(
              callbackId: callback.callbackId,
              payloadSize: callback.cubParam,
              apiCallHandle: apiCallHandle,
              apiCallExpectedCallbackId: apiCallExpectedCallbackId,
              apiCallPayloadSize: apiCallPayloadSize,
            ),
          );
        } finally {
          _bindings.manualDispatchFreeLastCallback(hSteamPipe);
        }
      }
    } finally {
      calloc.free(callbackPtr);
    }

    return callbacks;
  }

  @override
  SteamApiCallResultPayload? getApiCallResult({
    required final int apiCallHandle,
    required final int expectedCallbackId,
    required final int callbackBufferSize,
  }) {
    final arena = SteamPointerArena();
    try {
      final size = max(1, callbackBufferSize);
      final payload = arena.alloc<Uint8>(count: size);
      final failed = arena.alloc<Uint8>();

      final ok = _bindings.manualDispatchGetApiCallResult(
        hSteamPipe: hSteamPipe,
        apiCallHandle: apiCallHandle,
        callbackBuffer: payload.cast<Void>(),
        callbackBufferSize: callbackBufferSize,
        expectedCallbackId: expectedCallbackId,
        outFailed: failed,
      );

      if (!ok) {
        return null;
      }

      final payloadBytes = callbackBufferSize <= 0
          ? const <int>[]
          : List<int>.from(payload.asTypedList(callbackBufferSize));
      return SteamApiCallResultPayload(
        callbackId: expectedCallbackId,
        failed: failed.value != 0,
        payload: payloadBytes,
      );
    } finally {
      arena.releaseAll();
    }
  }

  @override
  bool userLoggedOn() => _bindings.userIsLoggedOn(_requireSteamUser());

  @override
  int userSteamId() => _bindings.userSteamId(_requireSteamUser());

  @override
  String personaName() => _bindings.readNullableUtf8(
    _bindings.friendsGetPersonaName(_requireSteamFriends()),
  );

  @override
  int friendCount(final int flags) =>
      _bindings.friendsGetFriendCount(_requireSteamFriends(), flags);

  @override
  int friendByIndex(final int index, final int flags) =>
      _bindings.friendsGetFriendByIndex(_requireSteamFriends(), index, flags);

  @override
  String friendPersonaName(final int steamId) => _bindings.readNullableUtf8(
    _bindings.friendsGetFriendPersonaName(_requireSteamFriends(), steamId),
  );

  @override
  bool requestCurrentStats() =>
      _bindings.userStatsRequestCurrentStats(_requireSteamUserStats());

  @override
  int? getStatInt32(final String name) {
    final arena = SteamPointerArena();
    try {
      final namePtr = arena.allocUtf8(name);
      final outValue = arena.alloc<Int32>();
      final ok = _bindings.userStatsGetStatInt32(
        _requireSteamUserStats(),
        namePtr,
        outValue,
      );
      return ok ? outValue.value : null;
    } finally {
      arena.releaseAll();
    }
  }

  @override
  double? getStatFloat(final String name) {
    final arena = SteamPointerArena();
    try {
      final namePtr = arena.allocUtf8(name);
      final outValue = arena.alloc<Float>();
      final ok = _bindings.userStatsGetStatFloat(
        _requireSteamUserStats(),
        namePtr,
        outValue,
      );
      return ok ? outValue.value : null;
    } finally {
      arena.releaseAll();
    }
  }

  @override
  bool setStatInt32(final String name, final int value) {
    final arena = SteamPointerArena();
    try {
      final namePtr = arena.allocUtf8(name);
      return _bindings.userStatsSetStatInt32(
        _requireSteamUserStats(),
        namePtr,
        value,
      );
    } finally {
      arena.releaseAll();
    }
  }

  @override
  bool setStatFloat(final String name, final double value) {
    final arena = SteamPointerArena();
    try {
      final namePtr = arena.allocUtf8(name);
      return _bindings.userStatsSetStatFloat(
        _requireSteamUserStats(),
        namePtr,
        value,
      );
    } finally {
      arena.releaseAll();
    }
  }

  @override
  bool storeStats() => _bindings.userStatsStoreStats(_requireSteamUserStats());

  @override
  bool? getAchievement(final String name) {
    final arena = SteamPointerArena();
    try {
      final namePtr = arena.allocUtf8(name);
      final achieved = arena.alloc<Uint8>();
      final ok = _bindings.userStatsGetAchievement(
        _requireSteamUserStats(),
        namePtr,
        achieved,
      );
      if (!ok) {
        return null;
      }
      return achieved.value != 0;
    } finally {
      arena.releaseAll();
    }
  }

  @override
  bool setAchievement(final String name) {
    final arena = SteamPointerArena();
    try {
      final namePtr = arena.allocUtf8(name);
      return _bindings.userStatsSetAchievement(
        _requireSteamUserStats(),
        namePtr,
      );
    } finally {
      arena.releaseAll();
    }
  }

  @override
  bool clearAchievement(final String name) {
    final arena = SteamPointerArena();
    try {
      final namePtr = arena.allocUtf8(name);
      return _bindings.userStatsClearAchievement(
        _requireSteamUserStats(),
        namePtr,
      );
    } finally {
      arena.releaseAll();
    }
  }
}
