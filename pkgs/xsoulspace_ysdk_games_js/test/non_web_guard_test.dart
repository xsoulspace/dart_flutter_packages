import 'package:test/test.dart';
import 'package:xsoulspace_ysdk_games_js/raw.dart' as raw;
import 'package:xsoulspace_ysdk_games_js/xsoulspace_ysdk_games_js.dart';

void main() {
  test('wrapper throws UnsupportedError on non-web', () async {
    expect(() => YandexGames.init(), throwsA(isA<UnsupportedError>()));
  });

  test('raw entrypoint is guarded on non-web', () {
    expect(() => raw.yaGames, throwsA(isA<UnsupportedError>()));
  });
}
