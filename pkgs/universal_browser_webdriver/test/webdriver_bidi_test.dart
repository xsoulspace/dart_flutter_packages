
import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_webdriver/testing.dart';
import 'package:universal_browser_webdriver/universal_browser_webdriver.dart';

void main() {
  late FakeWebDriverServer server;
  late WebDriverClient client;

  setUp(() async {
    server = FakeWebDriverServer();
    final base = await server.start();
    client = WebDriverClient(base);
  });

  tearDown(() async {
    await client.deleteSession();
    await server.stop();
  });

  group('WebDriver BiDi', () {
    test('new session advertises the BiDi socket URL', () async {
      await client.newSession();
      expect(client.webSocketUrl, isNotNull);
      expect(
        client.webSocketUrl.toString(),
        startsWith('ws://127.0.0.1:'),
      );
    });

    test('subscribe, navigate, getTree, and evaluate over BiDi',
        () async {
      await client.newSession();
      final bidi = await client.bidi();

      await bidi.send('session.subscribe', {
        'events': ['log.entryAdded'],
      });
      expect(server.bidiCommands, contains('session.subscribe'));

      await WebDriverBidiSession(bidi).navigate(
        Uri.parse('https://example.test/bidi'),
      );
      expect(server.currentUrl, 'https://example.test/bidi');

      final session = WebDriverBidiSession(bidi);
      final tree = await session.getTree();
      expect(tree, hasLength(1));
      expect(tree.first.context, 'ctx-1');

      final value = await session.evaluate('1 + 1');
      expect(value, 42);

      await bidi.close();
    });

    test('events stream to the client', () async {
      await client.newSession();
      final bidi = await client.bidi();
      final events = bidi
          .on('log.entryAdded')
          .take(1)
          .toList()
          .timeout(const Duration(seconds: 5));
      // Subscribe first (events only flow to subscribed sessions).
      await bidi.send('session.subscribe', {
        'events': ['log.entryAdded'],
      });
      server.emitBidiEvent('log.entryAdded', {
        'type': 'console',
        'level': 'warning',
        'text': 'careful',
      });
      final received = await events;
      expect(received.single.method, 'log.entryAdded');
      expect(received.single.params['text'], 'careful');
      await bidi.close();
    });

    test('BiDi error envelopes surface as BidiException', () async {
      await client.newSession();
      final bidi = await client.bidi();
      await expectLater(
        bidi.send('no.suchMethod'),
        throwsA(
          isA<BidiException>()
              .having((e) => e.bidiError, 'error', 'unknown command'),
        ),
      );
      await bidi.close();
    });

    test('missing webSocketUrl fails loudly', () async {
      server.bidiEnabled = false;
      await client.newSession();
      expect(client.webSocketUrl, isNull);
      await expectLater(client.bidi(),
          throwsA(isA<DriverUnsupportedException>()));
    });
  });
}
