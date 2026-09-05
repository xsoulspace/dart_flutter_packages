// ignore_for_file: lines_longer_than_80_chars

/// R7 PRODUCTION #2 — the meaning-profile overhead vs the AFM window.
///
/// Never measured until now: the FIXED cost of one meaning-profile decision
/// before any content — `meaningProfileSystemPrompt` + the 5 tool schemas
/// (`repo_etl`/`meaning_zoom`/`meaning_impact`/`edit_symbol`/`run`;
/// `edit_symbol` was expected to dominate) — metered with the SAME
/// chars/4 estimator the harness uses everywhere (`overheadTokens`),
/// checked against the P1 pre-flight `maxContextTokens` guard (3800).
///
/// LLM-free: constructs the exact registry `runCodingAgentOnce` wires for
/// `meaningProfile: true` and meters it. Publishes the row the results doc
/// cites (the printed lines ARE the row's source).
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot, JailWriteGateway, WriteGateMode, runTool;
import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart'
    show editSymbolTool, meaningSpanReader, repoEtlTool, writeReviewTool;

import 'package:xsoulspace_inference_apple_foundation/src/coding_agent_runner.dart'
    show meaningProfileSystemPrompt;

/// The P1 pre-flight budget (AppleFoundationNativeClient.maxContextTokens).
const afmBudgetTokens = 3800;

/// The harness fixed-overhead target. The 5-tool pre-fs-tier surface
/// measured 1408; ADR 0024 (as amended) added the fs tier (+2 tools:
/// span-cut zoom + the consent-gated write_review escape hatch) — the
/// measured row is the binding number. The hard constraints below (AFM
/// window fit; working memory ≥ 2000) are unchanged.
const fixedOverheadTarget = 1600;

void main() {
  test(
    'meaning-profile fixed overhead fits the AFM window; edit_symbol is '
    'the largest schema; nothing to cut but the cut',
    () {
      final world = World()..addPlugin(AgentPlugin());
      world.upsertResource(ToolRegistryResource());
      final jail = Directory.systemTemp.createTempSync('overhead_probe_');
      addTearDown(() => jail.deleteSync(recursive: true));

      // The EXACT meaning-profile registry runCodingAgentOnce wires
      // (meaningProfile: true, with a consent approver) — one truth, not a
      // rebuilt list. The fs tier (ADR 0024): span cuts via the span reader
      // + the consent-gated escape hatch (write_review).
      final fsRoot = FsToolsRoot(jail.path);
      final gateway = JailWriteGateway(
        fsRoot,
        mode: WriteGateMode.review,
        approver: (w) async => true,
      );
      final registry = ToolRegistry();
      registry.register(repoEtlTool(world, jail));
      registry.register(
        meaningZoomTool(world, spanReader: meaningSpanReader(fsRoot)),
      );
      registry.register(meaningImpactTool(world));
      registry.register(editSymbolTool(world, jail));
      registry.register(writeReviewTool(fsRoot, gateway));
      registry.register(runTool(fsRoot));

      final tools = registry.tools.values.toList();
      final systemTokens = overheadTokens(
        systemPrompt: meaningProfileSystemPrompt,
        tools: const [],
      );
      final perTool = {
        for (final t in tools)
          t.name.value: overheadTokens(systemPrompt: '', tools: [t]),
      };
      final total = overheadTokens(
        systemPrompt: meaningProfileSystemPrompt,
        tools: tools,
      );
      final workingMemory = afmBudgetTokens - total;

      // The published row (results_r7.md cites this printout).
      // ignore: avoid_print
      print('R7 production #2 — meaning-profile overhead row');
      // ignore: avoid_print
      print('tokens source: overheadTokens (chars/4, the harness estimator)');
      // ignore: avoid_print
      print('system prompt (meaningProfileSystemPrompt): $systemTokens');
      for (final entry in perTool.entries) {
        // ignore: avoid_print
        print('tool ${entry.key}: ${entry.value}');
      }
      // ignore: avoid_print
      print('FIXED OVERHEAD TOTAL: $total tokens');
      // ignore: avoid_print
      print(
        'AFM window (P1 maxContextTokens): $afmBudgetTokens → '
        'working memory left for cut+transcript: $workingMemory',
      );

      // edit_symbol is the largest schema (the expected lever if the row
      // ever stops fitting — lean schemas, never the law).
      expect(perTool['edit_symbol'], isNotNull);
      for (final entry in perTool.entries) {
        if (entry.key == 'edit_symbol') continue;
        expect(
          perTool['edit_symbol']!,
          greaterThanOrEqualTo(entry.value),
          reason: 'edit_symbol should be the largest schema; '
              '${entry.key}=${entry.value}',
        );
      }

      // The law of the row: the fixed surface fits the AFM window WITH the
      // harness fixed-overhead target honored — the surface needs no
      // further cutting to reach R7e; only the cut budget is a free
      // parameter (coderLean / ProjectionBudget), never the schemas.
      expect(total, lessThanOrEqualTo(afmBudgetTokens));
      expect(total, lessThanOrEqualTo(fixedOverheadTarget));
      expect(workingMemory, greaterThanOrEqualTo(2000));
    },
  );
}
