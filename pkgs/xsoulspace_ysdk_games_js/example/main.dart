import 'package:xsoulspace_ysdk_games_js/xsoulspace_ysdk_games_js.dart';

Future<void> main() async {
  final ysdk = await YandexGames.init();

  final flags = await ysdk.getFlags(
    defaultFlags: <String, String>{'music': 'on'},
  );

  final player = await ysdk.getPlayerUnsigned();

  // This is a minimal package usage example for pub.dev.
  final hasMusicFlag = flags['music'] == 'on';
  final uniqueId = player.getUniqueId();
  if (!hasMusicFlag || uniqueId.isEmpty) {
    throw StateError('Unexpected Yandex SDK example values.');
  }
}
