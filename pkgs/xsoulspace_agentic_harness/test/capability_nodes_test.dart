// ignore_for_file: lines_longer_than_80_chars

/// P2 — pack inventory as MEANING nodes: the agent LOCATES and ZOOMS its
/// own capabilities. Gates the reconcile contract:
/// - node shape: kind 'executable', label = executable id, props
///   {executableId, kind, params, verification, description, pack};
/// - edges: impl → pack anchor, capability_of → dir_root (once scanned);
/// - idempotent across refreshes: re-scan updates in place (no duplicates)
///   and a removed entry is DROPPED — never resurrected;
/// - discoverable through the meaning_locate ray (the agent's own verb).
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart' show AgentPlugin;
import 'package:xsoulspace_agentic_harness/src/meaning/capability_nodes.dart';
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_tree.dart';
import 'package:xsoulspace_agentic_harness/src/tools/meaning_locate_tool.dart';

const _entry = CapabilityEntry(
  executableId: 'dart/fix_loop_bound',
  kind: 'replace_member_body',
  params: ['symbolId'],
  verification: ['analyze', 'test'],
  description: 'tighten the loop bound (captured)',
);

World _world() => World()..addPlugin(AgentPlugin());

void main() {
  test('node shape: kind executable, label = executable id, pack props, '
      'impl edge to the stable anchor', () {
    final world = _world();
    reconcileCapabilityNodes(world, [_entry, CapabilityEntry(
      executableId: 'project/rename_field',
      kind: 'rename_symbol',
      params: const ['symbolId', 'newName'],
    )]);
    final index = world.getResource<MeaningIndex>();
    final id = capabilityNodeId('dart/fix_loop_bound');
    expect(hasMeaningNode(world, id), isTrue);
    expect(index.entityOf('pack_edit_capture'), isNotNull,
        reason: 'the stable pack anchor exists');
    final node =
        meaningComponentOf<MeaningNode>(world, index.entityOf(id)!)!;
    expect(node.kind, 'executable');
    expect(node.label, 'dart/fix_loop_bound');
    final props =
        meaningComponentOf<MeaningProps>(world, index.entityOf(id)!)!.props;
    expect(props['executableId'], 'dart/fix_loop_bound');
    expect(props['kind'], 'replace_member_body');
    expect(props['params'], ['symbolId']);
    expect(props['verification'], ['analyze', 'test']);
    expect(props['pack'], 'pack_edit_capture');
    // Edges: impl → anchor, capability_of → dir_root (linked when the fs
    // tier has scanned — simulate by creating dir_root and reconciling).
    expect(
      index.triples.any((t) => t.$1 == id && t.$2 == 'impl'
          && t.$3 == 'pack_edit_capture'),
      isTrue,
    );
    addMeaningNode(world, kind: 'dir', label: '/', id: 'dir_root');
    reconcileCapabilityNodes(world, [_entry]);
    expect(
      index.triples.any((t) => t.$1 == id && t.$2 == 'capability_of'
          && t.$3 == 'dir_root'),
      isTrue,
    );
  });

  test('idempotent: re-scan updates in place — no duplicates, no new nodes',
      () {
    final world = _world();
    final first = reconcileCapabilityNodes(world, [_entry]);
    expect(first['registered'], 1);
    final countAfterFirst =
        world.getResource<MeaningIndex>().nodeCount;
    final second = reconcileCapabilityNodes(world, [_entry]);
    expect(second['registered'], 0);
    expect(second['updated'], 1);
    expect(second['removed'], 0);
    expect(world.getResource<MeaningIndex>().nodeCount, countAfterFirst,
        reason: 'a re-scan must not duplicate');
  });

  test('a removed entry is dropped on reconcile and never resurrected '
      'by later refreshes', () {
    final world = _world();
    final keep = CapabilityEntry(
      executableId: 'project/other_fix',
      kind: 'replace_member_body',
    );
    reconcileCapabilityNodes(world, [_entry, keep]);
    final droppedId = capabilityNodeId(_entry.executableId);
    // The pack no longer carries the entry — the refresh prunes it.
    final r = reconcileCapabilityNodes(world, [keep]);
    expect(r['removed'], 1);
    expect(hasMeaningNode(world, droppedId), isFalse);
    // Later refreshes over the same (smaller) pack stay clean.
    final again = reconcileCapabilityNodes(world, [keep]);
    expect(again['removed'], 0);
    expect(hasMeaningNode(world, droppedId), isFalse,
        reason: 'no resurrection');
    expect(hasMeaningNode(world, capabilityNodeId(keep.executableId)), isTrue);
  });

  test('a changed repair class updates the SAME node in place', () {
    final world = _world();
    reconcileCapabilityNodes(world, [_entry]);
    final id = capabilityNodeId(_entry.executableId);
    reconcileCapabilityNodes(world, [
      const CapabilityEntry(
        executableId: 'dart/fix_loop_bound',
        kind: 'authored_body',
        params: ['symbolId'],
        description: 'promoted to trusted-author',
      ),
    ]);
    final props =
        meaningComponentOf<MeaningProps>(
          world,
          world.getResource<MeaningIndex>().entityOf(id)!,
        )!
            .props;
    expect(props['kind'], 'authored_body');
    expect(props['description'], 'promoted to trusted-author');
    expect(world.getResource<MeaningIndex>().byId.containsKey(id), isTrue);
  });

  test('LOCATE: the agent discovers its own capabilities through the ray',
      () async {
    final world = _world();
    reconcileCapabilityNodes(world, [_entry]);
    final locate = meaningLocateTool(world);
    // The tool layer JSON-stringifies results — decode before reading.
    final out =
        jsonDecode(await locate.execute({'query': 'fix_loop_bound'}) as String)
            as Map;
    final rows = (out['rows'] as List).cast<Map>();
    expect(rows, hasLength(1));
    expect(rows.single['kind'], 'executable');
    expect(rows.single['label'], 'dart/fix_loop_bound');
    expect(rows.single['id'], capabilityNodeId('dart/fix_loop_bound'));
    // Zoom-ready: the row id IS the node id the zoom verbs take.
    expect(jsonDecode(jsonEncode(rows.single))['kind'], 'executable');
  });
}
