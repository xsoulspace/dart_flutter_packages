import 'package:test/test.dart';
import 'package:xsoulspace_vkplay_js/raw.dart' as raw;
import 'package:xsoulspace_vkplay_js/xsoulspace_vkplay_js.dart';

void main() {
  test('wrapper throws UnsupportedError on non-web', () async {
    expect(() => VkPlay.init(), throwsA(isA<UnsupportedError>()));
  });

  test('raw entrypoint is guarded on non-web', () {
    expect(() => raw.iframeApi, throwsA(isA<UnsupportedError>()));
  });
}
