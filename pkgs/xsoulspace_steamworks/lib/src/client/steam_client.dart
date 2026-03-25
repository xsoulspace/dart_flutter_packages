import 'dart:async';
import 'dart:io';

import 'package:xsoulspace_steamworks_raw/xsoulspace_steamworks_raw.dart';

import '../events/steam_event.dart';
import '../native/steam_native_api.dart';
import '../native/steam_raw_native_api.dart';
import '../runtime/async_call_registry.dart';
import '../runtime/callback_engine.dart';
import '../services/steam_achievements_service.dart';
import '../services/steam_friends_service.dart';
import '../services/steam_stats_service.dart';
import '../services/steam_user_service.dart';
import 'steam_exception.dart';
import 'steam_init.dart';

/// Main Steamworks wrapper lifecycle entrypoint.
final class SteamClient {
  SteamClient({final SteamNativeApiFactory? nativeApiFactory})
    : _nativeApiFactory = nativeApiFactory ?? const SteamRawNativeApiFactory();

  final SteamNativeApiFactory _nativeApiFactory;

  final StreamController<SteamEvent> _eventsController =
      StreamController<SteamEvent>.broadcast();

  SteamNativeApi? _nativeApi;
  SteamAsyncCallRegistry? _asyncRegistry;
  SteamCallbackEngine? _callbackEngine;

  SteamUserService? _userService;
  SteamFriendsService? _friendsService;
  SteamStatsService? _statsService;
  SteamAchievementsService? _achievementsService;

  Timer? _autoPumpTimer;
  var _isInitialized = false;
  var _verboseLogs = false;

  /// Whether Steam runtime is initialized.
  bool get isInitialized => _isInitialized;

  /// Wrapper events stream.
  Stream<SteamEvent> get events => _eventsController.stream;

  SteamUserService get user => _requireService(
    _userService,
    'user service is available after initialize()',
  );

  SteamFriendsService get friends => _requireService(
    _friendsService,
    'friends service is available after initialize()',
  );

  SteamStatsService get stats => _requireService(
    _statsService,
    'stats service is available after initialize()',
  );

  SteamAchievementsService get achievements => _requireService(
    _achievementsService,
    'achievements service is available after initialize()',
  );

  /// Initializes Steam runtime and starts callback pumping based on config.
  Future<SteamInitResult> initialize(final SteamInitConfig config) async {
    config.validate();

    if (!_isDesktopPlatform()) {
      throw UnsupportedError(
        'xsoulspace_steamworks supports desktop only (Windows/macOS/Linux).',
      );
    }

    if (_isInitialized) {
      return SteamInitResult.failure(
        errorCode: SteamInitErrorCode.alreadyInitialized,
        message: 'SteamClient is already initialized.',
      );
    }

    _verboseLogs = config.enableVerboseLogs;

    final SteamNativeApi nativeApi;
    try {
      nativeApi = _nativeApiFactory.create(config);
    } on SteamRawException catch (error) {
      return SteamInitResult.failure(
        errorCode: SteamInitErrorCode.libraryLoadFailed,
        message: error.toString(),
      );
    } on Object catch (error) {
      return SteamInitResult.failure(
        errorCode: SteamInitErrorCode.unknown,
        message: error.toString(),
      );
    }

    _nativeApi = nativeApi;

    try {
      final shouldRestart = nativeApi.restartAppIfNecessary(config.appId);
      if (shouldRestart) {
        _safeShutdownNative(nativeApi);
        _clearRuntimeState();
        return SteamInitResult.failure(
          errorCode: SteamInitErrorCode.restartRequired,
          message:
              'Steam requested process restart through client launch path.',
          restartRequired: true,
        );
      }

      final init = nativeApi.initialize();
      final mappedError = _mapNativeInitCode(init.initCode);
      if (mappedError != null) {
        _safeShutdownNative(nativeApi);
        _clearRuntimeState();
        return SteamInitResult.failure(
          errorCode: mappedError,
          message: init.errorMessage,
          nativeInitCode: init.initCode,
        );
      }

      _asyncRegistry = SteamAsyncCallRegistry(
        defaultTimeout: const Duration(seconds: 10),
        onTimeout:
            (final apiCallHandle, final expectedCallbackId, final timeout) {
              _emit(
                SteamAsyncCallTimeoutEvent(
                  apiCallHandle: apiCallHandle,
                  expectedCallbackId: expectedCallbackId,
                  timeout: timeout,
                ),
              );
            },
      );

      _callbackEngine = SteamCallbackEngine(
        nativeApi: nativeApi,
        asyncRegistry: _asyncRegistry!,
        emit: _emit,
      )..initialize();

      _userService = SteamUserService(nativeApi);
      _friendsService = SteamFriendsService(nativeApi);
      _statsService = SteamStatsService(nativeApi);
      _achievementsService = SteamAchievementsService(nativeApi);

      _isInitialized = true;
      if (config.autoPumpCallbacks) {
        _startAutoPump(config.callbackInterval);
      }

      _emit(SteamLifecycleEvent(state: SteamLifecycleState.initialized));
      _log('Steam initialized successfully.');
      return SteamInitResult.success();
    } on SteamRawException catch (error) {
      _safeShutdownNative(nativeApi);
      _clearRuntimeState();
      return SteamInitResult.failure(
        errorCode: SteamInitErrorCode.libraryLoadFailed,
        message: error.toString(),
      );
    } on ArgumentError catch (error) {
      _safeShutdownNative(nativeApi);
      _clearRuntimeState();
      return SteamInitResult.failure(
        errorCode: SteamInitErrorCode.invalidConfig,
        message: error.toString(),
      );
    } on Object catch (error) {
      _safeShutdownNative(nativeApi);
      _clearRuntimeState();
      return SteamInitResult.failure(
        errorCode: SteamInitErrorCode.unknown,
        message: error.toString(),
      );
    }
  }

  /// Stops callback timer, releases runtime state and calls native shutdown.
  Future<void> shutdown() async {
    if (!_isInitialized) {
      return;
    }

    _autoPumpTimer?.cancel();
    _autoPumpTimer = null;

    try {
      _callbackEngine?.dispose();
      _asyncRegistry?.dispose();
      _nativeApi?.shutdown();
    } on Object catch (error) {
      _clearRuntimeState();
      throw SteamException(
        code: SteamExceptionCode.nativeFailure,
        message: 'Failed to shutdown Steam runtime.',
        cause: error,
      );
    }

    _clearRuntimeState();
    _emit(SteamLifecycleEvent(state: SteamLifecycleState.shutdown));
  }

  /// Executes a single callback pump iteration.
  void runCallbacksOnce() {
    if (!_isInitialized) {
      return;
    }
    _callbackEngine?.pumpOnce();
  }

  bool _isDesktopPlatform() {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  SteamInitErrorCode? _mapNativeInitCode(final int code) {
    switch (code) {
      case 0:
        return null;
      case 1:
        return SteamInitErrorCode.failedGeneric;
      case 2:
        return SteamInitErrorCode.noSteamClient;
      case 3:
        return SteamInitErrorCode.versionMismatch;
      default:
        return SteamInitErrorCode.unknown;
    }
  }

  void _startAutoPump(final Duration interval) {
    _autoPumpTimer?.cancel();
    _autoPumpTimer = Timer.periodic(interval, (_) {
      if (!_isInitialized) {
        return;
      }
      runCallbacksOnce();
    });
  }

  void _safeShutdownNative(final SteamNativeApi nativeApi) {
    try {
      nativeApi.shutdown();
    } on Object {
      // noop
    }
  }

  void _clearRuntimeState() {
    _autoPumpTimer?.cancel();
    _autoPumpTimer = null;

    _callbackEngine = null;
    _asyncRegistry = null;
    _nativeApi = null;

    _userService = null;
    _friendsService = null;
    _statsService = null;
    _achievementsService = null;

    _isInitialized = false;
  }

  T _requireService<T>(final T? value, final String message) {
    if (value == null) {
      throw SteamException(
        code: SteamExceptionCode.notInitialized,
        message: message,
      );
    }
    return value;
  }

  void _emit(final SteamEvent event) {
    if (_eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }

  void _log(final String message) {
    if (!_verboseLogs) {
      return;
    }
    // ignore: avoid_print
    print('[steamworks] $message');
  }
}
