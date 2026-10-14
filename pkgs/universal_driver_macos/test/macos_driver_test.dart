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

  // -- semantic writes (ADR 0064) --
  final setValues = <(int, String)>[];

  /// Queued results (0 when empty); lets tests script one-shot staleness.
  final setValueResults = <int>[];
  final elementActionCalls = <(int, String)>[];
  final elementActionResultQueue = <int>[];

  // -- pid-scoped event delivery (ADR 0064 rung) --
  final pidTypedText = <({int pid, String text})>[];

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
  int setValue(int handle, String value) {
    calls.add('setValue($handle)');
    setValues.add((handle, value));
    return setValueResults.isEmpty ? 0 : setValueResults.removeAt(0);
  }

  @override
  int performElementAction(int handle, String action) {
    calls.add('elementAction($handle,$action)');
    elementActionCalls.add((handle, action));
    return elementActionResultQueue.isEmpty
        ? 0
        : elementActionResultQueue.removeAt(0);
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
  int typeTextToPid(int pid, String text) {
    calls.add('typeTextToPid($pid)');
    pidTypedText.add((pid: pid, text: text));
    return 0;
  }

  @override
  int keyPressToPid(int pid, String key) {
    calls.add('keyPressToPid($pid,$key)');
    return 0;
  }

  @override
  int keyDownToPid(int pid, String key) {
    calls.add('keyDownToPid($pid,$key)');
    return 0;
  }

  @override
  int keyUpToPid(int pid, String key) {
    calls.add('keyUpToPid($pid,$key)');
    return 0;
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

const _finderJson =
    '{"pid":42,"bundleId":"com.appleFinder","name":"Finder",'
    '"active":false,"hidden":false}';

const _appJson =
    '{"role":"application","name":"Finder","attributes":{"axid":"0"},'
    '"children":['
    '{"role":"window","name":"Downloads","attributes":{"axid":"1"},"children":['
    '{"role":"button","name":"Save","attributes":{"axid":"2"}},'
    '{"role":"textbox","name":"Search","value":"","attributes":{"axid":"3"}}'
    ']}]}';

/// Root carries the observed pid (the bridge stamps it) — the focus
/// contract's reference point for focused sessions.
const _appJsonWithPid =
    '{"role":"application","name":"Finder",'
    '"attributes":{"axid":"0","pid":"42"},'
    '"children":['
    '{"role":"button","name":"Save","attributes":{"axid":"2"}},'
    '{"role":"textbox","name":"Search","value":"","attributes":{"axid":"3"}}'
    ']}';

final class AllWindowsFakeBridge extends FakeBridge
    implements AllWindowListingBridge {
  @override
  BridgeJsonResult allWindowsJson({int pid = 0}) {
    calls.add('allWindows(pid=$pid)');
    return windowsResult;
  }
}

MacosDriver driverWith(FakeBridge bridge) => MacosDriver(bridge: bridge);

void main() {
  test('capabilities declare a11y tree, input synthesis, and screenshots', () {
    final driver = driverWith(FakeBridge());
    expect(driver.capabilities.a11yTree, isTrue);
    expect(driver.capabilities.inputSynthesis, isTrue);
    expect(driver.capabilities.screenshot, isTrue);
    expect(driver.capabilities.evaluate, isFalse);
    expect(driver.capabilities.pointerCoordinates, isTrue);
    expect(driver.capabilities.semanticWrite, isTrue);
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

  test('drag presses at the from-point and releases at the to-point', () async {
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
    final press = bridge.pointerEvents.firstWhere(
      (event) => event['kind'] == 'down',
    );
    expect(press['modifiers'], ['shift']);
  });

  test('meta+drag holds the chord through press, carry, and release', () async {
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

  test('app management: discover/activate/launch/terminate/snapshot', () async {
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
    await expectLater(driver.terminate(99), throwsA(isA<ProtocolException>()));
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

  test('click by role+name resolves a unique match', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    await driver.snapshot();

    await driver.perform(const ClickAction(role: 'textbox', name: 'Search'));

    expect(bridge.pressedHandles, [3]);
  });

  for (final action in const <AutomationAction>[
    ClickAction(role: 'button', name: 'Save'),
    SetValueAction('x', role: 'button', name: 'Save'),
    ElementAction('AXPress', role: 'button', name: 'Save'),
  ]) {
    test(
      'ambiguous ${action.runtimeType} refuses before native mutation',
      () async {
        final tree = jsonDecode(_appJson) as Map<String, dynamic>;
        final window = (tree['children'] as List).single as Map;
        (window['children'] as List).add({
          'role': 'button',
          'name': 'Save',
          'attributes': {'axid': '4'},
        });
        final bridge = FakeBridge()
          ..snapshotResult = (code: 0, json: jsonEncode(tree));
        final driver = driverWith(bridge);
        await driver.snapshot();
        await expectLater(
          driver.perform(action),
          throwsA(
            isA<ProtocolException>().having(
              (e) => e.details['matches'],
              'matches',
              2,
            ),
          ),
        );
        expect(bridge.pressedHandles, isEmpty);
        expect(bridge.setValues, isEmpty);
        expect(bridge.elementActionCalls, isEmpty);
      },
    );
  }

  test('stale click cannot retry into an ambiguous replacement tree', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    await driver.snapshot();
    final tree = jsonDecode(_appJson) as Map<String, dynamic>;
    final window = (tree['children'] as List).single as Map;
    (window['children'] as List).add({
      'role': 'button',
      'name': 'Save',
      'attributes': {'axid': '4'},
    });
    bridge.snapshotResult = (code: 0, json: jsonEncode(tree));
    bridge.pressResults.add(5);
    await expectLater(
      driver.perform(const ClickAction(name: 'Save')),
      throwsA(isA<ProtocolException>()),
    );
    expect(bridge.pressedHandles, [
      2,
    ], reason: 'Only stale first handle attempted');
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

    bridge.windowScreenshotResult = (code: 10, bytes: Uint8List(0));
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

  test(
    'offscreen listing preserves visibility states',
    () async {
      final bridge = AllWindowsFakeBridge()
        ..windowsResult = (
          code: 0,
          json:
              '[{"windowId":77,"pid":42,"name":"host","onScreen":true},'
              '{"windowId":78,"pid":42,"name":"helper","onScreen":false},'
              '{"windowId":79,"pid":42,"name":"unknown"}]',
        );
      final driver = driverWith(bridge);
      final windows = await driver.windows(pid: 42, onScreenOnly: false);
      expect(bridge.calls, ['allWindows(pid=42)']);
      expect(windows.map((window) => window.onScreen), [true, false, null]);
      expect(windows.last.toJson().containsKey('onScreen'), isFalse);
      expect(windows[1].toJson()['onScreen'], isFalse);
      bridge.windowsResult = (code: 3, json: '');
      await expectLater(
        driver.windows(onScreenOnly: false),
        throwsA(isA<ProtocolException>()),
      );
    },
  );

  test(
    'legacy custom bridge refuses offscreen listing before a bridge call',
    () async {
      final bridge = FakeBridge();
      final driver = driverWith(bridge);
      await expectLater(
        driver.windows(pid: 42, onScreenOnly: false),
        throwsA(isA<DriverUnsupportedException>()),
      );
      expect(bridge.calls, isEmpty);
      await driver.windows(pid: 42);
      expect(bridge.calls, ['windows(pid=42)']);
    },
  );

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

  // -- ADR 0064: the semantic write path and the focus contract --

  test('setValue resolves the handle and writes in background', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    await driver.snapshot();
    bridge.calls.clear();

    await driver.perform(const SetValueAction('hello', name: 'Search'));

    expect(bridge.setValues, [(3, 'hello')]);
    // Semantic verbs never consult the event stream's owner.
    expect(bridge.calls.where((call) => call == 'frontmost'), isEmpty);
  });

  test('setValue with a css locator is refused loudly', () async {
    final driver = driverWith(FakeBridge());
    await expectLater(
      driver.perform(const SetValueAction('x', css: '#field')),
      throwsA(isA<DriverUnsupportedException>()),
    );
  });

  test(
    'setValue host refusal (not settable) is a clear protocol failure',
    () async {
      final bridge = FakeBridge();
      final driver = driverWith(bridge);
      await driver.snapshot();
      bridge.setValueResults.add(3);
      await expectLater(
        driver.perform(const SetValueAction('x', name: 'Search')),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.message,
            'message',
            contains('not settable'),
          ),
        ),
      );
    },
  );

  test('stale setValue handle re-observes once and retries', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    await driver.snapshot();
    bridge
      ..setValueResults.addAll([5, 0]) // first write hits a stale handle
      ..calls.clear();

    await driver.perform(const SetValueAction('fresh', name: 'Search'));

    expect(bridge.setValues, [
      (3, 'fresh'),
      (3, 'fresh'),
    ], reason: 'stale write then the retried write on the fresh handle');
    expect(
      bridge.calls.where((call) => call.startsWith('snapshot')),
      hasLength(1),
    );
  });

  test('elementAction performs the advertised action by name', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    await driver.snapshot();

    await driver.perform(const ElementAction('AXConfirm', name: 'Save'));

    expect(bridge.elementActionCalls, [(2, 'AXConfirm')]);
  });

  test('unadvertised element actions surface the host refusal', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    await driver.snapshot();
    bridge.elementActionResultQueue.add(3);
    await expectLater(
      driver.perform(const ElementAction('AXPick', name: 'Save')),
      throwsA(isA<ProtocolException>()),
    );
  });

  test(
    'anchored driver observes the anchored pid, not the focused one',
    () async {
      final bridge = FakeBridge();
      final driver = MacosDriver(bridge: bridge, targetPid: 42);

      final snapshot = await driver.snapshot();

      expect(bridge.lastSnapshotPid, 42);
      expect(
        bridge.calls,
        isNot(contains('snapshot(depth=12,nodes=600)')),
        reason: 'anchored sessions skip the focused-app walk',
      );
      expect(snapshot.roots.first.name, 'Finder');
    },
  );

  test(
    'focus contract: global verb on a background anchor is refused',
    () async {
      final bridge = FakeBridge();
      final driver = driverWith(bridge);
      // Observe Finder (root pid 42), then the user switches to Safari.
      bridge
        ..snapshotResult = (code: 0, json: _appJsonWithPid)
        ..frontmostResult = (code: 0, json: _safariJson)
        ..calls.clear();
      await driver.snapshot();

      await expectLater(
        driver.perform(const TypeAction('hello')),
        throwsA(
          isA<ForegroundRequiredException>()
              .having((error) => error.targetPid, 'targetPid', 42)
              .having((error) => error.frontmostPid, 'frontmostPid', 1234)
              .having((error) => error.kind, 'kind', 'foregroundRequired'),
        ),
      );
      expect(
        bridge.lastTypedText,
        isNull,
        reason: 'the refusal precedes any event synthesis',
      );
    },
  );

  test('focus contract: matching frontmost passes; no snapshot adopts '
      'the frontmost app', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    bridge.snapshotResult = (code: 0, json: _appJsonWithPid);
    await driver.snapshot();

    // Frontmost is Safari (1234) but the observation says pid 42.
    bridge.frontmostResult = (code: 0, json: _finderJson);
    await driver.perform(const TypeAction('ok'));
    expect(bridge.lastTypedText, 'ok');

    // A fresh session with no observation: the frontmost app at dispatch
    // IS the target (the focused binding's meaning), recorded then used.
    final fresh = driverWith(bridge);
    await fresh.perform(const KeyPressAction('Escape'));
    expect(bridge.calls, contains('keyPress(Escape)'));
  });

  test('focus contract: semantic verbs bypass the gate entirely', () async {
    final bridge = FakeBridge();
    final driver = driverWith(bridge);
    bridge
      ..snapshotResult = (code: 0, json: _appJsonWithPid)
      ..frontmostResult = (code: 0, json: _safariJson);
    await driver.snapshot();

    // Frontmost (Safari) != anchor (Finder): a global verb would refuse,
    // but locator verbs act below the focus layer.
    await driver.perform(const ClickAction(name: 'Save'));
    expect(bridge.pressedHandles, [2]);
    await driver.perform(const SetValueAction('bg', name: 'Search'));
    expect(bridge.setValues.last, (3, 'bg'));
  });

  test('pid-scoped rung: anchored typing posts to the target, focus '
      'untouched', () async {
    final bridge = FakeBridge();
    // Anchored to pid 4242 while Finder owns the user's focus — the
    // rung's whole point is that this still types.
    final driver = MacosDriver(bridge: bridge, targetPid: 4242);
    bridge.frontmostResult = (code: 0, json: _finderJson);

    await driver.perform(const TypeAction('hello background', submit: true));

    expect(bridge.pidTypedText, [(pid: 4242, text: 'hello background')]);
    expect(bridge.calls, contains('keyPressToPid(4242,Enter)'));
    expect(
      bridge.calls.where((call) => call == 'frontmost'),
      isEmpty,
      reason: 'the rung routes around the focus gate, not through it',
    );
    expect(bridge.calls, isNot(contains('typeText')));
    expect(driver.capabilities.pidScopedEvents, isTrue);
  });

  test('pid-scoped rung: chords post hold/tap/release to the pid in '
      'order', () async {
    final bridge = FakeBridge();
    final driver = MacosDriver(bridge: bridge, targetPid: 77);

    await driver.perform(
      const KeyPressAction('c', modifiers: ['meta', 'shift']),
    );

    expect(bridge.calls.where((call) => call.contains('(77')), [
      'keyDownToPid(77,Meta)',
      'keyDownToPid(77,Shift)',
      'keyPressToPid(77,c)',
      'keyUpToPid(77,Shift)',
      'keyUpToPid(77,Meta)',
    ], reason: 'modifiers hold before the tap and release in reverse after');
    expect(bridge.calls.where((call) => call == 'frontmost'), isEmpty);
  });

  test('pid-scoped rung: pointer verbs stay focus-bound on an anchored '
      'session', () async {
    final bridge = FakeBridge();
    final driver = MacosDriver(bridge: bridge, targetPid: 4242);
    bridge.frontmostResult = (code: 0, json: _finderJson);

    // Scroll carries global screen coordinates: still bound by the
    // focus contract even though typing is not.
    await expectLater(
      driver.perform(const ScrollAction(distance: 3)),
      throwsA(isA<ForegroundRequiredException>()),
    );
  });
}
