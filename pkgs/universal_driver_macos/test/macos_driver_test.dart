import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

/// Records every bridge call and replays scripted observations — the
/// FakeBus pattern from `universal_driver_linux`.
final class FakeBridge implements AxDriverBridge {
  FakeBridge({this.trusted = true});

  bool trusted;
  final calls = <String>[];
  BridgeJsonResult snapshotResult = (code: 0, json: _appJson);
  BridgeJsonResult elementResult = (code: 0, json: _buttonJson);

  /// Queued press results (0 when empty); lets tests script one-shot
  /// staleness.
  final pressResults = <int>[];
  int typeTextResult = 0;
  final keyPressResults = <String, int>{};
  int scrollResult = 0;
  BridgeBytesResult screenshotResult = (
    code: 0,
    bytes: Uint8List.fromList([1, 2, 3]),
  );

  double? lastScrollDx;
  double? lastScrollDy;
  String? lastTypedText;
  final pressedHandles = <int>[];

  @override
  String version() {
    calls.add('version');
    return 'xs-ax-driver/1';
  }

  @override
  bool axTrusted() {
    calls.add('axTrusted');
    return trusted;
  }

  @override
  bool requestTrust() {
    calls.add('requestTrust');
    return trusted;
  }

  @override
  BridgeJsonResult snapshotJson({
    required int maxDepth,
    required int maxNodes,
  }) {
    calls.add('snapshot(depth=$maxDepth,nodes=$maxNodes)');
    return snapshotResult;
  }

  @override
  BridgeJsonResult elementAtPositionJson({
    required double x,
    required double y,
  }) {
    calls.add('elementAt($x,$y)');
    return elementResult;
  }

  @override
  int press(int handle) {
    calls.add('press($handle)');
    pressedHandles.add(handle);
    return pressResults.isEmpty ? 0 : pressResults.removeAt(0);
  }

  @override
  int focus(int handle) {
    calls.add('focus($handle)');
    return 0;
  }

  @override
  int typeText(String text) {
    calls.add('typeText');
    lastTypedText = text;
    return typeTextResult;
  }

  @override
  int keyPress(String key) {
    calls.add('keyPress($key)');
    return keyPressResults[key] ?? 0;
  }

  @override
  int scroll(double dx, double dy) {
    calls.add('scroll($dx,$dy)');
    lastScrollDx = dx;
    lastScrollDy = dy;
    return scrollResult;
  }

  @override
  void releaseAll() => calls.add('releaseAll');

  @override
  BridgeBytesResult screenshotPng({int displayId = 0}) {
    calls.add('screenshot($displayId)');
    return screenshotResult;
  }
}

const _buttonJson =
    '{"role":"button","name":"Save","attributes":{"axid":"0"},'
    '"bounds":{"left":10,"top":20,"width":80,"height":24}}';

const _appJson =
    '{"role":"application","name":"Finder","attributes":{"axid":"0"},'
    '"children":['
    '{"role":"window","name":"Downloads","attributes":{"axid":"1"},"children":['
    '{"role":"button","name":"Save","attributes":{"axid":"2"}},'
    '{"role":"textbox","name":"Search","value":"","attributes":{"axid":"3"}}'
    ']}]}';

MacosDriver driverWith(FakeBridge bridge) => MacosDriver(bridge: bridge);

void main() {
  test('capabilities declare a11y tree, input synthesis, and screenshots', () {
    final driver = driverWith(FakeBridge());
    expect(driver.capabilities.a11yTree, isTrue);
    expect(driver.capabilities.inputSynthesis, isTrue);
    expect(driver.capabilities.screenshot, isTrue);
    expect(driver.capabilities.evaluate, isFalse);
  });

  test('snapshot parses the bridge JSON into the family model', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    final snapshot = await driver.snapshot();

    expect(snapshot.roots, hasLength(1));
    expect(snapshot.roots.first.role, 'application');
    expect(snapshot.roots.first.name, 'Finder');
    final button = snapshot.nodes.firstWhere((node) => node.role == 'button');
    expect(button.name, 'Save');
    expect(button.attributes['axid'], '2');
    expect(bridge.calls.first, 'axTrusted');
    expect(bridge.calls[1], 'snapshot(depth=12,nodes=600)');
    expect(snapshot.revision, 1);
    final second = await driver.snapshot();
    expect(second.revision, 2, reason: 'revision bumps per snapshot');
  });

  test('click by name resolves the cached handle and presses', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    await driver.snapshot();
    bridge.calls.clear();

    await driver.perform(const ClickAction(name: 'Save'));

    expect(bridge.pressedHandles, [2]);
    expect(bridge.calls, contains('press(2)'));
  });

  test('click by role+name resolves the first match', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    await driver.snapshot();

    await driver.perform(const ClickAction(role: 'textbox', name: 'Search'));

    expect(bridge.pressedHandles, [3]);
  });

  test('click with a css locator is refused loudly', () async {
    final driver = driverWith(FakeBridge());
    await expectLater(
      driver.perform(const ClickAction(css: '#save')),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test('missing element throws ElementNotFoundException', () async {
    final driver = driverWith(FakeBridge());
    await driver.snapshot();
    await expectLater(
      driver.perform(const ClickAction(name: 'Missing')),
      throwsA(
        isA<ElementNotFoundException>().having(
          (error) => error.locatorValue,
          'locatorValue',
          'Missing',
        ),
      ),
    );
  });

  test('stale handle triggers one re-observe and retry', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    await driver.snapshot();
    bridge
      ..pressResults.addAll([5, 0])
      ..calls.clear();

    await driver.perform(const ClickAction(name: 'Save'));

    expect(
      bridge.calls.where((call) => call.startsWith('snapshot')),
      hasLength(1),
    );
    expect(bridge.pressedHandles, hasLength(2));
  });

  test('type sends text; submit appends Enter', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    await driver.perform(const TypeAction('hello'));
    expect(bridge.lastTypedText, 'hello');

    await driver.perform(const TypeAction('go', submit: true));
    expect(bridge.calls, contains('keyPress(Enter)'));

    await expectLater(
      driver.perform(const TypeAction('x', css: '#field')),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test('unmapped keys are refused, mapped keys dispatch', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    await driver.perform(const KeyPressAction('Escape'));
    expect(bridge.calls, contains('keyPress(Escape)'));

    bridge.keyPressResults['F13'] = 1;
    await expectLater(
      driver.perform(const KeyPressAction('F13')),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test('scroll maps direction to signed line deltas', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    await driver.perform(const ScrollAction(direction: 'up'));
    expect(bridge.lastScrollDy, 3.0);

    await driver.perform(const ScrollAction(distance: 100));
    expect(bridge.lastScrollDy, -10.0);

    await driver.perform(const ScrollAction(direction: 'left', distance: 50));
    expect(bridge.lastScrollDx, -5.0);

    await expectLater(
      driver.perform(const ScrollAction(direction: 'sideways')),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test('navigate and evaluate are refused (no AX equivalent)', () async {
    final driver = driverWith(FakeBridge());
    await expectLater(
      driver.perform(NavigateAction(Uri.parse('https://example.com'))),
      throwsA(isA<DriverUnsupportedException>()),
    );
    await expectLater(
      driver.perform(const EvaluateAction('1 + 1')),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test('elementAtPosition hit-tests through the bridge', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    final node = await driver.elementAtPosition(120, 240);

    expect(bridge.calls, contains('elementAt(120.0,240.0)'));
    expect(node.role, 'button');
    expect(node.name, 'Save');
  });

  test(
    'untrusted accessibility raises the typed permission exception',
    () async {
      final bridge = FakeBridge(trusted: false);
      final driver = driverWith(bridge);
      await expectLater(
        driver.snapshot(),
        throwsA(isA<AccessibilityPermissionRequiredException>()),
      );
      await expectLater(
        driver.elementAtPosition(0, 0),
        throwsA(isA<AccessibilityPermissionRequiredException>()),
      );
    },
  );

  test(
    'bridge error codes surface as protocol or not-found exceptions',
    () async {
      final bridge = FakeBridge();
      final driver = driverWith(bridge);
      bridge.snapshotResult = (code: 2, json: '');
      await expectLater(
        driver.snapshot(),
        throwsA(isA<ElementNotFoundException>()),
      );
      bridge.snapshotResult = (code: 3, json: '');
      await expectLater(driver.snapshot(), throwsA(isA<ProtocolException>()));
      bridge.elementResult = (code: 4, json: '');
      await expectLater(
        driver.elementAtPosition(1, 1),
        throwsA(isA<ElementNotFoundException>()),
      );
    },
  );

  test('close releases the native state and poisons every method', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    await driver.close();
    await driver.close(); // idempotent

    expect(bridge.calls, contains('releaseAll'));
    expect(() => driver.axTrusted, throwsStateError);
    await expectLater(driver.snapshot(), throwsStateError);
    await expectLater(driver.screenshot(), throwsStateError);
    await expectLater(
      driver.perform(const KeyPressAction('Tab')),
      throwsStateError,
    );
  });

  test('screenshot returns bytes; missing permission is typed', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    expect(await driver.screenshot(), [1, 2, 3]);

    bridge.screenshotResult = (code: 10, bytes: Uint8List(0));
    await expectLater(
      driver.screenshot(),
      throwsA(isA<AccessibilityPermissionRequiredException>()),
    );
  });

  test('snapshot json payload is round-trippable through the model', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    final snapshot = await driver.snapshot();
    final restored = Snapshot.fromJson(snapshot.toJson());
    expect(
      restored.nodes.map((node) => node.name),
      snapshot.nodes.map((node) => node.name),
    );
    expect(jsonEncode(snapshot.toJson()), contains('Finder'));
  });
}
