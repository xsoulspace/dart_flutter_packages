import 'package:test/test.dart';
import 'package:xsoulspace_discord_js/raw.dart' as raw;
import 'package:xsoulspace_discord_js/xsoulspace_discord_js.dart';

void main() {
  test('wrapper throws UnsupportedError on non-web', () async {
    expect(
      () => Discord.init(clientId: '123'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('raw entrypoint is guarded on non-web', () {
    expect(() => raw.DiscordSDK, throwsA(isA<UnsupportedError>()));
  });
}
