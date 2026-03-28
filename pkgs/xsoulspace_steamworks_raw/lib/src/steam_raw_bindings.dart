import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'steam_raw_exception.dart';

/// Native callback envelope used by Steam manual dispatch mode.
base class SteamCallbackMessageNative extends Struct {
  @Int32()
  external int hSteamUser;

  @Int32()
  external int callbackId;

  external Pointer<Uint8> pubParam;

  @Int32()
  external int cubParam;
}

/// Payload for callback id `703` (`SteamAPICallCompleted_t`).
base class SteamApiCallCompletedNative extends Struct {
  @Uint64()
  external int apiCall;

  @Int32()
  external int callbackId;

  @Uint32()
  external int cubParam;
}

/// Symbol resolver abstraction for production and tests.
abstract interface class SteamRawSymbolResolver {
  Pointer<T> lookup<T extends NativeType>(final String symbolName);
}

/// Production resolver using a loaded dynamic library.
final class DynamicLibrarySteamRawSymbolResolver
    implements SteamRawSymbolResolver {
  const DynamicLibrarySteamRawSymbolResolver(this.library);

  final DynamicLibrary library;

  @override
  Pointer<T> lookup<T extends NativeType>(final String symbolName) => library.lookup<T>(symbolName);
}

/// Bound Steamworks flat API symbols used by the v1 wrapper runtime.
final class SteamRawBindings {
  SteamRawBindings(final DynamicLibrary library)
    : this.fromResolver(DynamicLibrarySteamRawSymbolResolver(library));

  SteamRawBindings.fromResolver(this._resolver);

  static const int steamErrMsgMax = 1024;
  static const int steamApiCallCompletedCallbackId = 703;

  final SteamRawSymbolResolver _resolver;
  final Map<String, Function> _functionCache = <String, Function>{};

  T _lookupRequiredFunction<T extends Function>(
    final String symbolName,
    final T Function(Pointer<NativeFunction<Void Function()>>) binder,
  ) {
    final cached = _functionCache[symbolName];
    if (cached != null) {
      return cached as T;
    }

    try {
      final pointer = _resolver.lookup<NativeFunction<Void Function()>>(
        symbolName,
      );
      final fn = binder(pointer);
      _functionCache[symbolName] = fn;
      return fn;
    } on Object catch (error) {
      throw SteamRawException(
        code: SteamRawErrorCode.symbolNotFound,
        symbol: symbolName,
        message: 'Steam symbol was not found or could not be bound.',
        cause: error,
      );
    }
  }

  T? _lookupOptionalFunction<T extends Function>(
    final String symbolName,
    final T Function(Pointer<NativeFunction<Void Function()>>) binder,
  ) {
    final cached = _functionCache[symbolName];
    if (cached != null) {
      return cached as T;
    }

    try {
      final pointer = _resolver.lookup<NativeFunction<Void Function()>>(
        symbolName,
      );
      final fn = binder(pointer);
      _functionCache[symbolName] = fn;
      return fn;
    } on Object {
      return null;
    }
  }

  bool _asBool(final int value) => value != 0;

  int _asNativeBool(final bool value) => value ? 1 : 0;

  Pointer<Void> _lookupVersionedInterface(final List<String> candidateSymbols) {
    for (final symbol in candidateSymbols) {
      final fn = _lookupOptionalFunction<_VoidPointerDart>(
        symbol,
        (final pointer) => pointer
            .cast<NativeFunction<Pointer<Void> Function()>>()
            .asFunction<_VoidPointerDart>(),
      );
      if (fn != null) {
        final value = fn();
        if (value != nullptr) {
          return value;
        }
      }
    }

    throw SteamRawException(
      code: SteamRawErrorCode.symbolNotFound,
      symbol: candidateSymbols.join(', '),
      message: 'Versioned Steam interface accessor symbol was not found.',
    );
  }

  int initializeFlat(final Pointer<Uint8> outErrorBuffer) {
    final initFlat =
        _lookupOptionalFunction<_InitFlatDart>(
          'SteamAPI_InitFlat',
          (final pointer) => pointer
              .cast<NativeFunction<_InitFlatNative>>()
              .asFunction<_InitFlatDart>(),
        ) ??
        _lookupOptionalFunction<_InitFlatDart>(
          'SteamAPI_InitEx',
          (final pointer) => pointer
              .cast<NativeFunction<_InitFlatNative>>()
              .asFunction<_InitFlatDart>(),
        );

    if (initFlat != null) {
      return initFlat(outErrorBuffer);
    }

    final init = _lookupRequiredFunction<_InitDart>(
      'SteamAPI_Init',
      (final pointer) =>
          pointer.cast<NativeFunction<Uint8 Function()>>().asFunction<_InitDart>(),
    );
    return _asBool(init()) ? 0 : 1;
  }

  bool restartAppIfNecessary(final int appId) {
    final fn = _lookupRequiredFunction<_RestartDart>(
      'SteamAPI_RestartAppIfNecessary',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Uint32)>>()
          .asFunction<_RestartDart>(),
    );
    return _asBool(fn(appId));
  }

  void shutdown() {
    final fn = _lookupRequiredFunction<_ShutdownDart>(
      'SteamAPI_Shutdown',
      (final pointer) => pointer
          .cast<NativeFunction<Void Function()>>()
          .asFunction<_ShutdownDart>(),
    );
    fn();
  }

  void runCallbacks() {
    final fn = _lookupRequiredFunction<_RunCallbacksDart>(
      'SteamAPI_RunCallbacks',
      (final pointer) => pointer
          .cast<NativeFunction<Void Function()>>()
          .asFunction<_RunCallbacksDart>(),
    );
    fn();
  }

  int getHSteamPipe() {
    final fn = _lookupRequiredFunction<_GetHSteamPipeDart>(
      'SteamAPI_GetHSteamPipe',
      (final pointer) => pointer
          .cast<NativeFunction<Int32 Function()>>()
          .asFunction<_GetHSteamPipeDart>(),
    );
    return fn();
  }

  bool hasManualDispatch() => _lookupOptionalFunction<_ManualDispatchInitDart>(
          'SteamAPI_ManualDispatch_Init',
          (final pointer) => pointer
              .cast<NativeFunction<_ManualDispatchInitNative>>()
              .asFunction<_ManualDispatchInitDart>(),
        ) !=
        null;

  void manualDispatchInit() {
    final fn = _lookupRequiredFunction<_ManualDispatchInitDart>(
      'SteamAPI_ManualDispatch_Init',
      (final pointer) => pointer
          .cast<NativeFunction<_ManualDispatchInitNative>>()
          .asFunction<_ManualDispatchInitDart>(),
    );
    fn();
  }

  void manualDispatchRunFrame(final int hSteamPipe) {
    final fn = _lookupRequiredFunction<_ManualDispatchRunFrameDart>(
      'SteamAPI_ManualDispatch_RunFrame',
      (final pointer) => pointer
          .cast<NativeFunction<Void Function(Int32)>>()
          .asFunction<_ManualDispatchRunFrameDart>(),
    );
    fn(hSteamPipe);
  }

  bool manualDispatchGetNextCallback(
    final int hSteamPipe,
    final Pointer<SteamCallbackMessageNative> callbackMsg,
  ) {
    final fn = _lookupRequiredFunction<_ManualDispatchGetNextCallbackDart>(
      'SteamAPI_ManualDispatch_GetNextCallback',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Int32, Pointer<SteamCallbackMessageNative>)>>()
          .asFunction<_ManualDispatchGetNextCallbackDart>(),
    );
    return _asBool(fn(hSteamPipe, callbackMsg));
  }

  void manualDispatchFreeLastCallback(final int hSteamPipe) {
    final fn = _lookupRequiredFunction<_ManualDispatchFreeLastCallbackDart>(
      'SteamAPI_ManualDispatch_FreeLastCallback',
      (final pointer) => pointer
          .cast<NativeFunction<Void Function(Int32)>>()
          .asFunction<_ManualDispatchFreeLastCallbackDart>(),
    );
    fn(hSteamPipe);
  }

  bool manualDispatchGetApiCallResult({
    required final int hSteamPipe,
    required final int apiCallHandle,
    required final Pointer<Void> callbackBuffer,
    required final int callbackBufferSize,
    required final int expectedCallbackId,
    required final Pointer<Uint8> outFailed,
  }) {
    final fn = _lookupRequiredFunction<_ManualDispatchGetApiCallResultDart>(
      'SteamAPI_ManualDispatch_GetAPICallResult',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Int32, Uint64, Pointer<Void>, Int32, Int32, Pointer<Uint8>)>>()
          .asFunction<_ManualDispatchGetApiCallResultDart>(),
    );

    return _asBool(
      fn(
        hSteamPipe,
        apiCallHandle,
        callbackBuffer,
        callbackBufferSize,
        expectedCallbackId,
        outFailed,
      ),
    );
  }

  Pointer<Void> steamUser() => _lookupVersionedInterface(const <String>[
      'SteamAPI_SteamUser_v023',
      'SteamAPI_SteamUser_v022',
      'SteamAPI_SteamUser_v021',
    ]);

  Pointer<Void> steamFriends() => _lookupVersionedInterface(const <String>[
      'SteamAPI_SteamFriends_v018',
      'SteamAPI_SteamFriends_v017',
      'SteamAPI_SteamFriends_v016',
    ]);

  Pointer<Void> steamUserStats() => _lookupVersionedInterface(const <String>[
      'SteamAPI_SteamUserStats_v013',
      'SteamAPI_SteamUserStats_v012',
      'SteamAPI_SteamUserStats_v011',
    ]);

  bool userIsLoggedOn(final Pointer<Void> steamUser) {
    final fn = _lookupRequiredFunction<_UserLoggedOnDart>(
      'SteamAPI_ISteamUser_BLoggedOn',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Pointer<Void>)>>()
          .asFunction<_UserLoggedOnDart>(),
    );
    return _asBool(fn(steamUser));
  }

  int userSteamId(final Pointer<Void> steamUser) {
    final fn = _lookupRequiredFunction<_UserGetSteamIdDart>(
      'SteamAPI_ISteamUser_GetSteamID',
      (final pointer) => pointer
          .cast<NativeFunction<Uint64 Function(Pointer<Void>)>>()
          .asFunction<_UserGetSteamIdDart>(),
    );
    return fn(steamUser);
  }

  Pointer<Utf8> friendsGetPersonaName(final Pointer<Void> steamFriends) {
    final fn = _lookupRequiredFunction<_FriendsGetPersonaNameDart>(
      'SteamAPI_ISteamFriends_GetPersonaName',
      (final pointer) => pointer
          .cast<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>()
          .asFunction<_FriendsGetPersonaNameDart>(),
    );
    return fn(steamFriends);
  }

  int friendsGetFriendCount(final Pointer<Void> steamFriends, final int flags) {
    final fn = _lookupRequiredFunction<_FriendsGetFriendCountDart>(
      'SteamAPI_ISteamFriends_GetFriendCount',
      (final pointer) => pointer
          .cast<NativeFunction<Int32 Function(Pointer<Void>, Int32)>>()
          .asFunction<_FriendsGetFriendCountDart>(),
    );
    return fn(steamFriends, flags);
  }

  int friendsGetFriendByIndex(
    final Pointer<Void> steamFriends,
    final int index,
    final int flags,
  ) {
    final fn = _lookupRequiredFunction<_FriendsGetFriendByIndexDart>(
      'SteamAPI_ISteamFriends_GetFriendByIndex',
      (final pointer) => pointer
          .cast<NativeFunction<Uint64 Function(Pointer<Void>, Int32, Int32)>>()
          .asFunction<_FriendsGetFriendByIndexDart>(),
    );
    return fn(steamFriends, index, flags);
  }

  Pointer<Utf8> friendsGetFriendPersonaName(
    final Pointer<Void> steamFriends,
    final int friendSteamId,
  ) {
    final fn = _lookupRequiredFunction<_FriendsGetFriendPersonaNameDart>(
      'SteamAPI_ISteamFriends_GetFriendPersonaName',
      (final pointer) => pointer
          .cast<NativeFunction<Pointer<Utf8> Function(Pointer<Void>, Uint64)>>()
          .asFunction<_FriendsGetFriendPersonaNameDart>(),
    );
    return fn(steamFriends, friendSteamId);
  }

  bool userStatsRequestCurrentStats(final Pointer<Void> steamUserStats) {
    final fn = _lookupRequiredFunction<_UserStatsRequestCurrentStatsDart>(
      'SteamAPI_ISteamUserStats_RequestCurrentStats',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Pointer<Void>)>>()
          .asFunction<_UserStatsRequestCurrentStatsDart>(),
    );
    return _asBool(fn(steamUserStats));
  }

  bool userStatsGetStatInt32(
    final Pointer<Void> steamUserStats,
    final Pointer<Utf8> name,
    final Pointer<Int32> outValue,
  ) {
    final fn = _lookupRequiredFunction<_UserStatsGetStatInt32Dart>(
      'SteamAPI_ISteamUserStats_GetStatInt32',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int32>)>>()
          .asFunction<_UserStatsGetStatInt32Dart>(),
    );
    return _asBool(fn(steamUserStats, name, outValue));
  }

  bool userStatsGetStatFloat(
    final Pointer<Void> steamUserStats,
    final Pointer<Utf8> name,
    final Pointer<Float> outValue,
  ) {
    final fn = _lookupRequiredFunction<_UserStatsGetStatFloatDart>(
      'SteamAPI_ISteamUserStats_GetStatFloat',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>)>>()
          .asFunction<_UserStatsGetStatFloatDart>(),
    );
    return _asBool(fn(steamUserStats, name, outValue));
  }

  bool userStatsSetStatInt32(
    final Pointer<Void> steamUserStats,
    final Pointer<Utf8> name,
    final int value,
  ) {
    final fn = _lookupRequiredFunction<_UserStatsSetStatInt32Dart>(
      'SteamAPI_ISteamUserStats_SetStatInt32',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Pointer<Void>, Pointer<Utf8>, Int32)>>()
          .asFunction<_UserStatsSetStatInt32Dart>(),
    );
    return _asBool(fn(steamUserStats, name, value));
  }

  bool userStatsSetStatFloat(
    final Pointer<Void> steamUserStats,
    final Pointer<Utf8> name,
    final double value,
  ) {
    final fn = _lookupRequiredFunction<_UserStatsSetStatFloatDart>(
      'SteamAPI_ISteamUserStats_SetStatFloat',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Pointer<Void>, Pointer<Utf8>, Float)>>()
          .asFunction<_UserStatsSetStatFloatDart>(),
    );
    return _asBool(fn(steamUserStats, name, value));
  }

  bool userStatsStoreStats(final Pointer<Void> steamUserStats) {
    final fn = _lookupRequiredFunction<_UserStatsStoreStatsDart>(
      'SteamAPI_ISteamUserStats_StoreStats',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Pointer<Void>)>>()
          .asFunction<_UserStatsStoreStatsDart>(),
    );
    return _asBool(fn(steamUserStats));
  }

  bool userStatsGetAchievement(
    final Pointer<Void> steamUserStats,
    final Pointer<Utf8> name,
    final Pointer<Uint8> outAchieved,
  ) {
    final fn = _lookupRequiredFunction<_UserStatsGetAchievementDart>(
      'SteamAPI_ISteamUserStats_GetAchievement',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>)>>()
          .asFunction<_UserStatsGetAchievementDart>(),
    );
    return _asBool(fn(steamUserStats, name, outAchieved));
  }

  bool userStatsSetAchievement(
    final Pointer<Void> steamUserStats,
    final Pointer<Utf8> name,
  ) {
    final fn = _lookupRequiredFunction<_UserStatsSetAchievementDart>(
      'SteamAPI_ISteamUserStats_SetAchievement',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Pointer<Void>, Pointer<Utf8>)>>()
          .asFunction<_UserStatsSetAchievementDart>(),
    );
    return _asBool(fn(steamUserStats, name));
  }

  bool userStatsClearAchievement(
    final Pointer<Void> steamUserStats,
    final Pointer<Utf8> name,
  ) {
    final fn = _lookupRequiredFunction<_UserStatsClearAchievementDart>(
      'SteamAPI_ISteamUserStats_ClearAchievement',
      (final pointer) => pointer
          .cast<NativeFunction<Uint8 Function(Pointer<Void>, Pointer<Utf8>)>>()
          .asFunction<_UserStatsClearAchievementDart>(),
    );
    return _asBool(fn(steamUserStats, name));
  }

  String readNullableUtf8(final Pointer<Utf8> value) {
    if (value == nullptr) {
      return '';
    }
    return value.toDartString();
  }

  int encodeBool(final bool value) => _asNativeBool(value);
}

typedef _InitFlatNative = Int32 Function(Pointer<Uint8>);
typedef _InitFlatDart = int Function(Pointer<Uint8>);

typedef _InitDart = int Function();

typedef _RestartDart = int Function(int);

typedef _ShutdownDart = void Function();

typedef _RunCallbacksDart = void Function();

typedef _GetHSteamPipeDart = int Function();

typedef _ManualDispatchInitNative = Void Function();
typedef _ManualDispatchInitDart = void Function();

typedef _ManualDispatchRunFrameDart = void Function(int);

typedef _ManualDispatchGetNextCallbackDart =
    int Function(int, Pointer<SteamCallbackMessageNative>);

typedef _ManualDispatchFreeLastCallbackDart = void Function(int);

typedef _ManualDispatchGetApiCallResultDart =
    int Function(int, int, Pointer<Void>, int, int, Pointer<Uint8>);

typedef _VoidPointerDart = Pointer<Void> Function();

typedef _UserLoggedOnDart = int Function(Pointer<Void>);

typedef _UserGetSteamIdDart = int Function(Pointer<Void>);

typedef _FriendsGetPersonaNameDart = Pointer<Utf8> Function(Pointer<Void>);

typedef _FriendsGetFriendCountDart = int Function(Pointer<Void>, int);

typedef _FriendsGetFriendByIndexDart = int Function(Pointer<Void>, int, int);

typedef _FriendsGetFriendPersonaNameDart =
    Pointer<Utf8> Function(Pointer<Void>, int);

typedef _UserStatsRequestCurrentStatsDart = int Function(Pointer<Void>);

typedef _UserStatsGetStatInt32Dart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int32>);

typedef _UserStatsGetStatFloatDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>);

typedef _UserStatsSetStatInt32Dart =
    int Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _UserStatsSetStatFloatDart =
    int Function(Pointer<Void>, Pointer<Utf8>, double);

typedef _UserStatsStoreStatsDart = int Function(Pointer<Void>);

typedef _UserStatsGetAchievementDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>);

typedef _UserStatsSetAchievementDart =
    int Function(Pointer<Void>, Pointer<Utf8>);

typedef _UserStatsClearAchievementDart =
    int Function(Pointer<Void>, Pointer<Utf8>);
