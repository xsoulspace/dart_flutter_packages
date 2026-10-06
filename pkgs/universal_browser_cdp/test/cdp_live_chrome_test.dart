// Live-Chromium conformance for the Flutter-web driving primitives.
//
// Opt-in (`XS_TEST_CDP_LIVE=1 fvm dart test ...`) because it spawns a
// real Chrome on this machine. The FakeCdpServer suite cannot see the
// failure class this file guards: Chromium's AX cache hands out
// `backendDOMNodeId`s that Flutter web (and any node-replacing SPA)
// invalidates between snapshot and resolve — semantic clicks died with
// "detached" against REAL Chromium while every fake passed.
//
// The `churn` fixture emulates the Flutter-web semantics DOM: nodes are
// replaced continuously, so only the fresh-snapshot + live-DOM fallback
// ladder lands a click.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

const _fixture = '''
<!DOCTYPE html>
<html><body>
  <button id="steady" aria-label="Steady button" onclick="tick(this)">0</button>
  <button id="churn" aria-label="Churning button" onclick="tick(this)">0</button>
  <input id="field" aria-label="Pairing code" />
  <script>
    function tick(el) {
      el.textContent = String(Number(el.textContent || '0') + 1);
      document.title = 'ticked';
    }
    // Flutter-web semantics emulation: the button's DOM node is replaced
    // continuously, so AX backendDOMNodeIds go stale between a snapshot
    // and the click that resolves one.
    setInterval(() => {
      const el = document.getElementById('churn');
      const copy = el.cloneNode(true);
      el.replaceWith(copy);
    }, 150);
  </script>
</body></html>
''';

void main() {
  if (Platform.environment['XS_TEST_CDP_LIVE'] != '1') {
    // ignore: avoid_print
    print('skipped: set XS_TEST_CDP_LIVE=1 to run against real Chrome');
    return;
  }

  late HttpServer fixtureServer;
  late Process chrome;
  late Uri httpBase;
  late CdpBrowserSession session;

  setUpAll(() async {
    fixtureServer = await HttpServer.bind('127.0.0.1', 0);
    fixtureServer.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_fixture);
      await request.response.close();
    });
    final fixturePort = fixtureServer.port;
    final cdpPort = await _freePort();
    final binary = _chromeBinary();
    chrome = await Process.start(binary, [
      '--headless=new',
      '--remote-debugging-port=$cdpPort',
      '--user-data-dir=${Directory.systemTemp.createTempSync('cdp-live-').path}',
      '--no-first-run',
      '--no-default-browser-check',
      '--force-renderer-accessibility',
      '--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding',
      'about:blank',
    ]);
    httpBase = Uri.parse('http://127.0.0.1:$cdpPort');
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      if (await CdpDiscovery.version(httpBase, timeout: const Duration(seconds: 2)) != null) {
        break;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Chrome never answered CDP on $httpBase');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    session = await CdpBrowserSession.attach(httpBase);
    await session.page.navigate(
      Uri.parse('http://127.0.0.1:$fixturePort/'),
      waitUntil: NavigateWait.load,
    );
    // `Page.loadEventFired` carries no loaderId, so navigate(load) can
    // return on the PREVIOUS page's load event — wait for fixture
    // content, not just navigation completion.
    for (var i = 0; i < 50; i++) {
      if (await session.page.hasNamedElement('Steady button')) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  });

  tearDownAll(() async {
    await session.close(closeTarget: true);
    chrome.kill(ProcessSignal.sigkill);
    await fixtureServer.close(force: true);
  });

  group('live Chromium', () {
    test('semantic click lands on a node-replacing (Flutter-web-like) DOM',
        () async {
      await session.driver.perform(
        const ClickAction(role: 'button', name: 'Churning button'),
      );
      final count = await session.page.evaluate(
        'document.getElementById("churn").textContent',
      );
      expect(int.parse(count! as String), greaterThanOrEqualTo(1));
    });

    test('semantic click lands on a stable DOM node', () async {
      await session.driver.perform(
        const ClickAction(role: 'button', name: 'Steady button'),
      );
      final count = await session.page.evaluate(
        'document.getElementById("steady").textContent',
      );
      expect(int.parse(count! as String), greaterThanOrEqualTo(1));
    });

    test('bringToFront + insertText + fieldValue round-trip', () async {
      await session.page.bringToFront();
      await session.page.evaluate(
        'document.getElementById("field").focus()',
      );
      await session.page.insertText('mesh-pair/v1 live');
      expect(
        await session.page.fieldValue('#field'),
        'mesh-pair/v1 live',
      );
      final values = await session.page.editableValues();
      expect(values, isNotEmpty);
      expect(values.any((entry) => entry.value == 'mesh-pair/v1 live'), isTrue);
    });
  });
}

String _chromeBinary() {
  const macPath =
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  if (Platform.isMacOS && File(macPath).existsSync()) return macPath;
  if (Platform.isWindows) return 'chrome.exe';
  return Platform.environment['CHROME_BIN'] ?? 'google-chrome';
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

// Silence the unused import when jsonEncode is unused on some SDKs.
// ignore: unused_element
final _ = jsonEncode;
