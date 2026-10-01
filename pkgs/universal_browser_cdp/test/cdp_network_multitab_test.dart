import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_browser_cdp/testing.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

/// Lets emitted socket events cross the loop before asserting.
Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeCdpServer server;

  setUp(() async {
    server = FakeCdpServer();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  group('CdpNetworkLog', () {
    test('tracks request lifecycle and bodies', () async {
      final session = await CdpBrowserSession.attach(server.httpBase);
      final network = session.page.network;

      server.emit('Network.requestWillBeSent', {
        'requestId': 'r1',
        'request': {
          'url': 'https://example.test/api',
          'method': 'GET',
        },
        'type': 'XHR',
      });
      await pump();
      expect(network.requests, hasLength(1));
      expect(network.inFlightCount, 1);
      expect(network.requests.single.url, 'https://example.test/api');

      server.emit('Network.responseReceived', {
        'requestId': 'r1',
        'response': {'status': 200, 'mimeType': 'application/json'},
      });
      await pump();
      final responded = network.requests.single;
      expect(responded.status, 200);
      expect(responded.mimeType, 'application/json');

      server.emit('Network.loadingFinished', {'requestId': 'r1'});
      await pump();
      expect(network.requests.single.finished, isTrue);
      expect(network.inFlightCount, 0);

      expect(await network.responseBody('r1'), '{"ok":true}');
    });

    test('records failures', () async {
      final session = await CdpBrowserSession.attach(server.httpBase);
      final network = session.page.network;
      server
        ..emit('Network.requestWillBeSent', {
          'requestId': 'r2',
          'request': {'url': 'https://example.test/x', 'method': 'GET'},
        })
        ..emit('Network.loadingFailed', {
          'requestId': 'r2',
          'errorText': 'net::ERR_BLOCKED_BY_CLIENT',
          'canceled': false,
        });
      await pump();
      final entry = network.requests.single;
      expect(entry.failed, isTrue);
      expect(entry.failureText, 'net::ERR_BLOCKED_BY_CLIENT');
      expect(network.inFlightCount, 0);
    });

    test('folds redirects into one entry', () async {
      final session = await CdpBrowserSession.attach(server.httpBase);
      final network = session.page.network;
      server
        ..emit('Network.requestWillBeSent', {
          'requestId': 'r3',
          'request': {'url': 'https://example.test/a', 'method': 'GET'},
        })
        ..emit('Network.requestWillBeSent', {
          'requestId': 'r3',
          'request': {'url': 'https://example.test/b', 'method': 'GET'},
          'redirectResponse': {'status': 302},
        });
      await pump();
      expect(network.requests, hasLength(1));
      final redirected = network.requests.single;
      expect(redirected.redirectCount, 1);
      expect(redirected.url, 'https://example.test/b');
      expect(network.requests.single.status, 302);
      expect(network.inFlightCount, 1);
    });

    test('waitIdle completes when quiet, times out when busy', () async {
      final session = await CdpBrowserSession.attach(server.httpBase);
      final network = session.page.network;
      await network.waitIdle(quiet: const Duration(milliseconds: 100));

      server.emit('Network.requestWillBeSent', {
        'requestId': 'busy',
        'request': {'url': 'https://example.test/slow', 'method': 'GET'},
      });
      await pump();
      await expectLater(
        network.waitIdle(
          quiet: const Duration(milliseconds: 50),
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('CdpBrowser multi-tab', () {
    test('attaches over flat sessions and tracks pages', () async {
      final browser = await CdpBrowser.connect(server.httpBase);
      final page = await browser.attachFirstPage();
      expect(browser.pages, [page]);
      // Domain enablement went over the multiplexed socket.
      expect(server.methods, contains('Page.enable'));

      final second = await browser.openPage(url: Uri.parse('https://x.test'));
      expect(server.createdTargets, contains('page-1'));
      expect(server.sessions, contains('session-page-1'));
      expect(browser.pages, containsAll([page, second]));
      expect(identical(page, second), isFalse);

      await browser.closePage(second);
      expect(browser.pages, [page]);
      expect(
        server.methods
            .where((method) => method == 'Target.closeTarget')
            .length,
        1,
      );
      expect(second.isClosed, isTrue);

      await browser.close();
      expect(page.isClosed, isTrue);
      expect(browser.pages, isEmpty);
    });

    test('switchTo returns the named page driver and rejects foreign pages',
        () async {
      final browser = await CdpBrowser.connect(server.httpBase);
      final page = await browser.attachFirstPage();
      final driver = browser.switchTo(page);
      expect(driver.page, same(page));

      final stranger = await CdpBrowserSession.attach(server.httpBase);
      expect(
        () => browser.switchTo(stranger.page),
        throwsA(isA<ArgumentError>()),
      );
      // switchTo mutated nothing: the original pages list is intact.
      expect(browser.pages, [page]);
      await browser.close();
      await stranger.detach();
    });

    test('targetDestroyed marks the page closed', () async {
      final browser = await CdpBrowser.connect(server.httpBase);
      final page = await browser.attachFirstPage();
      server.emit('Target.targetDestroyed', {'targetId': 'page-1'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(page.isClosed, isTrue);
      expect(browser.pages, isEmpty);
      await browser.close();
    });
  });
}
