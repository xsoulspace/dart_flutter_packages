import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_automation_conformance/universal_automation_conformance.dart';
import 'package:universal_browser_cdp/testing.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

void main() {
  late FakeCdpServer server;
  late Uri httpBase;

  setUp(() async {
    server = FakeCdpServer();
    httpBase = await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  group('CdpDiscovery', () {
    test('probes version', () async {
      final version = await CdpDiscovery.version(httpBase);
      expect(version, isNotNull);
      expect(version!.browser, startsWith('FakeChrome'));
    });

    test('requireAlive passes on live endpoint', () async {
      final version = await CdpDiscovery.requireAlive(httpBase);
      expect(version.protocolVersion, '1.3');
    });

    test('requireAlive refuses a dead endpoint', () async {
      final dead = Uri.parse('http://127.0.0.1:1');
      await expectLater(
        CdpDiscovery.requireAlive(
          dead,
          timeout: const Duration(milliseconds: 500),
        ),
        throwsA(isA<EndpointUnreachableException>()),
      );
    });

    test('lists page targets', () async {
      final targets = await CdpDiscovery.listTargets(httpBase);
      expect(targets, hasLength(1));
      expect(targets.first.type, 'page');
      expect(targets.first.webSocketDebuggerUrl, startsWith('ws://'));
    });
  });

  group('CdpConnection', () {
    late CdpConnection connection;

    setUp(() async {
      final target = await CdpDiscovery.findTarget(httpBase);
      connection = await CdpConnection.connect(
        Uri.parse(target!.webSocketDebuggerUrl),
      );
    });

    tearDown(() async {
      await connection.close();
    });

    test('correlates concurrent requests', () async {
      final first = connection.send('Page.enable');
      final second = connection.send('Accessibility.getFullAXTree');
      final tree = await second;
      await first;
      expect(tree['nodes'], isA<List<Object?>>());
    });

    test('surfaces protocol errors', () async {
      server.failNextWithError = {'code': -32601, 'message': 'nope'};
      await expectLater(
        connection.send('Page.unknownMethod'),
        throwsA(
          isA<CdpProtocolException>().having((e) => e.code, 'code', -32601),
        ),
      );
    });

    test('delivers events', () async {
      final events = connection.on('Page.frameNavigated').take(1).toList();
      await connection.send('Page.navigate', {'url': 'https://example.test/'});
      final received = await events.timeout(const Duration(seconds: 5));
      expect(
        (received.first.params['frame']! as Map<String, Object?>)['url']!
            as String,
        'https://example.test/',
      );
    });

    test('send after close throws', () async {
      await connection.close();
      expect(() => connection.send('Page.enable'), throwsStateError);
    });
  });

  group('CdpPage', () {
    late CdpBrowserSession session;

    setUp(() async {
      session = await CdpBrowserSession.attach(httpBase);
    });

    tearDown(() async {
      await session.close();
    });

    test('navigates and bumps revision', () async {
      final page = session.page;
      final before = page.revision;
      await page.navigate(Uri.parse('https://example.test/page'));
      expect(server.currentUrl, 'https://example.test/page');
      expect(page.revision, before + 1);
    });

    test('maps the accessibility tree to the family model', () async {
      final snapshot = await session.page.accessibilitySnapshot();
      expect(snapshot.roots, hasLength(1));
      final root = snapshot.roots.first;
      final button = root.byRole('button', name: 'Submit');
      expect(button, isNotNull);
      expect(button!.bounds!.center, (140.0, 100.0));
      expect(root.byRole('generic', name: 'hint'), isNotNull);
      expect(root.byName('ignored-node'), isNull);
    });

    test('captures a screenshot', () async {
      final bytes = await session.page.screenshot();
      expect(bytes, isNotEmpty);
      expect(base64Encode(bytes), server.screenshotBase64);
    });

    test('clicks dispatch trusted mouse events at the rect center', () async {
      await session.page.click(css: '#submit');
      final events = server.inputEvents;
      // Auto-waited click: move to the point, then press + release.
      expect(events, hasLength(3));
      expect(events[0]['method'], 'Input.dispatchMouseEvent');
      expect(events[0]['type'], 'mouseMoved');
      expect((events[0]['x']! as num).toDouble(), 140.0);
      expect((events[0]['y']! as num).toDouble(), 100.0);
      expect(events[1]['type'], 'mousePressed');
      expect(events[2]['type'], 'mouseReleased');
    });

    test('typing emits per-key events and submits with Enter', () async {
      await session.page.type('hi', css: '#email', submit: true);
      final keyEvents = server.inputEvents
          .where((event) => event['method'] == 'Input.dispatchKeyEvent')
          .toList();
      // h down, h up, i down, i up, Enter down, Enter up.
      expect(keyEvents, hasLength(6));
      expect(keyEvents.first['key'], 'h');
      expect(keyEvents.first['windowsVirtualKeyCode'], 72);
      expect(keyEvents.first['text'], 'h');
      expect(keyEvents.last['key'], 'Enter');
      expect(keyEvents.last['type'], 'keyUp');
    });

    test('unknown keys are refused loudly', () async {
      await expectLater(
        session.page.keyPress('Shift'),
        throwsA(isA<DriverUnsupportedException>()),
      );
    });
  });

  automationDriverConformanceTests(
    'CdpDriver over FakeCdpServer',
    createDriver: () async {
      final session = await CdpBrowserSession.attach(httpBase);
      return CdpDriver(session.page);
    },
  );
}
