import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';
import 'package:universal_browser_cdp/universal_browser_cdp_testing.dart';

/// The ADR 0053 coordinate verbs over the CDP tier: plain dispatch and
/// the MoE lowering both land at the asked-for viewport coordinates.
void main() {
  late FakeCdpServer server;

  setUp(() async {
    server = FakeCdpServer();
    await server.start();
  });
  tearDown(() => server.stop());

  test('the CDP driver advertises pointerCoordinates', () async {
    final session = await CdpBrowserSession.attach(server.httpBase);
    expect(session.driver.capabilities.pointerCoordinates, isTrue);
    await session.detach();
  });

  test('clickAt dispatches move + press + release at the coordinates',
      () async {
    final session = await CdpBrowserSession.attach(server.httpBase);
    await session.driver.perform(const ClickAtAction(120, 80));
    final events = server.inputEvents
        .map((event) => event['type'] as String)
        .toList();
    expect(events, ['mouseMoved', 'mousePressed', 'mouseReleased']);
    expect(server.inputEvents[1]['x'], 120);
    expect(server.inputEvents[1]['y'], 80);
    expect(server.inputEvents[1]['clickCount'], 1);
    await session.detach();
  });

  test('double clickAt escalates clickCount per press', () async {
    final session = await CdpBrowserSession.attach(server.httpBase);
    await session.driver.perform(
      const ClickAtAction(30, 40, clickCount: 2),
    );
    final presses = server.inputEvents
        .where((event) => event['type'] == 'mousePressed')
        .toList();
    expect(presses.map((event) => event['clickCount']).toList(), [1, 2]);
    await session.detach();
  });

  test('drag presses at the from-point and releases at the to-point',
      () async {
    final session = await CdpBrowserSession.attach(server.httpBase);
    await session.driver.perform(const DragAction(10, 20, 300, 400));
    final pressed = server.inputEvents
        .firstWhere((event) => event['type'] == 'mousePressed');
    final released = server.inputEvents
        .firstWhere((event) => event['type'] == 'mouseReleased');
    expect(pressed['x'], 10);
    expect(pressed['y'], 20);
    expect(released['x'], 300);
    expect(released['y'], 400);
    await session.detach();
  });

  test('behavioral lowering routes the whole path through the plan',
      () async {
    final session = await CdpBrowserSession.attach(server.httpBase);
    final behavioral = BehavioralCdpDriver(session.page);
    final outcome = await behavioral.performWith(
      const DragAction(10, 20, 300, 400),
      BehaviorProfile.humanPrior(7),
      seed: 7,
    );
    expect(outcome.verdict, BehaviorVerdict.complete);
    final events = server.inputEvents
        .map((event) => event['type'] as String)
        .toList();
    // Press once near the from-point, animated moves while carried,
    // release at the end.
    expect(events.first, 'mouseMoved');
    expect(events.where((type) => type == 'mousePressed').length, 1);
    expect(events.last, 'mouseReleased');
    final movedXs = server.inputEvents
        .where((event) => event['type'] == 'mouseMoved')
        .map((event) => (event['x'] as num).toDouble())
        .toList();
    // Bezier approach departs near the from-point; the release lands on
    // the to-point.
    expect(movedXs.first, closeTo(10, 30));
    final released = server.inputEvents.lastWhere(
      (event) => event['type'] == 'mouseReleased',
    );
    expect(released['x'], 300);
    expect(released['y'], 400);
    await session.detach();
  });

  test('shift+click sets the CDP modifier mask on every pointer event',
      () async {
    final session = await CdpBrowserSession.attach(server.httpBase);
    await session.driver.perform(
      const ClickAtAction(120, 80, modifiers: ['shift']),
    );
    for (final event in server.inputEvents) {
      expect(event['modifiers'], 8, reason: '${event['type']} carries shift');
    }
    await session.detach();
  });

  test('behavioral chords dispatch key steps and flagged presses', () async {
    final session = await CdpBrowserSession.attach(server.httpBase);
    final behavioral = BehavioralCdpDriver(session.page);
    final outcome = await behavioral.performWith(
      const ClickAtAction(5, 6, modifiers: ['shift', 'control']),
      BehaviorProfile.agentImmediate,
      seed: 7,
    );
    expect(outcome.verdict, BehaviorVerdict.complete);
    // The chord rides both channels: key steps for the transport-less
    // representation, the mask field for the pointer events.
    final keys = server.inputEvents
        .where((event) => event['method'] == 'Input.dispatchKeyEvent')
        .map((event) => '${event['type']}:${event['key']}')
        .toList();
    expect(keys, [
      'keyDown:Shift',
      'keyDown:Control',
      'keyUp:Control',
      'keyUp:Shift',
    ]);
    final pressed = server.inputEvents
        .firstWhere((event) => event['type'] == 'mousePressed');
    // shift 8 | control 2.
    expect(pressed['modifiers'], 10);
    await session.detach();
  });
}
