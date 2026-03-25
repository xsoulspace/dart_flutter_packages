import 'package:meta/meta.dart';

typedef CrazyGamesSdkScriptLoader = Future<void> Function(Uri scriptUrl);

@immutable
final class CrazyGamesPlatformConfig {
  const CrazyGamesPlatformConfig({
    this.expectedSdkGlobal = 'CrazyGames',
    this.sdkUrl,
    this.autoLoadSdk = false,
    this.sdkScriptLoader,
    this.sdkInjected,
  });

  final String expectedSdkGlobal;
  final Uri? sdkUrl;
  final bool autoLoadSdk;
  final CrazyGamesSdkScriptLoader? sdkScriptLoader;
  final bool? sdkInjected;
}
