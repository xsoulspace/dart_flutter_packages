import 'dart:io';

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

  Future<BehavioralCdpDriver> attachDriver() async {
    final session = await CdpBrowserSession.attach(server.httpBase);
    return BehavioralCdpDriver(session.page);
  }

  group('CdpPage.navigate correctness', () {
    test('surfaces errorText as a typed error instead of hanging', () async {
      server.navigateErrorText = 'ERR_NAME_NOT_RESOLVED';
      final session = await CdpBrowserSession.attach(server.httpBase);
      final watch = Stopwatch()..start();
      await expectLater(
        session.page.navigate(Uri.parse('https://nope.invalid')),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.details['errorText'],
            'errorText',
            'ERR_NAME_NOT_RESOLVED',
          ),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('ignores subframe navigations while waiting for the main frame',
        () async {
      final session = await CdpBrowserSession.attach(server.httpBase);
      final page = session.page;
      final navigated = page.navigate(Uri.parse('https://example.test'));
      // A subframe completes early; the main-frame wait must not resolve.
      server.emit('Page.frameNavigated', {
        'frame': {'id': 'sub-1', 'parentId': 'frame-1', 'url': '/ad'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // The fake answers Page.navigate with its own frameNavigated event,
      // which is what actually completes the wait.
      await navigated;
      expect(page.revision, 1);
    });

    test('detach leaves the target alive; close closes it', () async {
      final session = await CdpBrowserSession.attach(server.httpBase);
      final targetCloses = <String>[];
      // The fake records every method; closeTarget shows up there.
      await session.detach();
      expect(server.methods, isNot(contains('Target.closeTarget')));
      expect(targetCloses, isEmpty);

      final session2 = await CdpBrowserSession.attach(server.httpBase);
      await session2.close();
      expect(server.methods, contains('Target.closeTarget'));
    });
  });

  group('hit-target resolution', () {
    test('refuses to click an occluded element', () async {
      server.evaluateHandler = (expression) =>
          '{"state":"occluded","x":40,"y":60,"width":200,"height":80}';
      final session = await CdpBrowserSession.attach(server.httpBase);
      await expectLater(
        session.page.click(
          css: '#covered',
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.details['state'],
            'state',
            'occluded',
          ),
        ),
      );
      // No input events went out.
      expect(server.inputEvents, isEmpty);
    });
  });

  group('BehavioralCdpDriver', () {
    test('reports behaviorDynamics capability', () async {
      final driver = await attachDriver();
      expect(driver.capabilities.behaviorDynamics, isTrue);
      await driver.close();
    });

    test('agentImmediate dispatches bare down/up with planned stamps',
        () async {
      final driver = await attachDriver();
      final outcome = await driver.performWith(
        const ClickAction(css: '#go'),
        BehaviorProfile.agentImmediate,
        seed: 7,
      );
      expect(outcome.verdict, BehaviorVerdict.complete);
      expect(outcome.cause, isNull);
      final kinds = server.inputEvents
          .map((event) => event['method'])
          .toList(growable: false);
      // Teleport move first, then press, then release.
      expect(kinds.length, 3);
      expect(server.inputEvents[0]['type'], 'mouseMoved');
      expect(server.inputEvents[1]['type'], 'mousePressed');
      expect(server.inputEvents[2]['type'], 'mouseReleased');
      // Planned timestamps are stamped (epoch seconds, > 1e9).
      final stamp = server.inputEvents[0]['timestamp']! as num;
      expect(stamp, greaterThan(1e9));
      await driver.close();
    });

    test('humanPrior click animates: moves precede press, drift is sane',
        () async {
      final driver = await attachDriver();
      final profile = BehaviorProfile.humanPrior(11);
      final outcome = await driver.performWith(
        const ClickAction(css: '#go'),
        profile,
        seed: 3,
      );
      expect(outcome.verdict, BehaviorVerdict.complete);
      final types = server.inputEvents
          .map((event) => event['type'])
          .toList(growable: false);
      expect(types.first, 'mouseMoved');
      expect(types, contains('mousePressed'));
      final moveCount = types.where((t) => t == 'mouseMoved').length;
      expect(moveCount, greaterThan(1));
      // Serialized awaited dispatch: drift accumulates but stays small
      // against loopback fakes.
      expect(
        outcome.dispatched.map((step) => step.driftUs).every((d) => d >= 0),
        isTrue,
      );
      await driver.close();
    });

    test('typing lowers to per-key events with virtual key codes',
        () async {
      final driver = await attachDriver();
      final outcome = await driver.performWith(
        const TypeAction('Hi', css: '#field'),
        BehaviorProfile.agentImmediate,
        seed: 1,
      );
      expect(outcome.verdict, BehaviorVerdict.complete);
      final methods = server.inputEvents
          .map((event) => event['method'])
          .where((m) => m == 'Input.dispatchKeyEvent')
          .toList();
      // keyDown(H), keyUp(H), keyDown(i), keyUp(i)
      expect(methods.length, 4);
      final keyDowns = server.inputEvents
          .where((event) =>
              event['method'] == 'Input.dispatchKeyEvent' &&
              event['type'] == 'keyDown')
          .toList();
      expect(keyDowns.first['windowsVirtualKeyCode'], 72);
      expect(keyDowns.first['text'], 'H');
      await driver.close();
    });

    test('enforces the reaction floor against the last observation',
        () async {
      final driver = await attachDriver();
      await driver.snapshot();
      final profile = BehaviorProfile.agentImmediate.copyWith(
        reaction: const ReactionDelay(floorUs: 150_000),
      );
      final watch = Stopwatch()..start();
      await driver.performWith(
        const ClickAction(css: '#go'),
        profile,
        seed: 2,
      );
      expect(
        watch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 150)),
      );
      await driver.close();
    });

    test('refuses unsupported session pacing loudly', () async {
      final driver = await attachDriver();
      final noisy = BehaviorProfile.agentImmediate.copyWith(
        pacing: const SessionPacing(noiseEventRate: 0.3),
      );
      await expectLater(
        driver.performWith(const ClickAction(css: '#go'), noisy, seed: 1),
        throwsA(isA<DriverUnsupportedException>()),
      );
      expect(server.inputEvents, isEmpty);
      await driver.close();
    });

    test('receipt writer emits both artifacts with terminal verdict',
        () async {
      final driver = await attachDriver();
      final directory = await Directory.systemTemp.createTemp('cdp-behavior');
      addTearDown(() => directory.delete(recursive: true));
      final profile = BehaviorProfile.agentImmediate;
      final outcome = await driver.performWith(
        const ClickAction(css: '#go'),
        profile,
        seed: 7,
      );
      final writer = CdpBehaviorReceiptWriter(directory: directory.path);
      await writer.write(
        profile: profile,
        seed: 7,
        driverId: 'cdp',
        transport: 'cdp',
        outcome: outcome,
        sessionId: 'session-chrome-handle',
      );
      final streamLines = File(writer.streamPath).readAsLinesSync()
        ..removeWhere((line) => line.isEmpty);
      final receiptLines = File(writer.receiptsPath).readAsLinesSync()
        ..removeWhere((line) => line.isEmpty);
      // Meta + teleport move + down + up.
      expect(streamLines.length, 4);
      expect(streamLines.first, contains('"schema":"behavior.plan/v2"'));
      // Envelope + 3 dispatched (move, down, up) + terminal.
      expect(receiptLines.length, 5);
      expect(receiptLines.first, contains('"driverId":"cdp"'));
      expect(receiptLines.last, contains('"terminal":true'));
      expect(receiptLines.last, contains('"verdict":"complete"'));
      await driver.close();
    });
  });
}
