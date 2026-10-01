import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/testing.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

void main() {
  late FakeCdpServer server;

  setUp(() async {
    server = FakeCdpServer();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  group('navigate waitUntil', () {
    test('commit does not wait for the load event', () async {
      server.emitLifecycleEvents = false;
      final session = await CdpBrowserSession.attach(server.httpBase);
      final watch = Stopwatch()..start();
      await session.page.navigate(
        Uri.parse('https://example.test'),
        waitUntil: NavigateWait.commit,
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(server.currentUrl, 'https://example.test');
    });

    test('load waits for Page.loadEventFired', () async {
      server.emitLifecycleEvents = false;
      final session = await CdpBrowserSession.attach(server.httpBase);
      final page = session.page;
      final pending = page.navigate(Uri.parse('https://example.test'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      server.emit('Page.loadEventFired', const {});
      await pending;
      expect(page.revision, 1);
    });

    test('load times out when the load event never fires', () async {
      server.emitLifecycleEvents = false;
      final session = await CdpBrowserSession.attach(server.httpBase);
      await expectLater(
        session.page.navigate(
          Uri.parse('https://example.test'),
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('networkIdle resolves when the network sits quiet', () async {
      final session = await CdpBrowserSession.attach(server.httpBase);
      // No pending requests: only the 500ms quiet window has to pass.
      await session.page.navigate(
        Uri.parse('https://example.test'),
        waitUntil: NavigateWait.networkIdle,
        timeout: const Duration(seconds: 5),
      );
      expect(session.page.network.inFlightCount, 0);
    });

    test('networkIdle refuses to resolve while requests are in flight',
        () async {
      final session = await CdpBrowserSession.attach(server.httpBase);
      final page = session.page;
      final pending = page.navigate(
        Uri.parse('https://example.test'),
        waitUntil: NavigateWait.networkIdle,
        timeout: const Duration(milliseconds: 800),
      );
      // A request lands after the load events but never finishes.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      server.emit('Network.requestWillBeSent', {
        'requestId': 'pending-1',
        'request': {'url': 'https://example.test/api', 'method': 'GET'},
        'type': 'XHR',
      });
      await expectLater(pending, throwsA(isA<TimeoutException>()));
      expect(page.network.inFlightCount, 1);
    });
  });

  group('actionability polling', () {
    test('click waits for the element to become ready', () async {
      var probes = 0;
      server.evaluateHandler = (expression) {
        probes++;
        if (probes < 3) return '{"state":"detached"}';
        return '{"state":"ready","x":40,"y":60,"width":200,"height":80}';
      };
      final session = await CdpBrowserSession.attach(server.httpBase);
      await session.page.click(
        css: '#late',
        timeout: const Duration(seconds: 3),
      );
      expect(probes, greaterThanOrEqualTo(3));
      // Move, press, release — at the ready rect's center.
      expect(server.inputEvents[0]['type'], 'mouseMoved');
      expect((server.inputEvents[1]['x']! as num).toDouble(), 140.0);
      expect(server.inputEvents[2]['type'], 'mouseReleased');
    });

    test('click requires rect stability before dispatching', () async {
      var probes = 0;
      server.evaluateHandler = (expression) {
        probes++;
        // Every probe reports a different rect: never stable.
        return '{"state":"ready","x":40,"y":${60 + probes},'
            '"width":200,"height":80}';
      };
      final session = await CdpBrowserSession.attach(server.httpBase);
      await expectLater(
        session.page.click(
          css: '#unstable',
          timeout: const Duration(milliseconds: 400),
        ),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.details['state'],
            'state',
            'stable?',
          ),
        ),
      );
      expect(server.inputEvents, isEmpty);
    });

    test('force skips visible/stable/hittable but not existence', () async {
      server.evaluateHandler =
          (expression) =>
              '{"state":"hidden","x":40,"y":60,"width":200,"height":80}';
      final session = await CdpBrowserSession.attach(server.httpBase);
      await session.page.click(
        css: '#hidden',
        force: true,
        timeout: const Duration(milliseconds: 500),
      );
      expect(server.inputEvents, hasLength(3));
    });

    test('a detached element never dispatches, even with force', () async {
      server.evaluateHandler = (expression) => '{"state":"detached"}';
      final session = await CdpBrowserSession.attach(server.httpBase);
      await expectLater(
        session.page.click(
          css: '#gone',
          force: true,
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<ProtocolException>()),
      );
      expect(server.inputEvents, isEmpty);
    });

    test('type waits for the element then emits per-key events', () async {
      var probes = 0;
      server.evaluateHandler = (expression) {
        probes++;
        if (probes == 1) {
          return '{"state":"hidden","x":0,"y":0,"width":0,"height":0}';
        }
        return '{"state":"ready","x":40,"y":60,"width":200,"height":80}';
      };
      final session = await CdpBrowserSession.attach(server.httpBase);
      await session.page.type(
        'éx',
        css: '#field',
        timeout: const Duration(seconds: 3),
      );
      // Non-ASCII rune lowers to insertText; printable rune to keys.
      final insertTexts = server.inputEvents
          .where((event) => event['method'] == 'Input.insertText')
          .toList();
      expect(insertTexts, hasLength(1));
      expect(insertTexts.single['text'], 'é');
      final keyDowns = server.inputEvents
          .where((event) =>
              event['method'] == 'Input.dispatchKeyEvent' &&
              event['type'] == 'keyDown')
          .toList();
      expect(keyDowns.single['key'], 'x');
      expect(probes, greaterThanOrEqualTo(2));
    });
  });

  group('semantic click', () {
    setUp(() {
      server.axNodes = [
        {
          'nodeId': '1',
          'role': {'value': 'root'},
          'name': {'value': 'document'},
          'childIds': ['2'],
        },
        {
          'nodeId': '2',
          'role': {'value': 'button'},
          'name': {'value': 'Submit'},
          'bounds': {'x': 40, 'y': 60, 'width': 200, 'height': 80},
          'backendDOMNodeId': 42,
        },
      ];
    });

    test('resolves role/name through the semantic index', () async {
      server.callFunctionOnValue =
          '{"state":"ready","x":40,"y":60,"width":200,"height":80}';
      final session = await CdpBrowserSession.attach(server.httpBase);
      final driver = CdpDriver(session.page);
      await driver.perform(const ClickAction(role: 'button', name: 'Submit'));
      expect(server.methods, contains('DOM.resolveNode'));
      expect(server.methods, contains('Runtime.callFunctionOn'));
      // Move, press, release at the resolved center.
      expect(server.inputEvents, hasLength(3));
      expect((server.inputEvents[1]['x']! as num).toDouble(), 140.0);
    });

    test('unknown semantic targets refuse with the locator named', () async {
      final session = await CdpBrowserSession.attach(server.httpBase);
      final driver = CdpDriver(session.page);
      await expectLater(
        driver.perform(const ClickAction(name: 'Nonexistent')),
        throwsA(
          isA<ElementNotFoundException>()
              .having((error) => error.locator, 'locator', 'name')
              .having(
                (error) => error.locatorValue,
                'locatorValue',
                'Nonexistent',
              ),
        ),
      );
      expect(server.inputEvents, isEmpty);
    });
  });
}
