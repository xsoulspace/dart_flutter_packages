import 'package:meta/meta.dart';

@immutable
final class YandexGamesPlatformConfig {
  const YandexGamesPlatformConfig({this.signed = false});

  final bool signed;
}
