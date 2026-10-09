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
  BridgeBytesResult windowScreenshotResult = (
    code: 0,
    bytes: Uint8List.fromList([4, 5]),
  );
  BridgeJsonResult windowsResult = (code: 0, json: _windowsJson);
  int? lastWindowId;
  int? lastWindowMaxPx;

  double? lastScrollDx;
  double? lastScrollDy;
  String? lastTypedText;
  final pressedHandles = <int>[];

  /// Structured record of every pointer event the bridge saw, in order.
  final pointerEvents = <Map<String, Object?>>[];
  int pointerResult = 0;
  int keyResult = 0;

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
  int pointerMove({
    required double x,
    required double y,
    Iterable<String> modifiers = const [],
  }) {
    calls.add('pointerMove($x,$y)');
    pointerEvents.add({
      'kind': 'move',
      'x': x,
      'y': y,
      if (modifiers.isNotEmpty) 'modifiers': modifiers.toList(),
    });
    return pointerResult;
  }

  @override
  int pointerButton({
    required double x,
    required double y,
    required String button,
    required bool down,
    int clickCount = 1,
    Iterable<String> modifiers = const [],
  }) {
    calls.add(
      'pointerButton($x,$y,$button,${down ? 'down' : 'up'},$clickCount)',
    );
    pointerEvents.add({
      'kind': down ? 'down' : 'up',
      'x': x,
      'y': y,
      'button': button,
      'clickCount': clickCount,
      if (modifiers.isNotEmpty) 'modifiers': modifiers.toList(),
    });
    return pointerResult;
  }

  @override
  int keyDown(String key) {
    calls.add('keyDown($key)');
    return keyResult;
  }

  @override
  int keyUp(String key) {
    calls.add('keyUp($key)');
    return keyResult;
  }

  @override
  void releaseAll() => calls.add('releaseAll');

  @override
  BridgeBytesResult screenshotPng({int displayId = 0, int maxPx = 0}) {
    calls.add('screenshot($displayId)');
    return screenshotResult;
  }

  @override
  BridgeBytesResult screenshotWindowPng({
    required int windowId,
    int maxPx = 0,
  }) {
    calls.add('windowScreenshot($windowId)');
    lastWindowId = windowId;
    lastWindowMaxPx = maxPx;
    return windowScreenshotResult;
  }

  @override
  BridgeJsonResult windowsJson({int pid = 0}) {
    calls.add('windows(pid=$pid)');
    return windowsResult;
  }

  // -- app management (scripted results + call log) --

  BridgeJsonResult appsResult = (code: 0, json: _appsJson);
  BridgeJsonResult frontmostResult = (code: 0, json: _safariJson);
  BridgeJsonResult snapshotAppResult = (code: 0, json: _appJson);
  int activateResult = 0;
  int launchResult = 4242;
  int terminateResult = 0;
  String? lastLaunchedBundleId;
  int? lastActivatedPid;
  int? lastTerminatedPid;
  int? lastSnapshotPid;

  @override
  BridgeJsonResult appsJson() {
    calls.add('apps');
    return appsResult;
  }

  @override
  BridgeJsonResult frontmostJson() {
    calls.add('frontmost');
    return frontmostResult;
  }

  @override
  BridgeJsonResult snapshotAppJson({
    required int maxDepth,
    required int maxNodes,
    required int pid,
  }) {
    calls.add('snapshotApp(pid=$pid)');
    lastSnapshotPid = pid;
    return snapshotAppResult;
  }

  @override
  int activateApp(int pid) {
    calls.add('activate($pid)');
    lastActivatedPid = pid;
    return activateResult;
  }

  @override
  int launchApp(String bundleId) {
    calls.add('launch($bundleId)');
    lastLaunchedBundleId = bundleId;
    return launchResult;
  }

  @override
  int terminateApp(int pid) {
    calls.add('terminate($pid)');
    lastTerminatedPid = pid;
    return terminateResult;
  }
}

const _buttonJson =
    '{"role":"button","name":"Save","attributes":{"axid":"0"},'
    '"bounds":{"left":10,"top":20,"width":80,"height":24}}';

const _windowsJson =
    '[{"windowId":77,"pid":42,"name":"Downloads",'
    '"bounds":{"left":10,"top":20,"width":800,"height":600}},'
    '{"windowId":88,"pid":42,"name":""}]';

const _appsJson =
    '[{"pid":42,"bundleId":"com.appleFinder","name":"Finder",'
    '"active":true,"hidden":false},'
    '{"pid":4242,"name":"Terminal","active":false,"hidden":false}]';

const _safariJson =
    '{"pid":1234,"bundleId":"com.apple.Safari","name":"Safari",'
    '"active":true,"hidden":false}';

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
    expect(driver.capabilities.pointerCoordinates, isTrue);
  });

  test('clickAt moves, then presses with escalating click state', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    await driver.perform(const ClickAtAction(120, 80));
    expect(bridge.pointerEvents.map((event) => event['kind']).toList(), [
      'move',
      'down',
      'up',
    ]);
    expect(bridge.pointerEvents[1]['x'], 120);
    expect(bridge.pointerEvents[1]['y'], 80);
    expect(bridge.pointerEvents[1]['clickCount'], 1);

    bridge.pointerEvents.clear();
    await driver.perform(const ClickAtAction(5, 6, clickCount: 2));
    final presses = bridge.pointerEvents
        .where((event) => event['kind'] == 'down')
        .toList();
    expect(presses.map((event) => event['clickCount']).toList(), [1, 2]);
  });

  test('clickAt preserves the button axis', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    await driver.perform(const ClickAtAction(1, 2, button: 'right'));
    expect(bridge.pointerEvents[1]['button'], 'right');
    expect(bridge.pointerEvents[2]['button'], 'right');
  });

  test('moveTo posts a single move', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    await driver.perform(const MoveAction(30, 40));
    expect(bridge.pointerEvents, [
      {'kind': 'move', 'x': 30.0, 'y': 40.0},
    ]);
  });

  test('drag presses at the from-point and releases at the to-point',
      () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    await driver.perform(const DragAction(10, 20, 300, 400));
    expect(bridge.pointerEvents.map((event) => event['kind']).toList(), [
      'move',
      'down',
      'move',
      'up',
    ]);
    expect(bridge.pointerEvents[1]['x'], 10);
    expect(bridge.pointerEvents[1]['y'], 20);
    expect(bridge.pointerEvents[3]['x'], 300);
    expect(bridge.pointerEvents[3]['y'], 400);
  });

  test('coordinate verbs surface the typed permission exception', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    // The real bridge returns 10 when the Accessibility grant is absent.
    bridge.pointerResult = 10;
    await expectLater(
      driver.perform(const MoveAction(1, 2)),
      throwsA(isA<AccessibilityPermissionRequiredException>()),
    );
  });

  test('unknown button names are refused loudly', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    bridge.pointerResult = 1;
    await expectLater(
      driver.perform(const ClickAtAction(1, 2, button: 'pen')),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test('shift+click holds the chord key around flagged presses', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    await driver.perform(const ClickAtAction(1, 2, modifiers: ['shift']));

    expect(bridge.calls.where((call) => call.startsWith('key')), [
      'keyDown(Shift)',
      'keyUp(Shift)',
    ]);
    final press = bridge.pointerEvents
        .firstWhere((event) => event['kind'] == 'down');
    expect(press['modifiers'], ['shift']);
  });

  test('meta+drag holds the chord through press, carry, and release',
      () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    await driver.perform(const DragAction(0, 0, 40, 40, modifiers: ['meta']));

    expect(bridge.calls.where((call) => call.startsWith('key')), [
      'keyDown(Meta)',
      'keyUp(Meta)',
    ]);
    for (final event in bridge.pointerEvents.skip(1)) {
      expect(event['modifiers'], ['meta'], reason: '${event['kind']} carries');
    }
  });

  test('app management: discover/activate/launch/terminate/snapshot',
      () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    final apps = await driver.runningApps();
    expect(apps, hasLength(2));
    expect(apps.first.bundleId, 'com.appleFinder');
    expect(apps.first.active, isTrue);
    expect(apps[1].pid, 4242);

    await driver.activate(4242);
    expect(bridge.lastActivatedPid, 4242);

    final pid = await driver.launch('com.apple.Safari');
    expect(pid, 4242);
    expect(bridge.lastLaunchedBundleId, 'com.apple.Safari');

    await driver.terminate(4242);
    expect(bridge.lastTerminatedPid, 4242);

    final snapshot = await driver.snapshotOfApp(42);
    expect(snapshot.roots.first.name, 'Finder');
    expect(bridge.lastSnapshotPid, 42);
  });

  test('app management errors map to the family exceptions', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    bridge
      ..activateResult = 7
      ..terminateResult = 8
      ..launchResult = -7
      ..snapshotAppResult = (code: 7, json: '');

    await expectLater(
      driver.activate(99),
      throwsA(isA<ElementNotFoundException>()),
    );
    await expectLater(
      driver.terminate(99),
      throwsA(isA<ProtocolException>()),
    );
    await expectLater(
      driver.launch('no.such.App'),
      throwsA(isA<ElementNotFoundException>()),
    );
    await expectLater(
      driver.snapshotOfApp(99),
      throwsA(isA<ElementNotFoundException>()),
    );
  });

  test('frontmost parses the bridge record', () async {
    final driver = driverWith(FakeBridge());
    final app = await driver.frontmost();
    expect(app.pid, 1234);
    expect(app.bundleId, 'com.apple.Safari');
    expect(app.name, 'Safari');
    expect(app.active, isTrue);
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

  test('screenshot returns bytes; missing consent is typed', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    expect(await driver.screenshot(), [1, 2, 3]);

    bridge.screenshotResult = (code: 10, bytes: Uint8List(0));
    await expectLater(
      driver.screenshot(),
      throwsA(isA<ScreenRecordingPermissionRequiredException>()),
    );
  });

  test('window discovery and window-scoped capture', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);

    final windows = await driver.windows(pid: 42);
    expect(bridge.calls, contains('windows(pid=42)'));
    expect(windows, hasLength(2));
    expect(windows.first.windowId, 77);
    expect(windows.first.name, 'Downloads');
    expect(windows.first.bounds!.width, 800);
    expect(windows.last.name, '');

    final bytes = await driver.windowScreenshot(77, maxPx: 1024);
    expect(bytes, [4, 5]);
    expect(bridge.lastWindowId, 77);
    expect(bridge.lastWindowMaxPx, 1024);

    bridge.windowScreenshotResult = (
      code: 10,
      bytes: Uint8List(0),
    );
    await expectLater(
      driver.windowScreenshot(77),
      throwsA(isA<ScreenRecordingPermissionRequiredException>()),
    );
    bridge.windowScreenshotResult = (code: 2, bytes: Uint8List(0));
    await expectLater(
      driver.windowScreenshot(999),
      throwsA(isA<ElementNotFoundException>()),
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
