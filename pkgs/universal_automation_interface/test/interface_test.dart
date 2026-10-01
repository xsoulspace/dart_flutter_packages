import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

void main() {
  group('AutomationEndpoint', () {
    test('round-trips through JSON', () {
      final endpoint = AutomationEndpoint(
        transport: AutomationTransport.cdp,
        uri: Uri.parse('http://127.0.0.1:9222'),
        authToken: 'secret',
        metadata: const {'browser': 'chrome-141'},
      );
      final restored = AutomationEndpoint.fromJson(endpoint.toJson());
      expect(restored.transport, endpoint.transport);
      expect(restored.uri, endpoint.uri);
      expect(restored.authToken, 'secret');
      expect(restored.metadata['browser'], 'chrome-141');
    });
  });

  group('SessionHandles', () {
    test('follows the oka naming convention', () {
      expect(SessionHandles.handle('chrome'), 'session-chrome-handle');
      expect(
        SessionHandles.sub('chrome', 'cdp-port'),
        'session-chrome-cdp-port',
      );
      expect(SessionHandles.nameOf('session-chrome-handle'), 'chrome');
      expect(SessionHandles.nameOf('unrelated'), isNull);
    });
  });

  group('SessionDescriptor', () {
    test('rejects borrowed sessions with start mode', () {
      expect(
        () => SessionDescriptor(
          name: 'chrome',
          startMode: StartMode.start,
          ownership: LeaseOwnership.borrowed,
        ),
        throwsA(isA<SpecViolationException>()),
      );
    });

    test('accepts borrowed attach and owned start', () {
      expect(
        SessionDescriptor(name: 'chrome', startMode: StartMode.start).name,
        'chrome',
      );
      expect(
        SessionDescriptor(
          name: 'user-safari',
          ownership: LeaseOwnership.borrowed,
        ).ownership,
        LeaseOwnership.borrowed,
      );
    });

    test('rejects empty names', () {
      expect(
        () => SessionDescriptor(name: '  '),
        throwsA(isA<SpecViolationException>()),
      );
    });
  });

  group('AxNode', () {
    const tree = AxNode(
      role: 'root',
      children: [
        AxNode(
          role: 'button',
          name: 'Submit',
          bounds: AxBounds(left: 10, top: 20, width: 100, height: 30),
        ),
        AxNode(
          role: 'textbox',
          name: 'Email',
          value: '',
          children: [AxNode(role: 'generic', name: 'hint')],
        ),
      ],
    );

    test('walks depth-first and finds by role/name', () {
      expect(tree.walk().length, 4);
      expect(tree.byRole('button', name: 'Submit'), isNotNull);
      expect(tree.byName('hint')!.role, 'generic');
      expect(tree.byRole('link'), isNull);
    });

    test('bounds expose a click center', () {
      final node = tree.byRole('button')!;
      expect(node.bounds!.center, (60.0, 35.0));
    });

    test('round-trips through JSON', () {
      final restored = AxNode.fromJson(tree.toJson());
      expect(restored.children.length, 2);
      expect(restored.children[1].children[0].name, 'hint');
    });
  });

  group('AutomationEvent', () {
    test('events round-trip payload-free', () {
      final event = FrameDelivered(
        sourceId: 'cdp-main',
        sequence: 7,
        revision: 2,
        byteLength: 512,
        contentType: 'image/jpeg',
        capturedAt: DateTime.utc(2026, 9, 27, 12, 30),
      );
      final json = event.toJson();
      expect(json.containsKey('bytes'), isFalse);
      expect(json['type'], 'frameDelivered');
      expect(json['sequence'], 7);
    });
  });

  group('ElementNotFoundException', () {
    test('carries locator identity and a stable kind', () {
      const error = ElementNotFoundException('name', 'Buy');
      expect(error.kind, 'elementNotFound');
      expect(error.locator, 'name');
      expect(error.locatorValue, 'Buy');
      expect(error.toString(), contains('no node matches name "Buy"'));
    });
  });
}
