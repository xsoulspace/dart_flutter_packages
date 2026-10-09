import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'webdriver_client.dart';

/// [AutomationDriver] over a W3C WebDriver session.
///
/// The classic WebDriver protocol has no accessibility-tree endpoint, so
/// `capabilities.a11yTree` is declared `false` and [snapshot] refuses
/// loudly — semantic snapshots for Safari arrive through the OS-native
/// tier, not through WebDriver.
class WebDriverDriver implements AutomationDriver {
  /// Creates a driver over a started session.
  WebDriverDriver(this._client);

  final WebDriverClient _client;
  bool _closed = false;

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    screenshot: true,
    inputSynthesis: true,
    pointerCoordinates: true,
  );

  /// The underlying client.
  WebDriverClient get client => _client;

  @override
  Future<Snapshot> snapshot() async {
    throw const DriverUnsupportedException(
      'classic WebDriver has no accessibility-tree endpoint; '
      'use the OS-native tier for semantic snapshots',
    );
  }

  @override
  Future<void> perform(AutomationAction action) async {
    switch (action) {
      case NavigateAction(:final url):
        await _client.navigate(url);
      case ClickAction(:final css, :final name):
        final element = css != null
            ? await _client.findElementByCss(css)
            : await _client.findElement('link text', name!);
        await _client.elementClick(element);
      case TypeAction(:final text, :final css, :final submit):
        final element = await _client.findElementByCss(css ?? 'body');
        await _client.sendKeys(element, text);
        if (submit) await _client.keyPress('\n');
      case ScrollAction():
        throw const DriverUnsupportedException(
          'surface scrolling is not part of this driver\'s protocol; '
          'it refuses loudly instead of silently dropping it',
        );
      case KeyPressAction(:final key, :final modifiers):
        if (modifiers.isEmpty) {
          final wireKey = _wireKeys[key];
          if (wireKey == null) {
            throw DriverUnsupportedException(
              'WebDriver: key "$key" is not in the supported set '
              '(${_wireKeys.keys.toList()})',
            );
          }
          await _client.keyPress(wireKey);
        } else {
          // A chord is one keyboard source: modifiers down, the key,
          // modifiers up (release order mirrors the press).
          await _client.runInputSources([
            {
              'type': 'key',
              'id': 'keyboard',
              'actions': [
                for (final modifier in modifiers)
                  {'type': 'keyDown', 'value': _wireKey(modifier)},
                {'type': 'keyDown', 'value': _wireKey(key)},
                {'type': 'keyUp', 'value': _wireKey(key)},
                for (final modifier in modifiers.reversed)
                  {'type': 'keyUp', 'value': _wireKey(modifier)},
              ],
            },
          ]);
        }
      case EvaluateAction(:final expression):
        throw DriverUnsupportedException(
          'classic WebDriver has no script endpoint; got '
          '${expression.length} chars',
        );
      case ClickAtAction(
        :final x,
        :final y,
        :final button,
        :final clickCount,
        :final modifiers,
      ):
        // W3C pointer actions carry no click state; multi-clicks are
        // adjacent down/up pairs, which remotes fold into their
        // double/triple-click recognition.
        await _dispatchPointerChord(
          _client,
          modifiers,
          [
            _pointerMove(x, y),
            for (var press = 1; press <= clickCount.clamp(1, 3); press++) ...[
              {'type': 'pointerDown', 'button': _w3cButton(button)},
              {'type': 'pointerUp', 'button': _w3cButton(button)},
            ],
          ],
        );
      case MoveAction(:final x, :final y):
        await _client.runPointerActions([_pointerMove(x, y)]);
      case DragAction(
        :final fromX,
        :final fromY,
        :final toX,
        :final toY,
        :final button,
        :final modifiers,
      ):
        await _dispatchPointerChord(
          _client,
          modifiers,
          [
            _pointerMove(fromX, fromY),
            {'type': 'pointerDown', 'button': _w3cButton(button)},
            _pointerMove(toX, toY),
            {'type': 'pointerUp', 'button': _w3cButton(button)},
          ],
        );
      case InvokeAction(:final name):
        throw DriverUnsupportedException(
          'the WebDriver tier has no surface action registry; '
          'InvokeAction("$name") needs the instrumented or CDP tier',
        );
    }
  }

  @override
  Future<Uint8List> screenshot() => _client.screenshot();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client.deleteSession();
  }
}

Map<String, Object?> _pointerMove(double x, double y) => {
  'type': 'pointerMove',
  'duration': 0,
  'x': x,
  'y': y,
  'origin': 'viewport',
};

/// Family button names → W3C pointer-button codes (`left` 0, `middle` 1,
/// `right` 2).
int _w3cButton(String button) => switch (button.toLowerCase()) {
  'middle' => 1,
  'right' => 2,
  _ => 0,
};

/// The family's logical key names → W3C Unicode PUA wire keys, modifier
/// chord names included.
const _wireKeys = <String, String>{
  'Enter': '\uE007',
  'Tab': '\uE004',
  'Escape': '\uE00C',
  'Backspace': '\uE003',
  'ArrowLeft': '\uE012',
  'ArrowUp': '\uE013',
  'ArrowRight': '\uE014',
  'ArrowDown': '\uE015',
  'Shift': '\uE008',
  'Control': '\uE009',
  'Alt': '\uE00A',
  'Meta': '\uE03D',
};

String _wireKey(String key) {
  // Modifiers travel lowercase through the family vocabulary; named
  // keys are capitalized. Look up either shape.
  final wire =
      _wireKeys[key] ??
      _wireKeys[key.isEmpty ? key : key[0].toUpperCase() + key.substring(1)];
  if (wire == null) {
    throw DriverUnsupportedException(
      'WebDriver: key "$key" is not in the supported set '
      '(${_wireKeys.keys.toList()})',
    );
  }
  return wire;
}

/// Lowers one pointer gesture, holding a keyboard source with
/// [modifiers] alongside it when a chord is asked for.
///
/// Tick alignment (W3C dispatches sources tick by tick, idle past a
/// source's list): the key downs land in the opening ticks, then
/// `pause` actions idle the keyboard until the pointer's last tick has
/// passed, so the key ups strictly follow the release.
Future<void> _dispatchPointerChord(
  WebDriverClient client,
  List<String> modifiers,
  List<Map<String, Object?>> pointerActions,
) async {
  if (modifiers.isEmpty) {
    await client.runPointerActions(pointerActions);
    return;
  }
  final keyActions = [
    for (final modifier in modifiers)
      {'type': 'keyDown', 'value': _wireKey(modifier)},
    for (var i = 0; i < pointerActions.length - 1; i++)
      {'type': 'pause', 'duration': 0},
    for (final modifier in modifiers.reversed)
      {'type': 'keyUp', 'value': _wireKey(modifier)},
  ];
  await client.runInputSources([
    {'type': 'key', 'id': 'keyboard', 'actions': keyActions},
    {
      'type': 'pointer',
      'id': 'mouse',
      'parameters': {'pointerType': 'mouse'},
      'actions': pointerActions,
    },
  ]);
}
