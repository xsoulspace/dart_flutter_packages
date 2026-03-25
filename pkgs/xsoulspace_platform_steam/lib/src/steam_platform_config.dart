import 'package:meta/meta.dart';
import 'package:xsoulspace_steamworks/xsoulspace_steamworks.dart';

@immutable
final class SteamPlatformConfig {
  const SteamPlatformConfig({
    required this.appId,
    this.autoPumpCallbacks = true,
    this.callbackInterval = const Duration(milliseconds: 16),
    this.librarySearchPaths = const <String>[],
    this.enableVerboseLogs = false,
  });

  final int appId;
  final bool autoPumpCallbacks;
  final Duration callbackInterval;
  final List<String> librarySearchPaths;
  final bool enableVerboseLogs;

  SteamInitConfig toSteamInitConfig() {
    return SteamInitConfig(
      appId: appId,
      autoPumpCallbacks: autoPumpCallbacks,
      callbackInterval: callbackInterval,
      librarySearchPaths: librarySearchPaths,
      enableVerboseLogs: enableVerboseLogs,
    );
  }
}
