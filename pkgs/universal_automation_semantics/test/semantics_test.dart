import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_semantics/universal_automation_semantics.dart';

AxNode _node(
  String role, {
  String? name,
  String? value,
  String? identifier,
  List<AxNode> children = const [],
}) => AxNode(
  role: role,
  name: name,
  value: value,
  attributes: identifier == null ? const {} : {'identifier': identifier},
  children: children,
);

/// window
///   toolbar (identifier: toolbar)
///     button "New"
///     button "Open"
///   textbox "Email" value ""
///   button "Buy"
Snapshot _fixture({String emailValue = ''}) => Snapshot(
  roots: [
    _node(
      'window',
      name: 'Main',
      children: [
        _node(
          'toolbar',
          identifier: 'toolbar',
          children: [
            _node('button', name: 'New'),
            _node('button', name: 'Open'),
          ],
        ),
        _node('textbox', name: 'Email', value: emailValue),
        _node('button', name: 'Buy'),
      ],
    ),
  ],
  capturedAt: DateTime.parse('2026-10-08T12:00:00Z'),
  revision: 7,
);

void main() {
  test('refs number the full walk; views only decide what is shown', () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(subtreeOf: 's_1'), // the toolbar
    );
    // Full walk: window, toolbar, New, Open, Email, Buy = 6 nodes.
    expect(observation.walkedCount, 6);
    // Shown: toolbar + two buttons — but refs stay full-walk.
    expect(observation.nodes.map((n) => n.ref).toList(), [
      's_1',
      's_2',
      's_3',
    ]);
    final rendered = observation.render();
    expect(rendered, contains('# observation rev=7 walked=6 shown=3'));
    expect(rendered, contains('s_2 button "New"'));
    // Resolve works for any full-walk ref, shown or not.
    expect(observation.resolve('s_5').node.name, 'Buy');
  });

  test('identifier selectors and field shaping work', () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(
        subtreeOf: 'toolbar',
        fields: {SemanticField.role, SemanticField.name},
      ),
    );
    expect(observation.nodes.first.ref, 's_1');
    final rendered = observation.render();
    expect(rendered, isNot(contains('value=')));
  });

  test('trimming hides the tail, admits it in the header, never renumbers',
      () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(maxNodes: 2),
    );
    expect(observation.trimmed, isTrue);
    expect(observation.render(), contains('TRIMMED'));
    expect(observation.nodes.map((n) => n.ref).toList(), ['s_0', 's_1']);
  });

  test('panes nest their own walks with namespaced refs', () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(
        maxNodes: 1, // main shows only the window
        panes: {
          'toolbar': SemanticView(subtreeOf: 's_1'),
        },
      ),
    );
    final rendered = observation.render();
    expect(rendered, contains('# pane main'));
    expect(rendered, contains('# pane toolbar'));
    expect(rendered, contains('toolbar.s_1 button "New"'));
    expect(observation.resolve('toolbar.s_1').node.name, 'New');
    expect(observation.walkedCount, 6 + 3); // main walk + pane subtree
  });

  test('a pane selector naming an absent node renders an empty section',
      () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(panes: {
        'ghost': SemanticView(subtreeOf: 's_99'),
      }),
    );
    final rendered = observation.render();
    expect(rendered, contains('# pane ghost'));
    expect(rendered, isNot(contains('ghost.s_')));
  });

  test('diff reports added, removed, and value-changed rows', () {
    final view = const SemanticView();
    final before = Observation.of(_fixture(), view);
    // "Open" removed, a "Save" button added, Email gained a value.
    final after = Observation.of(
      Snapshot(
        roots: [
          _node(
            'window',
            name: 'Main',
            children: [
              _node(
                'toolbar',
                identifier: 'toolbar',
                children: [
                  _node('button', name: 'New'),
                  _node('button', name: 'Save'),
                ],
              ),
              _node('textbox', name: 'Email', value: 'a@b.c'),
              _node('button', name: 'Buy'),
            ],
          ),
        ],
        capturedAt: DateTime.parse('2026-10-08T12:00:01Z'),
        revision: 8,
      ),
      view,
    );
    final delta = after.diff(before);
    expect(delta.renderedNames(), {'added': ['Save'], 'removed': ['Open'], 'changed': ['Email']});
    expect(delta.render(), contains('+ '));
    expect(delta.render(), contains('- '));
    expect(delta.render(), contains('~ '));
    expect(delta.render(), contains('"a@b.c"'));
  });

  test('a pure reflow with unchanged structure reports no change', () {
    final view = const SemanticView();
    final before = Observation.of(_fixture(), view);
    final after = Observation.of(_fixture(), view); // same tree, new rev
    expect(after.diff(before).isEmpty, isTrue);
    expect(after.diff(before).render(), '# no change');
  });

  test('identified siblings match across reordering (keyed diffing)', () {
    final view = const SemanticView();
    AxNode toolbarNode({required List<AxNode> children}) => _node(
      'toolbar',
      identifier: 'toolbar',
      children: children,
    );
    final before = Observation.of(
      Snapshot(
        roots: [
          _node('window', name: 'Main', children: [
            toolbarNode(children: [
              _node('button', name: 'Save', identifier: 'btn.save'),
              _node('button', name: 'Open', identifier: 'btn.open'),
            ]),
          ]),
        ],
        capturedAt: DateTime.parse('2026-10-08T12:00:00Z'),
        revision: 1,
      ),
      view,
    );
    // Same two buttons, order swapped: identities pair by identifier.
    final after = Observation.of(
      Snapshot(
        roots: [
          _node('window', name: 'Main', children: [
            toolbarNode(children: [
              _node('button', name: 'Open', identifier: 'btn.open'),
              _node('button', name: 'Save', identifier: 'btn.save'),
            ]),
          ]),
        ],
        capturedAt: DateTime.parse('2026-10-08T12:00:01Z'),
        revision: 2,
      ),
      view,
    );
    expect(after.diff(before).render(), '# no change');
  });

  test('a value change on a reordered identified sibling still pairs', () {
    final view = const SemanticView();
    AxNode tree({required String saveValue}) => _node(
      'window',
      name: 'Main',
      children: [
        _node('textbox', name: 'Title', value: saveValue,
            identifier: 'field.title'),
        _node('button', name: 'Buy', identifier: 'btn.buy'),
      ],
    );
    final before = Observation.of(
      Snapshot(
        roots: [tree(saveValue: '')],
        capturedAt: DateTime.parse('2026-10-08T12:00:00Z'),
        revision: 1,
      ),
      view,
    );
    final after = Observation.of(
      Snapshot(
        roots: [
          // Reordered: the button moved before the field; the field's
          // value changed. Keyed matching reports one ~ row, not churn.
          _node('window', name: 'Main', children: [
            _node('button', name: 'Buy', identifier: 'btn.buy'),
            _node('textbox', name: 'Title', value: 'hello',
                identifier: 'field.title'),
          ]),
        ],
        capturedAt: DateTime.parse('2026-10-08T12:00:01Z'),
        revision: 2,
      ),
      view,
    );
    final delta = after.diff(before);
    expect(delta.added, isEmpty);
    expect(delta.removed, isEmpty);
    expect(delta.changed.single.current.ref, 's_2');
    expect(delta.render(), contains('"hello"'));
  });

  test('stale refs fail closed with a reobserve hint', () {
    final observation = Observation.of(
      _fixture(),
      const SemanticView(maxNodes: 1),
    );
    // Hidden-but-walked refs resolve (display ≠ resolution); a ref no
    // walk ever issued does not.
    expect(observation.resolve('s_5').node.name, 'Buy');
    expect(
      () => observation.resolve('s_99'),
      throwsA(
        isA<SemanticRefUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('reobserve'),
        ),
      ),
    );
  });

  test('the wire form round-trips and speaks mcp_flutter filter keys', () {
    const view = SemanticView(
      fields: {SemanticField.role, SemanticField.value},
      subtreeOf: 's_1',
      identifierPrefix: 'nav.',
      maxNodes: 40,
      panes: {'header': SemanticView(maxNodes: 5)},
    );
    final json = view.toJson();
    // The mcp_flutter-compatible keys are exactly these.
    expect(json['subtreeOf'], 's_1');
    expect(json['identifierPrefix'], 'nav.');
    expect(json['fields'], ['role', 'value']);
    final restored = SemanticView.fromJson(json);
    expect(restored.fields, view.fields);
    expect(restored.subtreeOf, 's_1');
    expect(restored.identifierPrefix, 'nav.');
    expect(restored.maxNodes, 40);
    expect(restored.panes['header']!.maxNodes, 5);
    // And a bare mcp_flutter-style filter map parses directly.
    final bare = SemanticView.fromJson({
      'identifierPrefix': 'item-',
      'subtreeOf': '',
      'fields': ['role', 'name', 'value'],
    });
    expect(bare.identifierPrefix, 'item-');
    expect(bare.subtreeOf, isNull); // blank counts as unasked
  });

  test('unknown fields and non-integer caps fail closed', () {
    expect(
      () => SemanticView.fromJson({'fields': ['role', 'aura']}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SemanticView.fromJson({'maxNodes': 'many'}),
      throwsA(isA<FormatException>()),
    );
  });
}

extension on ObservationDelta {
  Map<String, List<String>> renderedNames() => {
    'added': [for (final node in added) node.node.name ?? node.node.role],
    'removed': [for (final node in removed) node.node.name ?? node.node.role],
    'changed': [for (final change in changed) change.current.node.name ?? ''],
  };
}
