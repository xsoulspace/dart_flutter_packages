import 'package:test/test.dart';
import 'package:xsoulspace_crazygames_js/raw.dart' as raw;
import 'package:xsoulspace_crazygames_js/xsoulspace_crazygames_js.dart';

void main() {
  test('wrapper throws UnsupportedError on non-web', () async {
    expect(() => CrazyGames.init(), throwsA(isA<UnsupportedError>()));
  });

  test('availability probe is false on non-web', () {
    expect(CrazyGames.isAvailable(), isFalse);
  });

  test('raw entrypoint is guarded on non-web', () {
    expect(() => raw.crazyGames, throwsA(isA<UnsupportedError>()));
    expect(() => raw.crazyGamesSdk, throwsA(isA<UnsupportedError>()));
  });
}
