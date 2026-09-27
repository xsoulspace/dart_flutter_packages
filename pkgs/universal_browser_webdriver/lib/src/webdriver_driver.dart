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
  DriverCapabilities get capabilities =>
      const DriverCapabilities(screenshot: true, inputSynthesis: true);

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
      case KeyPressAction(:final key):
        final wireKey = _wireKeys[key] ?? key;
        await _client.keyPress(wireKey);
      case EvaluateAction(:final expression):
        throw DriverUnsupportedException(
          'classic WebDriver has no script endpoint; got '
          '${expression.length} chars',
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

/// W3C wire keys for the family's logical key names (Unicode PUA).
const _wireKeys = <String, String>{
  'Enter': '\uE007',
  'Tab': '\uE004',
  'Escape': '\uE00C',
  'Backspace': '\uE003',
  'ArrowLeft': '\uE012',
  'ArrowUp': '\uE013',
  'ArrowRight': '\uE014',
  'ArrowDown': '\uE015',
};
