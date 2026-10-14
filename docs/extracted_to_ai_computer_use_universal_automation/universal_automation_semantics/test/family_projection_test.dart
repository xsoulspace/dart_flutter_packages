import 'package:test/test.dart';
import 'package:universal_automation_semantics/universal_automation_semantics.dart';

void main() {
  group('snapshotRef', () {
    test('is the one family ref dialect', () {
      expect(snapshotRef(0), 's_0');
      expect(snapshotRef(17), 's_17');
    });
  });

  group('familySnapshotFromNodes', () {
    final nodes = [
      {
        'ref': 's_0',
        'type': 'Container',
        'label': 'Root',
        'bounds': {'left': 0.0, 'top': 0.0, 'right': 100.0, 'bottom': 50.0},
        'children': ['s_1', 's_2'],
      },
      {
        'ref': 's_1',
        'type': 'Button',
        'label': 'Save',
        'identifier': 'save-btn',
        'enabled': true,
        'children': <String>[],
      },
      {
        'ref': 's_2',
        'type': 'TextField',
        'label': 'Email',
        'value': '',
        'children': <String>[],
      },
    ];

    test('projects type/label/value/bounds onto the shared axis', () {
      final snapshot = familySnapshotFromNodes(
        nodes,
        snapshotId: 3,
        capturedAt: DateTime.utc(2026, 10, 8),
      );
      expect(snapshot.revision, 3);
      expect(snapshot.roots, hasLength(1));
      final root = snapshot.roots.first;
      expect(root.role, 'container');
      expect(root.name, 'Root');
      expect(root.bounds, isNotNull);
      expect(root.bounds!.width, 100);
      expect(
        root.children.map((child) => child.role).toList(),
        ['button', 'textfield'],
      );
      expect(root.children[0].name, 'Save');
      // The empty value rides along: an empty field is an answer.
      expect(root.children[1].value, '');
      // Producer vocabulary lands in attributes, lossy to strings.
      expect(root.children[0].attributes['identifier'], 'save-btn');
      expect(root.children[0].attributes['enabled'], 'true');
      expect(snapshot.nodes.map((node) => node.role), contains('button'));
    });

    test('dropped children (trim) do not break parent links', () {
      final trimmed = [
        nodes.first,
        {...nodes[1], 'children': <String>['s_2']},
      ];
      final snapshot = familySnapshotFromNodes(
        trimmed,
        snapshotId: 1,
        capturedAt: DateTime.utc(2026, 10, 8),
      );
      // s_2's map is gone; the dangling ref is skipped wherever it
      // appears and s_1 keeps its slot under the root.
      expect(snapshot.roots, hasLength(1));
      expect(snapshot.roots.first.children, hasLength(1));
      expect(snapshot.roots.first.children.first.children, isEmpty);
    });
  });

  group('projectSnapshotNodes', () {
    final nodes = [
      {
        'ref': 's_0',
        'type': 'container',
        'children': <String>['s_1', 's_2'],
      },
      {'ref': 's_1', 'type': 'button', 'label': 'Save', 'hint': 'commit'},
      {'ref': 's_2', 'type': 'text', 'label': 'Body'},
    ];

    test('no filter keeps everything verbatim', () {
      expect(projectSnapshotNodes(nodes), nodes);
    });

    test('keep predicate prunes and prunes children to kept refs', () {
      final projected = projectSnapshotNodes(
        nodes,
        keep: (node) => node['type'] != 'text',
      );
      expect(projected, hasLength(2));
      expect(projected[0]['children'], ['s_1']);
      expect(projected[1]['children'], isNull);
    });

    test('fields projection always keeps ref', () {
      final projected = projectSnapshotNodes(
        nodes,
        fields: ['type'],
      );
      for (final node in projected) {
        expect(node.containsKey('ref'), isTrue);
        expect(node.containsKey('label'), isFalse);
      }
    });

    test('children emptied by pruning are dropped entirely', () {
      final projected = projectSnapshotNodes(
        nodes,
        keep: (node) => node['ref'] == 's_0',
        fields: ['type', 'children'],
      );
      expect(projected, [
        {'ref': 's_0', 'type': 'container'},
      ]);
    });
  });
}

void nodeAtTests() {}
