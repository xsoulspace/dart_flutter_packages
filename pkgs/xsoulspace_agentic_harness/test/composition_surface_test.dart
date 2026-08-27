// ignore_for_file: lines_longer_than_80_chars

/// Declarative composition surface (ADR 0014): verifies (a) the closed
/// shape-set hard rule — unknown declarative keys throw, (b) rendering a
/// FlowSpec onto the existing DecisionFlow, (c) the tool-surface seam gate,
/// and (d) the eval tier split keeps coding pass-rate honest while prose/
/// dialogue rows are evidence, never pass.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

void main() {
  group('FlowSpec — closed shape-set (ADR 0014 §1)', () {
    test('parses decide + verify stages and a tool surface', () {
      final flow = FlowSpec.fromYaml('''
name: quick_editor
archetype: code_edit
tools:
  allow_all: false
  allowed: [read, write, glob]
stages:
  - kind: decide
    trigger: tool_result
    prompt: continue after the tool result
  - kind: decide
    trigger: idle_every_n_ticks
    every_n_ticks: 100
    prompt: reflect
  - kind: verify
    check: contains
    path: lib/a.dart
''');
      expect(flow.name, 'quick_editor');
      expect(flow.archetype, TaskArchetype.codeEdit);
      expect(flow.toolSurface.allows(const ToolName('read')), isTrue);
      expect(flow.toolSurface.allows(const ToolName('grep')), isFalse);

      final rendered = renderFlow(flow);
      // Two decide stages → two policies; idle-tick stage carries a real
      // interval. Verify stage is extracted, not turned into a policy.
      expect(rendered.flow.policies.length, 2);
      expect(rendered.verifies.length, 1);
      // The continuation policy is the first-added (tool_result) stage shape.
      expect(rendered.flow.policies.first.name, 'onToolResult');
    });

    test('unknown stage kind throws (closed shape-set)', () {
      expect(
        () => FlowSpec.fromYaml('''
name: x
stages:
  - kind: while_loop
'''),
        throwsArgumentError,
      );
    });
  });

  group('ToolSurface gate (seam 3)', () {
    test('filters ToolDefs to allowed names, preserving order', () {
      final all = [
        ToolDef.encode(
          name: const ToolName('read'),
          description: 'r',
          execute: (_) async => null,
        ),
        ToolDef.encode(
          name: const ToolName('write'),
          description: 'w',
          execute: (_) async => null,
        ),
      ];
      const surface = ToolSurface(allowed: {'read'});
      final allowed = applyToolSurface(all, surface);
      expect(allowed.map((t) => t.name.value), ['read']);
    });
  });

  group('Dataset tiers — honest eval (ADR 0014 §3)', () {
    test('pass-rate counts passable rows only; evidence excluded', () {
      final summary = DatasetResultSummary([
        const DatasetRow(
          task: 'edit_01',
          backend: EvalBackend.native,
          tokens: 10,
          calls: 2,
          passed: true,
        ),
        const DatasetRow(
          task: 'edit_02',
          backend: EvalBackend.native,
          tokens: 500,
          calls: 4,
          passed: false,
        ),
        const DatasetRow(
          task: 'screenplay_act1',
          backend: EvalBackend.native,
          tokens: 900,
          calls: 6,
          evidence: 'act structure coherent; beats verified',
        ),
      ]);
      expect(summary.passableCount, 2);
      expect(summary.evidenceCount, 1);
      expect(summary.passedCount, 1);
      expect(summary.passRate, 0.5); // evidence row is never counted
      expect(summary.totalTokens, 900 + 10 + 500);
    });

    test('DatasetSpec.fromYaml closes tier + backends', () {
      final d = DatasetSpec.fromYaml('''
id: code_suite
tier: passable
tasks: [edit_01, glob_02]
backends: [scripted, pi]
''');
      expect(d.id, 'code_suite');
      expect(d.tier, EvalTier.passable);
      expect(d.taskRefs, ['edit_01', 'glob_02']);
      expect(d.backends, [EvalBackend.scripted, EvalBackend.pi]);
    });
  });
}
