// The Flutter-web driving primitives, against the fake endpoint: focus
// restoration, caret typing, live-DOM name location, and field reads —
// the set the multiplayer gates measured as the difference between
// working and dead automation on real Chromium + Flutter web.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/testing.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

void main() {
  late FakeCdpServer server;
  late Uri httpBase;
  late CdpBrowserSession session;

  setUp(() async {
    server = FakeCdpServer();
    httpBase = await server.start();
    session = await CdpBrowserSession.attach(httpBase);
  });

  tearDown(() async {
    await session.close(closeTarget: false);
    await server.stop();
  });

  group('focus + caret typing (background-window safe)', () {
    test('bringToFront sends Page.bringToFront', () async {
      await session.page.bringToFront();
      expect(server.methods, contains('Page.bringToFront'));
    });

    test('insertText sends one Input.insertText with the full text',
        () async {
      await session.page.insertText('mesh-pair/v1 code');
      final inserts = server.inputEvents
          .where((event) => event.containsKey('text'))
          .toList();
      expect(inserts, hasLength(1));
      expect(inserts.single['text'], 'mesh-pair/v1 code');
    });

    test(
        'TypeAction without a locator lowers to bringToFront + insertText '
        '(no per-key events — they need OS focus a background window '
        'does not have)', () async {
      await session.driver
          .perform(const TypeAction('typed into the focused field'));
      expect(server.methods, contains('Page.bringToFront'));
      final inserts = server.inputEvents
          .where((event) => event.containsKey('text'))
          .toList();
      expect(inserts, hasLength(1));
      expect(
        inserts.single['text'],
        'typed into the focused field',
      );
      final keyEvents = server.inputEvents
          .where(
            (event) =>
                event.containsKey('windowsVirtualKeyCode') ||
                event.containsKey('code'),
          )
          .toList();
      expect(keyEvents, isEmpty);
    });

    test('TypeAction with submit presses Enter after the insert',
        () async {
      await session.driver.perform(const TypeAction('abc', submit: true));
      expect(server.methods, contains('Page.bringToFront'));
      final enter = server.inputEvents.where(
        (event) => event['key'] == 'Enter',
      );
      expect(enter, isNotEmpty);
    });
  });

  group('live-DOM name location', () {
    test('absent name refuses fast with the locator named', () async {
      await expectLater(
        session.page.resolveNamedRect('Nonexistent'),
        throwsA(
          isA<ElementNotFoundException>()
            .having((e) => e.locatorValue, 'locatorValue', 'Nonexistent'),
        ),
      );
    });

    test('hasNamedElement answers the presence probe', () async {
      server.evaluateHandler = (expression) =>
          expression.contains('some(') ? true : null;
      expect(
        await session.page.hasNamedElement('Sync between devices'),
        isTrue,
      );
      server.evaluateHandler = (expression) =>
          expression.contains('some(') ? false : null;
      expect(
        await session.page.hasNamedElement('Sync between devices'),
        isFalse,
      );
    });

    test(
        'resolveNamedRect locates by name and returns actionable bounds '
        '(the legacy probe shape answers through the loop)', () async {
      // Presence probe → true; the rect probe returns a rect with the
      // legacy hitOk shape (state-less), which the actionability loop
      // accepts directly.
      var calls = 0;
      server.evaluateHandler = (expression) {
        if (expression.contains('some(')) return true;
        if (expression.contains('getBoundingClientRect')) {
          calls++;
          return '{"x":40,"y":60,"width":200,"height":80,"hitOk":true}';
        }
        return null;
      };
      final bounds = await session.page.resolveNamedRect(
        'Paste pairing code',
        match: NameMatch.contains,
      );
      expect(calls, greaterThan(0));
      expect(bounds.center, (140.0, 100.0));
    });

    test(
        'driver semantic click falls back to the live DOM when the AX '
        'backend id is dead (stale-id scenario)', () async {
      // AX tree knows the button, but resolving its backendDOMNodeId
      // fails (stale) — the named fallback must click via the live DOM.
      server.axNodes = [
        {
          'nodeId': '1',
          'role': {'value': 'RootWebArea'},
          'childIds': ['2'],
        },
        {
          'nodeId': '2',
          'role': {'value': 'button'},
          'name': {'value': 'Settings'},
          'backendDOMNodeId': 555,
          'attributes': [],
        },
      ];
      server.evaluateHandler = (expression) {
        if (expression.contains('some(')) return 'true';
        if (expression.contains('getBoundingClientRect')) {
          return '{"x":10,"y":20,"width":100,"height":50,"hitOk":true}';
        }
        return null;
      };
      // Force the node-rect path to fail: DOM.resolveNode gets no
      // usable object id (the fake does not implement it, mirroring a
      // detached node), so the poll times out — shrink the driver's
      // timeout pressure by letting the fallback answer immediately.
      await session.driver
          .perform(const ClickAction(role: 'button', name: 'Settings'));
      final clicks = server.inputEvents
          .where((event) => event['type'] == 'mousePressed')
          .toList();
      expect(clicks, isNotEmpty);
    });
  });

  group('field reads', () {
    test('fieldValue reads the selector-addressed editable', () async {
      server.evaluateHandler = (expression) => expression.contains('.value')
          ? '{"v":"mesh-pair/v1 abc"}'
          : null;
      // The JS returns the string directly; encode through the handler.
      server.evaluateHandler = (expression) => expression.contains('.value')
          ? 'the typed code'
          : null;
      expect(
        await session.page.fieldValue('flt-semantics textarea'),
        'the typed code',
      );
    });

    test('editableValues lists every editable in DOM order', () async {
      server.evaluateHandler = (expression) =>
          expression.contains('querySelectorAll')
              ? jsonEncode([
                  {'tag': 'INPUT', 'value': 'first'},
                  {'tag': 'TEXTAREA', 'value': 'second'},
                ])
              : null;
      final values = await session.page.editableValues();
      expect(values, hasLength(2));
      expect(values.last.tag, 'TEXTAREA');
      expect(values.last.value, 'second');
    });
  });
}
