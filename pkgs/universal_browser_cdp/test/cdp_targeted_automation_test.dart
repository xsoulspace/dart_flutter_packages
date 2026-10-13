import 'dart:async';
import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_browser_cdp/testing.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

void main() {
  late FakeCdpServer server;
  late CdpBrowserSession session;
  setUp(() async {
    server = FakeCdpServer();
    await server.start();
    session = await CdpBrowserSession.attach(server.httpBase);
  });
  tearDown(() async {
    await session.close();
    await server.stop();
  });
  for (final focus in [false, true]) {
    test('absent target waits before ${focus ? 'focus' : 'click'}', () async {
      server
        ..axNodes = []
        ..callFunctionOnValue = focus
            ? '{"state":"focused"}'
            : '{"state":"ready","x":10,"y":20,"width":40,"height":20}';
      final update = Timer(const Duration(milliseconds: 100), () {
        server.axNodes = [
          {
            'nodeId': '1',
            'role': {'value': 'button'},
            'name': {'value': 'Save'},
            'backendDOMNodeId': 1,
          },
        ];
      });
      try {
        const target = SemanticTarget(role: 'button', name: 'Save');
        if (focus) {
          await session.driver.focusTarget(target);
        } else {
          await session.driver.clickTarget(target);
        }
        expect(server.inputEvents, hasLength(focus ? 0 : 3));
        expect(
          server.methods
              .where((s) => s == 'Accessibility.getFullAXTree')
              .length,
          greaterThan(1),
        );
      } finally {
        update.cancel();
      }
    });
  }
  test('duplicate semantic names refuse before input', () async {
    server.axNodes = [
      for (var i = 0; i < 2; i++)
        {
          'nodeId': '$i',
          'role': {'value': 'button'},
          'name': {'value': 'Save'},
          'backendDOMNodeId': i + 1,
        },
    ];
    await expectLater(
      session.driver.clickTarget(const SemanticTarget(name: 'Save')),
      throwsA(isA<TargetResolutionException>()),
    );
    expect(server.inputEvents, isEmpty);
  });
  test(
    'fresh scoped target waits for stable bounds and dispatches once',
    () async {
      server
        ..axNodes = [
          {
            'nodeId': '0',
            'role': {'value': 'dialog'},
            'name': {'value': 'Editor'},
            'childIds': ['1'],
          },
          {
            'nodeId': '1',
            'role': {'value': 'button'},
            'name': {'value': 'Save'},
            'backendDOMNodeId': 1,
          },
          {
            'nodeId': '2',
            'role': {'value': 'button'},
            'name': {'value': 'Save'},
            'backendDOMNodeId': 2,
          },
        ]
        ..callFunctionOnValue =
            '{"state":"ready","x":10,"y":20,"width":40,"height":20}';
      await session.driver.clickTarget(
        const SemanticTarget(
          name: 'Save',
          scope: [SemanticTarget(name: 'Editor')],
        ),
      );
      expect(server.inputEvents, hasLength(3));
      expect(server.inputEvents[1]['x'], 30);
      expect(
        server.methods.where((s) => s == 'Accessibility.getFullAXTree').length,
        2,
      );
    },
  );
  test('element focus verifies independently of pointer delivery', () async {
    server
      ..axNodes = [
        {
          'nodeId': '1',
          'role': {'value': 'button'},
          'name': {'value': 'Submit'},
          'backendDOMNodeId': 1,
        },
      ]
      ..callFunctionOnValue = '{"state":"focused"}';
    await session.driver.focusTarget(
      const SemanticTarget(role: 'button', name: 'Submit'),
    );
    expect(server.inputEvents, isEmpty);
    server.callFunctionOnValue = '{"state":"not-focusable"}';
    await expectLater(
      session.driver.focusTarget(const SemanticTarget(name: 'Submit')),
      throwsA(isA<ProtocolException>()),
    );
  });
  test(
    'AX scalar properties preserve focused, checked, range and human value',
    () async {
      server.axNodes = [
        {
          'nodeId': '1',
          'role': {'value': 'slider'},
          'name': {'value': 'Frequency'},
          'value': {'value': 1.0},
          'properties': [
            {
              'name': 'focused',
              'value': {'value': true},
            },
            {
              'name': 'disabled',
              'value': {'value': false},
            },
            {
              'name': 'checked',
              'value': {'value': 'mixed'},
            },
            {
              'name': 'valuemin',
              'value': {'value': 0},
            },
            {
              'name': 'valuemax',
              'value': {'value': 2},
            },
            {
              'name': 'valuetext',
              'value': {'value': '1.25 Hz'},
            },
          ],
        },
      ];
      final node = (await session.driver.snapshot()).nodes.single;
      expect(node.attributes, {
        'focused': 'true',
        'disabled': 'false',
        'checked': 'mixed',
        'valuemin': '0',
        'valuemax': '2',
        'valuetext': '1.25 Hz',
      });
    },
  );
  test('disabled refuses before DOM resolution or input', () async {
    server.axNodes = [
      {
        'nodeId': '1',
        'role': {'value': 'button'},
        'name': {'value': 'Save'},
        'backendDOMNodeId': 1,
        'properties': [
          {
            'name': 'disabled',
            'value': {'value': true},
          },
        ],
      },
    ];
    await expectLater(
      session.driver.clickTarget(const SemanticTarget(name: 'Save')),
      throwsA(isA<ProtocolException>()),
    );
    expect(server.methods, isNot(contains('DOM.resolveNode')));
    expect(server.inputEvents, isEmpty);
  });
}
