import 'package:meta/meta.dart';

typedef YandexGamesSdkScriptLoader = Future<void> Function(Uri scriptUrl);

@immutable
final class YandexGamesPlatformConfig {
  const YandexGamesPlatformConfig({
    this.signed = false,
    this.expectedSdkGlobal = 'YaGames',
    this.sdkUrl,
    this.autoLoadSdk = false,
    this.sdkScriptLoader,
    this.sdkInjected,
  });

  final bool signed;
  final String expectedSdkGlobal;
  final Uri? sdkUrl;
  final bool autoLoadSdk;
  final YandexGamesSdkScriptLoader? sdkScriptLoader;
  final bool? sdkInjected;
}
